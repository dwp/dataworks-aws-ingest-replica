#!/usr/bin/python3
import argparse
import base64
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

LOG_PATH = "${log_path}"
cache = {}


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


_logger = setup_logging(
    log_level="INFO",
    log_path=LOG_PATH,
)


def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )
    # Parse command line inputs and set defaults
    parser.add_argument("--correlation_id", default=0, type=int)
    parser.add_argument("--collections", type=str, nargs="+")
    parser.add_argument("--start_time", default=0, type=int)
    parser.add_argument(
        "--end_time",
        default=int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000),
        type=int,
    )
    args, unrecognized_args = parser.parse_known_args()

    return args


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
    requests_session.mount("http://", adapter)
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


def get_key_from_cache(kek):
    if kek in cache:
        return cache[kek]

def get_plaintext_key(url, kek, cek):
    plaintext_key = None

    """Call DKS to return decrypted datakey."""
    request = retry_requests(methods=["POST"])

    plaintext_key = get_key_from_cache(kek)

    if not plaintext_key:
        response = request.post(
            DKS_DECRYPT_ENDPOINT,
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
        cache[f"{kek}"] = plaintext_key
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
    return json.dumps(json_item)


def filter_rows(x):
    if x:
        return str(x).find("column=") > -1
    else:
        return False


def process_record(x):
    y = [str.strip(i) for i in re.split(r" *column=|, *timestamp=|, *value=", x)]
    record_id = y[0]
    timestamp = y[2]
    record = decrypt_message(y[3])
    return [record_id, timestamp, record]


def list_to_csv_str(x):
    output = io.StringIO("")
    csv.writer(output).writerow(x)
    return output.getvalue().strip()


def process_collection(
    collection, spark, start_time, end_time, s3_root_path, business_date_hour
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

    s3_collection_dir = s3_root_path + hive_table_name + "/"
    s3_output_dir = s3_collection_dir + business_date_hour + "/"
    rdd.saveAsTextFile(s3_output_dir)
    num_records = rdd.count()
    return hive_table_name, s3_collection_dir, num_records


def create_hive_table(collection_tuple):
    table_name, s3_path, _ = collection_tuple
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
    _logger.warning(create_view)
    spark.sql(drop_view)
    spark.sql(create_view)


def main(spark, collections, start_time, end_time, s3_root_path, business_date_hour):
    replica_metadata_refresh()

    try:
        with concurrent.futures.ThreadPoolExecutor() as executor:
            all_collections = list(
                executor.map(
                    process_collection,
                    collections,
                    itertools.repeat(spark),
                    itertools.repeat(start_time),
                    itertools.repeat(end_time),
                    itertools.repeat(s3_root_path),
                    itertools.repeat(business_date_hour),
                )
            )
    except Exception as e:
        _logger.error(e)
        raise e

    total_records = sum([i[2] for i in all_collections])

    # create Hive tables
    with concurrent.futures.ThreadPoolExecutor() as executor:
        executor.map(create_hive_table, list(all_collections))

    return total_records


if __name__ == "__main__":
    args = get_parameters()
    start_time = args.start_time
    end_time = args.end_time
    collections = list(args.collections)
    spark = SparkSession.builder.enableHiveSupport().getOrCreate()

    business_date_hour = datetime.datetime.fromtimestamp(end_time / 1000.0).strftime(
        "%Y%m%d-%H%M"
    )
    s3_root_path = f"s3://{INCREMENTAL_OUTPUT_BUCKET}/{INCREMENTAL_OUTPUT_PREFIX}"
    perf_start = time.perf_counter()
    total_records = main(
        spark, collections, start_time, end_time, s3_root_path, business_date_hour
    )

    perf_end = time.perf_counter()
    total_time = round(perf_end - perf_start)
    _logger.info(
        f"time taken to process collections: {total_records} records"
        + f" in {total_time}s"
    )
