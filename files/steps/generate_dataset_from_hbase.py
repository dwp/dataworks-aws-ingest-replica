#!/usr/bin/python3
import argparse
import ast
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

import boto3
import botocore.config
import requests
from Crypto import Random
from Crypto.Cipher import AES
from Crypto.Util import Counter
from boto3.dynamodb.conditions import Attr, Key


from pyspark import AccumulatorParam
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
max_timestamps = None

EMRStates = {
    "TRIGGERED": "LAMBDA_TRIGGERED",  # this lambda was triggered
    "WAITING": "WAITING",  # this lambda is waiting up to 10 minutes for another cluster
    "DEFERRED": "DEFERRED",  # this lambda timed out waiting, did not launch emr
    "LAUNCHED": "EMR_LAUNCHED",  # this lambda posted to SNS topic to launch EMR cluster
    "PROCESSING": "EMR_PROCESSING",  # emr cluster has started processing data
    "COMPLETED": "EMR_COMPLETED",  # emr cluster processed the data successfully
    "EMR_FAILED": "EMR_FAILED",  # emr cluster couldn't process data successfully
    "LAMBDA_FAILED": "LAMBDA_FAILED",  # lambda encountered an error
}


class DictAccumulatorParam(AccumulatorParam):
    def zero(self, v):
        return v.copy()

    def addInPlace(self, d1, d2):
        for key, value in d2.items():
            if not d1.get(key):
                d1.update({key: value})
            elif value:
                d1.update({key: max(value, d1.get(key, value))})
        return d1


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
    parser.add_argument("--test", dest="test", action="store_true")
    parser.add_argument("--tracked", dest="tracked", action="store_true")
    parser.add_argument("--correlation_id", default="0", type=str)
    parser.add_argument("--triggered_time", default=0, type=int)
    parser.add_argument(
        "--output_s3_bucket", default=INCREMENTAL_OUTPUT_BUCKET, type=str
    )
    parser.add_argument(
        "--output_s3_prefix", default=INCREMENTAL_OUTPUT_PREFIX, type=str
    )
    parser.add_argument("--collections", type=str, nargs="+")
    parser.add_argument("--start_time", type=int)
    parser.add_argument(
        "--end_time", default=round(time.time() * 1000) - (5 * 60 * 1000), type=int
    )
    parser.add_argument("--log_path", default=LOG_PATH, type=str)
    parser.set_defaults(dry_run=False, test=False, tracked=False)
    args, unrecognized_args = parser.parse_known_args()

    if args.test is True:
        if args.tracked is True:
            raise Exception("Cannot use --tracked and --test flags together")
        global DATABASE_NAME
        DATABASE_NAME += "_tests"
    return args


def get_s3_client():
    """Return S3 client"""
    client_config = botocore.config.Config(
        max_pool_connections=100, retries={"max_attempts": 10, "mode": "standard"}
    )
    client = boto3.client("s3", config=client_config)
    return client


def update_db_with_success(table, args, max_timestamps, bulk_values=None):
    """Updates each collection with its max_timestamp, updates all collections
    with any bulk_values provided"""
    if args.tracked is True and args.test is False:
        collection_update_values = {
            collection: {"ProcessedDataEnd": max_timestamp}
            for collection, max_timestamp in max_timestamps.items()
        }

        for values_dict in collection_update_values.values():
            values_dict.update(bulk_values)

        update_db_per_collection(table, args.correlation_id, collection_update_values)


def update_db_bulk_collections(table, args, collections, values: dict):
    """Update dynamo_db with supplied values for collections provided"""
    if args.tracked is True and args.test is False:
        collections_names = [i["hbase_table"] for i in collections]
        for collection in collections_names:
            _update_db_collection(table, args.correlation_id, collection, values)


def update_db_per_collection(table, correlation_id, values_per_collection: dict):
    """Update dynamodb with supplied collection-specific values"""
    if args.tracked is True and args.test is False:
        for collection, values in values_per_collection.items():
            _update_db_collection(table, correlation_id, collection, values)


def _update_db_collection(table, correlation_id, collection, values: dict):
    """Not intended to be called directly, does not check whether updates to db are
    required"""
    updates = {key: {"Value": value} for key, value in values.items()}
    table.update_item(
        Key={
            "CorrelationId": correlation_id,
            "Collection": collection,
        },
        AttributeUpdates=updates,
    )


def get_last_processed_timestamp(collection, job_table):
    results = job_table.query(
        IndexName="byCollection",
        ProjectionExpression="ProcessedDataEnd",
        KeyConditionExpression=Key("Collection").eq(collection),
        FilterExpression=Attr("JobStatus").eq(str(EMRStates["COMPLETED"]))
        & Attr("ProcessedDataEnd").ne(None),
        ScanIndexForward=False,
    )

    try:
        return int(results["Items"][0]["ProcessedDataEnd"])
    except IndexError:
        if results["Count"] == 0:
            _logger.error(
                f"No results in db for collection {collection}, populate db "
                f"with ProcesssedDataEnd - use 0 timestamp to process whole "
                f"collection"
            )
        raise
    except KeyError:
        _logger.error(
            f"DB Item does not include attribute 'ProcesssedDataEnd'.  Ensure"
            f" this is present for collection {collection}"
        )
        raise


def get_collections(args, job_table):
    """Get collections and required information either from args, or from AWS Secrets"""
    timestamp_folder = datetime.datetime.fromtimestamp(args.end_time / 1000.0).strftime(
        "%Y%m%d-%H%M"
    )
    if args.collections:
        # Assume PII, parse table/db names for tags
        collections = [
            {
                "hbase_table": collection,
                "hive_table": collection.replace(":", "_"),
                "tags": {
                    "pii": "true",
                    "db": collection.split(":")[0],
                    "table": collection.split(":")[1],
                },
            }
            for collection in args.collections
        ]
    else:
        collections = get_collections_from_aws(COLLECTIONS_SECRET_NAME)

    for collection in collections:
        collection.update(
            {
                "start_time": get_last_processed_timestamp(
                    collection["hbase_table"], job_table
                )
                + 1
                if not args.start_time
                else args.start_time,
                "output_bucket": args.output_s3_bucket,
                "output_root_prefix": args.output_s3_prefix,
                "collection_output_prefix": os.path.join(
                    args.output_s3_prefix, collection["hive_table"]
                ),
                "full_output_prefix": os.path.join(
                    args.output_s3_prefix, collection["hive_table"], timestamp_folder
                ),
            }
        )

    return collections


def get_collections_from_aws(collections_secret_name):
    """Parse collections returned by AWS Secrets Manager"""
    return [
        {
            "hbase_table": f"{j['db']}:{j['table']}",
            "hive_table": f"{j['db']}_{j['table']}",
            "tags": j,
        }
        for j in retrieve_secrets(collections_secret_name)[
            "collections_all"
        ].values()
    ]


def retrieve_secrets(secret_name):
    """Get b64 encoded secrets from AWS Secrets Manager"""
    secrets_client = boto3.client("secretsmanager")
    response = secrets_client.get_secret_value(SecretId=secret_name)
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
    plaintext_key = dks_cache.get(cek)
    if not plaintext_key:
        plaintext_key = get_key_from_dks(url, kek, cek)
        dks_cache[cek] = plaintext_key
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
    """Find and decrypt dbObject, return tuple containing record ID and decrypted
    db_object."""
    json_item = json.loads(item)
    record_id = json_item["message"]["_id"]

    # get encryption materials
    iv = json_item["message"]["encryption"]["initialisationVector"]
    cek = json_item["message"]["encryption"]["encryptedEncryptionKey"]
    kek = json_item["message"]["encryption"]["keyEncryptionKeyId"]
    # get encrypted db_object
    db_obj = json_item["message"]["dbObject"]

    # decrypt data key using cache/dks
    plaintext_key = get_plaintext_key(
        DKS_DECRYPT_ENDPOINT,
        kek,
        cek,
    )

    # decrypt object using plaintext data key
    decrypted_obj = decrypt_ciphertext(db_obj, plaintext_key, iv)
    return record_id, decrypted_obj


def filter_rows(x):
    if x:
        return str(x).find("column=") > -1
    else:
        return False


def process_record(x, table_name):
    global record_count
    global max_timestamps
    y = [str.strip(i) for i in re.split(r" *column=|, *timestamp=|, *value=", x)]
    timestamp = y[2]
    record_id, record = decrypt_message(y[3])
    record_count.add(1)
    max_timestamps.add({table_name: int(timestamp)})
    return [record_id, timestamp, record]


def list_to_csv_str(x):
    output = io.StringIO("")
    csv.writer(output).writerow(x)
    return output.getvalue().strip()


def process_collection(
    collection,
    spark,
    args,
):
    """Extract collection from hbase, decrypt, put in S3."""
    hbase_table_name = collection["hbase_table"]
    hive_table_name = collection["hive_table"]
    start_time = collection["start_time"]
    end_time = args.end_time

    max_timestamps.add({hbase_table_name: None})

    table = boto3.resource("dynamodb").Table(JOB_STATUS_TABLE)
    update_db_per_collection(
        table=table,
        correlation_id=args.correlation_id,
        values_per_collection={hbase_table_name: {"ProcessedDataStart": start_time}},
    )

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
        .map(lambda x: process_record(x, hbase_table_name))
        .map(list_to_csv_str)
    )
    rdd.saveAsTextFile(
        "s3://"
        + os.path.join(
            collection["output_bucket"],
            collection["full_output_prefix"],
        ),
        compressionCodecClass="com.hadoop.compression.lzo.LzopCodec",
    )
    return collection


def create_hive_table(collection):
    """Create hive table + 'latest' view over data in s3"""
    hive_table = collection["hive_table"]
    s3_path = "s3://" + os.path.join(
        collection["output_bucket"],
        collection["collection_output_prefix"],
    )

    # sql to ensure db exists
    create_db = f"create database if not exists {DATABASE_NAME}"

    # sql for creating table over s3 data
    drop_table = f"drop table if exists {DATABASE_NAME}.{hive_table}"
    create_table = f"""
    create external table if not exists {DATABASE_NAME}.{hive_table}
        (id string, record_timestamp string, record string)
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
           WITH SERDEPROPERTIES ( 
           "separatorChar" = ",",
           "quoteChar"     = "\\""
                  )
        stored as textfile location "{s3_path}"
    """

    drop_view = f"drop view if exists {DATABASE_NAME}.v_{hive_table}_latest"
    create_view = f"""
        create view {DATABASE_NAME}.v_{hive_table}_latest as with ranked as (
        select  id,
                record_timestamp,
                record, 
                row_number() over (
                    partition by id 
                    order by id desc, cast(record_timestamp as bigint) desc
                ) RANK
        from {DATABASE_NAME}.{hive_table})
        select id, record_timestamp, record from ranked where RANK = 1
        """

    spark.sql(create_db)
    try:
        spark.sql(drop_view)
        spark.sql(drop_table)
    except Exception as e:
        _logger.error(e)
    spark.sql(create_table)
    spark.sql(create_view)


def tag_s3_objects(s3_client, collection):
    _logger.info(f"{collection['hive_table']}: tagging files")
    i = 0
    aws_format_tags = [
        {"Key": key, "Value": value} for key, value in collection["tags"].items()
    ]

    for key in s3_client.list_objects(
        Bucket=collection["output_bucket"], Prefix=collection["full_output_prefix"]
    )["Contents"]:
        s3_client.put_object_tagging(
            Bucket=collection["output_bucket"],
            Key=key["Key"],
            Tagging={"TagSet": aws_format_tags},
        )
        i += 1
    _logger.info(f"{collection['hive_table']}: tagging complete, {i} objects")


def main(spark, args, collections, s3_client):
    replica_metadata_refresh()
    try:
        with concurrent.futures.ThreadPoolExecutor() as executor:
            processed_collections = list(
                executor.map(
                    process_collection,
                    collections,
                    itertools.repeat(spark),
                    itertools.repeat(args),
                )
            )
    except Exception as e:
        _logger.error(e)
        raise e

    # create Hive tables
    with concurrent.futures.ThreadPoolExecutor() as executor:
        _ = list(executor.map(create_hive_table, list(processed_collections)))

    # tag files
    with concurrent.futures.ThreadPoolExecutor() as executor:
        _ = list(
            executor.map(
                tag_s3_objects, itertools.repeat(s3_client), processed_collections
            )
        )


if __name__ == "__main__":
    _logger = setup_logging(
        log_level="INFO",
        log_path=LOG_PATH,
    )
    cluster_id = os.environ["EMR_CLUSTER_ID"]
    args = get_parameters()

    if args.dry_run is True:
        _logger.warning("Dry Run Flag (-d, --dry-run) set, exiting with success status")
        exit(0)

    dynamodb = boto3.resource("dynamodb")
    job_table = dynamodb.Table(JOB_STATUS_TABLE)
    collections = get_collections(args=args, job_table=job_table)

    if len(collections) == 0:
        _logger.warning("No collections to process, exiting")
        exit(0)

    s3_client = get_s3_client()
    spark = SparkSession.builder.enableHiveSupport().getOrCreate()
    dks_count = spark.sparkContext.accumulator(0)
    record_count = spark.sparkContext.accumulator(0)
    max_timestamps = spark.sparkContext.accumulator(dict(), DictAccumulatorParam())

    update_db_bulk_collections(
        table=job_table,
        args=args,
        collections=collections,
        values={
            "JobStatus": EMRStates["PROCESSING"],
            "EMRReadyTime": round(time.time() * 1000),
            "EMRClusterId": cluster_id,
        },
    )

    perf_start = time.perf_counter()
    try:
        main(spark=spark, args=args, collections=collections, s3_client=s3_client)
        update_db_with_success(
            table=job_table,
            args=args,
            max_timestamps=max_timestamps.value,
            bulk_values={"JobStatus": EMRStates["COMPLETED"]},
        )
        perf_end = time.perf_counter()
        total_time = round(perf_end - perf_start)
    except Exception as e:
        _logger.error(f"Failed to process collections")
        update_db_bulk_collections(
            table=job_table,
            args=args,
            collections=collections,
            values={"JobStatus": EMRStates["EMR_FAILED"]},
        )
        raise e

    _logger.info(
        f"time taken to process collections: {record_count.value} records"
        + f" in {total_time}s.  {dks_count.value} calls to DKS"
    )
