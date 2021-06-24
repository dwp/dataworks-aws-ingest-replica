#!/usr/bin/python3
import argparse
import ast
import base64
import boto3
import binascii
import concurrent.futures
import csv
import datetime
import io
import itertools
import json
import logging
import os
import re
import sys
import time

import requests
from Crypto import Random
from Crypto.Cipher import AES
from Crypto.Util import Counter

if __name__ == "__main__":
    from pyspark.sql import SparkSession
from requests.adapters import HTTPAdapter
from requests.packages.urllib3 import Retry

DKS_ENDPOINT = "${dks_decrypt_endpoint}"
DKS_DECRYPT_ENDPOINT = DKS_ENDPOINT + "/datakey/actions/decrypt/"

INCREMENTAL_OUTPUT_BUCKET = "${incremental_output_bucket}"
INCREMENTAL_OUTPUT_PREFIX = "${incremental_output_prefix}"

JOB_STATUS_TABLE = "${job_status_table_name}"
COLLECTIONS_SECRET_NAME = "${collections_secret_name}"
DATABASE_NAME = "intraday"

LOG_PATH = "${log_path}"
dks_cache = {}

# pyspark accumulators
dks_count = None
record_count = None


def setup_logging(log_level, log_path):
    logger = logging.getLogger()
    for old_handler in logger.handlers:
        logger.removeHandler(old_handler)

    if log_path is None:
        handler = logging.StreamHandler(sys.stdout)
    else:
        handler = logging.FileHandler(log_path)

    json_format = (
        "{ 'timestamp': '%(asctime)s', 'log_level': '%(levelname)s', 'message': "
        "'%(message)s' } "
    )
    handler.setFormatter(logging.Formatter(json_format))
    logger.addHandler(handler)
    new_level = logging.getLevelName(log_level.upper())
    logger.setLevel(new_level)

    return logger


def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )
    # Parse command line inputs and set defaults
    parser.add_argument("-d", "--dry_run", dest="dry_run", action="store_true")
    parser.add_argument("-e", "--test", dest="test", action="store_true")
    parser.add_argument("--correlation_id", default="0", type=str)
    parser.add_argument("--triggered_time", default=0, type=int)
    parser.add_argument(
        "--output_s3_bucket", default=INCREMENTAL_OUTPUT_BUCKET, type=str
    )
    parser.add_argument(
        "--output_s3_prefix", default=INCREMENTAL_OUTPUT_PREFIX, type=str
    )
    parser.add_argument("--collections", type=str, nargs="+")
    parser.add_argument("--start_time", default=0, type=int)
    parser.add_argument("--end_time", default=round(time.time() * 1000) - (5 * 60 * 1000), type=int)
    parser.add_argument("--log_path", default=LOG_PATH, type=str)
    parser.set_defaults(dry_run=False)
    parser.set_defaults(test=False)
    args, unrecognized_args = parser.parse_known_args()

    if args.test is True:
        global DATABASE_NAME
        DATABASE_NAME += "_tests"
    return args


def update_db_item(table, correlation_id: str, triggered_time: int, values: dict):
    if correlation_id is None or correlation_id in ["0", ""]:
        return

    updates = {key: {"Value": value} for key, value in values.items()}
    table.update_item(
        Key={
            "CorrelationId": correlation_id,
            "TriggeredTime": triggered_time,
        },
        AttributeUpdates=updates,
    )


def get_collections(collections_secret_name):
    return [
        f"{j['db']}:{j['table']}"
        for j in retrieve_secrets(collections_secret_name)["collections_all"].values()
    ]


def retrieve_secrets(secret_name):
    session = boto3.session.Session()
    client = session.client(service_name="secretsmanager")
    response = client.get_secret_value(SecretId=secret_name)
    response_binary = response["SecretString"]
    response_decoded = base64.b64decode(response_binary).decode("utf-8")
    response_dict = ast.literal_eval(response_decoded)
    return response_dict


def replica_metadata_refresh():
    """Refresh replica cluster metadata"""
    os.system("sudo chmod -R a+rwx /var/log/hbase")
    os.system('echo "refresh_meta" | hbase shell')


def retry_requests(retries=10, backoff=1, methods=None):
    if methods is None:
        methods = ["POST"]
    retry_strategy = Retry(
        total=retries,
        backoff_factor=backoff,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=frozenset(methods),
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    requests_session = requests.Session()
    requests_session.mount("https://", adapter)
    return requests_session


def encrypt_plaintext(data_key, plaintext_string, iv=None):
    if iv is None:
        initialisation_vector = Random.new().read(AES.block_size)
        iv_int = int(binascii.hexlify(initialisation_vector), 16)
        iv = base64.b64encode(initialisation_vector)
    else:
        initialisation_vector = base64.b64decode(iv.encode("ascii"))
        iv_int = int(binascii.hexlify(initialisation_vector), 16)
        iv = base64.b64encode(initialisation_vector)

    counter = Counter.new(AES.block_size * 8, initial_value=iv_int)
    aes = AES.new(base64.b64decode(data_key), AES.MODE_CTR, counter=counter)
    ciphertext = aes.encrypt(plaintext_string.encode("utf8"))
    ciphertext = base64.b64encode(ciphertext)

    return ciphertext.decode("ascii"), iv.decode("ascii")


def get_plaintext_key(url, kek, cek):
    plaintext_key = dks_cache.get(kek)
    if not plaintext_key:
        plaintext_key = get_key_from_dks(url, kek, cek)
        dks_cache[kek] = plaintext_key
    return plaintext_key


def get_key_from_dks(url, kek, cek):
    """Call DKS to return decrypted datakey."""
    global dks_count
    request = retry_requests(methods=["POST"])

    response = request.post(
        url,
        params={"keyId": kek, "correlationId": 0},
        data=cek,
        cert=(
            "/etc/pki/tls/certs/private_key.crt",
            "/etc/pki/tls/private/private_key.key",
        ),
        verify="/etc/pki/ca-trust/source/anchors/analytical_ca.pem",
    )
    content = response.json()
    plaintext_key = content["plaintextDataKey"]
    dks_cache[kek] = plaintext_key
    dks_count.add(1)
    return plaintext_key


def decrypt_ciphertext(ciphertext, key, iv):
    """Decrypt ciphertext using key & iv."""
    iv_int = int(binascii.hexlify(base64.b64decode(iv)), 16)
    counter = Counter.new(AES.block_size * 8, initial_value=iv_int)
    aes = AES.new(base64.b64decode(key), AES.MODE_CTR, counter=counter)
    return aes.decrypt(base64.b64decode(ciphertext)).decode("utf8")


def decrypt_message(item):
    """Find and decrypt dbObject, Return full message."""
    json_item = json.loads(item)
    record_id = json_item["message"]["_id"]
    iv = json_item["message"]["encryption"]["initialisationVector"]
    cek = json_item["message"]["encryption"]["encryptedEncryptionKey"]
    kek = json_item["message"]["encryption"]["keyEncryptionKeyId"]
    db_obj = json_item["message"]["dbObject"]

    plaintext_key = get_plaintext_key(
        DKS_DECRYPT_ENDPOINT,
        kek,
        cek,
    )
    decrypted_obj = decrypt_ciphertext(db_obj, plaintext_key, iv)
    json_item["message"]["dbObject"] = json.loads(decrypted_obj)
    del json_item["message"]["encryption"]
    return record_id, json.dumps(json_item)


def filter_rows(x):
    if x:
        return str(x).find("column=") > -1
    else:
        return False


def process_record(x):
    global record_count
    y = [str.strip(i) for i in re.split(r" *column=|, *timestamp=|, *value=", x)]
    timestamp = y[2]
    record_id, record = decrypt_message(y[3])
    record_count.add(1)
    return [record_id, timestamp, record]


def list_to_csv_str(x):
    output = io.StringIO("")
    csv.writer(output).writerow(x)
    return output.getvalue().strip()


def process_collection(
    collection, spark, start_time, end_time, output_root_path, business_date_hour
):
    """Extract collection from hbase, decrypt, put in S3."""
    hbase_table_name = collection
    hive_table_name = collection.replace(":", "_")
    hbase_commands = (
        f"refresh_hfiles '{hbase_table_name}' \n"
        + f"scan '{hbase_table_name}', {{TIMERANGE => [{start_time}, {end_time}]}}"
    )

    os.system(
        f'echo -e "{hbase_commands}" '
        f"| hbase shell  "
        f"| hdfs dfs -put -f - hdfs:///{hive_table_name}"
    )

    rdd = (
        spark.sparkContext.textFile(f"hdfs:///{hive_table_name}")
        .filter(filter_rows)
        .map(process_record)
        .map(list_to_csv_str)
    )

    s3_collection_dir = os.path.join(output_root_path, hive_table_name)
    final_output_dir = os.path.join(s3_collection_dir, business_date_hour) + "/"
    rdd.saveAsTextFile(final_output_dir)
    return hive_table_name, s3_collection_dir


def create_hive_table(collection_tuple):
    table_name, s3_path = collection_tuple
    drop_table = f"drop table if exists {table_name}"
    create_table = (
        f"create external table if not exists {table_name} "
        + "(id string, record_timestamp bigint, record string) "
        + "ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'"
        + "    WITH SERDEPROPERTIES ( "
        + '    "separatorChar" = ",",'
        + '    "quoteChar"     = "\\""'
        + "           )"
        + f'stored as textfile location "{s3_path}"'
    )
    spark.sql(drop_table)
    spark.sql(create_table)

    drop_view = f"drop view if exists v_{table_name}_latest"
    create_view = f"""
                    create view v_{table_name}_latest as with ranked as (
                    select id, record_timestamp, record, row_number() over
                    (partition by id order by id desc, record_timestamp desc) RANK
                    from {table_name})
                    select id, record_timestamp, record from ranked where RANK = 1
                    """
    spark.sql(drop_view)
    spark.sql(create_view)


def main(spark, args, output_root_path, business_date_hour):
    replica_metadata_refresh()

    try:
        with concurrent.futures.ThreadPoolExecutor() as executor:
            all_collections = list(
                executor.map(
                    process_collection,
                    args.collections,
                    itertools.repeat(spark),
                    itertools.repeat(args.start_time),
                    itertools.repeat(args.end_time),
                    itertools.repeat(output_root_path),
                    itertools.repeat(business_date_hour),
                )
            )
    except Exception as e:
        _logger.error(e)
        raise e

    # create Hive tables
    with concurrent.futures.ThreadPoolExecutor() as executor:
        executor.map(create_hive_table, list(all_collections))


if __name__ == "__main__":
    _logger = setup_logging(
        log_level="INFO",
        log_path=LOG_PATH,
    )

    cluster_id = os.environ["EMR_CLUSTER_ID"]
    args = get_parameters()

    if args.dry_run is True:
        # Dry run flag, quit
        _logger.warning("Dry Run Flag (-d, --dry-run) set, exiting with success status")
        _logger.warning("0 rows processed")
        exit(0)

    if not args.collections:
        args.collections = get_collections(COLLECTIONS_SECRET_NAME)
        if len(args.collections) == 0:
            _logger.warning("No collections to process, exiting")
            _logger.warning("0 rows processed")
            exit(0)

    if not args.end_time:
        args.end_time = round(time.time() * 1000) - (5 * 60 * 1000)

    dynamodb = boto3.resource("dynamodb")
    job_table = dynamodb.Table(JOB_STATUS_TABLE)

    output_root_path = f"s3://{args.output_s3_bucket}/{args.output_s3_prefix}"
    spark = SparkSession.builder.enableHiveSupport().getOrCreate()
    # Set Accumulators
    dks_count = spark.sparkContext.accumulator(0)
    record_count = spark.sparkContext.accumulator(0)

    business_date_hour = datetime.datetime.fromtimestamp(
        args.end_time / 1000.0
    ).strftime("%Y%m%d-%H%M")

    update_db_item(
        job_table,
        args.correlation_id,
        args.triggered_time,
        {"JobStatus": "PROCESSING",
         "EMRReadyTime": round(time.time() * 1000),
         "ProcessedDataEnd": int(args.end_time),
         "ProcessedDataStart": int(args.start_time)},
    )
    perf_start = time.perf_counter()
    try:
        main(spark, args, output_root_path, business_date_hour)
        update_db_item(table=job_table,
                       correlation_id=args.correlation_id,
                       triggered_time=args.triggered_time,
                       values={"JobStatus": "COMPLETED"})
    except Exception:
        update_db_item(
            job_table,
            args.correlation_id,
            args.triggered_time,
            {"JobStatus": "EMR_FAILED"},
        )
        raise
    perf_end = time.perf_counter()

    total_time = round(perf_end - perf_start)
    _logger.info(
        f"time taken to process collections: {record_count.value} records"
        + f" in {total_time}s.  {dks_count.value} calls to DKS"
    )
