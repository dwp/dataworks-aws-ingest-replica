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
from argparse import ArgumentError

import boto3
import botocore.config
import requests
from Crypto import Random
from Crypto.Cipher import AES
from Crypto.Util import Counter
from boto3.dynamodb.conditions import Attr, Key
from requests.adapters import HTTPAdapter
from requests.packages.urllib3 import Retry

if __name__=="__main__":
    from pyspark import AccumulatorParam
    from pyspark.sql import SparkSession

DKS_ENDPOINT = "${dks_decrypt_endpoint}"
DKS_DECRYPT_ENDPOINT = DKS_ENDPOINT + "/datakey/actions/decrypt/"

INCREMENTAL_OUTPUT_BUCKET = "${incremental_output_bucket}"
INCREMENTAL_OUTPUT_PREFIX = "${incremental_output_prefix}"

JOB_STATUS_TABLE = "${job_status_table_name}"
COLLECTIONS_SECRET_NAME = "${collections_secret_name}"
DATABASE_NAME = "intraday"

LOG_PATH = "${log_path}"
dks_cache = {}


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


def ms_epoch_now():
    return round(time.time() * 1000) - (5 * 60 * 1000)


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
    sub_p = parser.add_subparsers(dest="job_type")
    p_scheduled = sub_p.add_parser("scheduled", description="Run scheduled execution")
    p_manual = sub_p.add_parser("manual", description="Run manual execution")

    # Scheduled
    p_scheduled.add_argument("--correlation_id", type=str, required=True)
    p_scheduled.add_argument("--triggered_time", type=int, required=True)
    p_scheduled.add_argument("--collections", type=str, nargs="+", required=True)
    p_scheduled.add_argument("--database_name", type=str, default="intra_day")
    p_scheduled.add_argument("--end_time", type=int, required=True)
    p_scheduled.add_argument(
        "--output_s3_bucket", type=str, default=INCREMENTAL_OUTPUT_BUCKET
    )
    p_scheduled.add_argument(
        "--output_s3_prefix", type=str, default=INCREMENTAL_OUTPUT_PREFIX
    )

    # Manual
    p_manual.add_argument("--correlation_id", type=str, required=True)
    p_manual.add_argument("--collections", type=str, nargs="+", required=True)
    p_manual.add_argument("--start_time", type=int, default=0)
    p_manual.add_argument("--end_time", type=int)
    p_manual.add_argument("--triggered_time", type=int)
    p_manual.add_argument(
        "--output_s3_bucket", type=str, default=INCREMENTAL_OUTPUT_BUCKET
    )
    p_manual.add_argument("--output_s3_prefix", type=str, required=True)

    args, unrecognized_args = parser.parse_known_args()
    return args


def get_s3_client():
    """Return S3 client"""
    client_config = botocore.config.Config(
        max_pool_connections=100, retries={"max_attempts": 10, "mode": "standard"}
    )
    client = boto3.client("s3", config=client_config)
    return client


def update_db_with_success(table, correlation_id, max_timestamps, bulk_values=None):
    """Updates each collection with its max_timestamp, updates all collections
    with any bulk_values provided"""
    collection_update_values = {
        collection: {"ProcessedDataEnd": max_timestamp}
        for collection, max_timestamp in max_timestamps.items()
    }

    for values_dict in collection_update_values.values():
        values_dict.update(bulk_values)

    update_db_per_collection(table, correlation_id, collection_update_values)


def update_db_bulk_collections(table, correlation_id, collections, values: dict):
    """Update dynamo_db with supplied values for collections provided"""
    collections_names = [i["hbase_table"] for i in collections]
    for collection in collections_names:
        _update_db_collection(table, correlation_id, collection, values)


def update_db_per_collection(
    table, correlation_id, values_per_collection: dict, bulk_values: dict = None
):
    """Update dynamodb with supplied collection-specific values  Bulk values
    will overwrite per-collection values."""
    if bulk_values:
        for collection, values in values_per_collection.items():
            values.update(bulk_values)

    for collection, values in values_per_collection.items():
        _update_db_collection(table, correlation_id, collection, values)


def _update_db_collection(table, correlation_id, collection, values: dict):
    updates = {key: {"Value": value} for key, value in values.items()}
    table.update_item(
        Key={
            "CorrelationId": correlation_id,
            "Collection": collection,
        },
        AttributeUpdates=updates,
    )


def get_start_timestamp(collection, args, job_table=None):
    # different scenarios for test / tracked / manual executions
    if args.job_type == "scheduled" and job_table is not None:
        # get timestamp from dynamodb
        start_time = get_last_processed_dynamodb(collection, job_table) + 1
    elif args.start_time:
        # use args.start_time
        start_time = args.start_time
    else:
        raise ArgumentError(message="start_time not provided", argument=args.start_time)
    return start_time


def get_last_processed_dynamodb(collection, job_table):
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
            f"DB Item does not include attribute 'ProcessedDataEnd'.  Ensure"
            f" this is present for collection {collection}"
        )
        raise


def get_collections(args, job_table=None):
    """Parse collections and add required information"""
    timestamp_folder = datetime.datetime.fromtimestamp(
        args.triggered_time / 1000.0
    ).strftime("%Y%m%d-%H%M")

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

    for collection in collections:
        if args.job_type == "scheduled":
            start_time = get_start_timestamp(collection["hbase_table"], args, job_table)
        else:
            start_time = args.start_time
        coll_prefix = os.path.join(args.output_s3_prefix, collection["hive_table"])
        full_prefix = os.path.join(coll_prefix, timestamp_folder)

        collection.update(
            {
                "start_time": start_time,
                "output_bucket": args.output_s3_bucket,
                "output_root_prefix": args.output_s3_prefix,
                "collection_output_prefix": coll_prefix,
                "full_output_prefix": full_prefix,
            }
        )

    if len(collections) < 1:
        raise IndexError("No collections provided")
    return collections


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


def get_plaintext_key(url, kek, cek, dks_count_acc):
    plaintext_key = dks_cache.get(cek)
    if not plaintext_key:
        dks_count_acc.add(1)
        plaintext_key = get_key_from_dks(url, kek, cek)
        dks_cache[cek] = plaintext_key
    return plaintext_key


def get_key_from_dks(url, kek, cek):
    """Call DKS to return decrypted datakey."""
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
    return plaintext_key


def decrypt_ciphertext(ciphertext, key, iv):
    """Decrypt ciphertext using key & iv."""
    iv_int = int(binascii.hexlify(base64.b64decode(iv)), 16)
    counter = Counter.new(AES.block_size * 8, initial_value=iv_int)
    aes = AES.new(base64.b64decode(key), AES.MODE_CTR, counter=counter)
    return aes.decrypt(base64.b64decode(ciphertext)).decode("utf8")


def decrypt_message(item, dks_count_acc):
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
        dks_count_acc,
    )

    # decrypt object using plaintext data key
    decrypted_obj = decrypt_ciphertext(db_obj, plaintext_key, iv)
    return record_id, decrypted_obj


def filter_rows(x):
    if x:
        return str(x).find("column=") > -1
    else:
        return False


def process_record(x, table_name, accumulators):
    y = [str.strip(i) for i in re.split(r" *column=|, *timestamp=|, *value=", x)]
    timestamp = y[2]
    record_id, record = decrypt_message(y[3], accumulators["dks_count"])
    accumulators["record_count"].add(1)
    accumulators["max_timestamps"].add({table_name: int(timestamp)})
    return [record_id, timestamp, record]


def list_to_csv_str(x):
    output = io.StringIO("")
    csv.writer(output).writerow(x)
    return output.getvalue().strip()


def process_collection(
    collection_info, spark, end_time, accumulators, update_dynamodb=False
):
    """Extract collection from hbase, decrypt, put in S3."""
    hbase_table_name = collection_info["hbase_table"]
    hive_table_name = collection_info["hive_table"]
    start_time = collection_info["start_time"]

    accumulators["max_timestamps"].add({hbase_table_name: None})
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
        .map(lambda x: process_record(x, hbase_table_name, accumulators))
        .map(list_to_csv_str)
    )
    rdd.saveAsTextFile(
        "s3://"
        + os.path.join(
            collection_info["output_bucket"],
            collection_info["full_output_prefix"],
        ),
        compressionCodecClass="com.hadoop.compression.lzo.LzopCodec",
    )
    return collection_info


def create_hive_table(spark, database_name, collection):
    """Create hive table + 'latest' view over data in s3"""
    hive_table = collection["hive_table"]
    s3_path = "s3://" + os.path.join(
        collection["output_bucket"],
        collection["collection_output_prefix"],
    )

    # sql to ensure db exists
    create_db = f"create database if not exists {database_name}"

    # sql for creating table over s3 data
    drop_table = f"drop table if exists {database_name}.{hive_table}"
    create_table = f"""
    create external table if not exists {database_name}.{hive_table}
        (id string, record_timestamp string, record string)
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
           WITH SERDEPROPERTIES ( 
           "separatorChar" = ",",
           "quoteChar"     = "\\""
                  )
        stored as textfile location "{s3_path}"
    """

    drop_view = f"drop view if exists {database_name}.v_{hive_table}_latest"
    create_view = f"""
        create view {database_name}.v_{hive_table}_latest as with ranked as (
        select  id,
                record_timestamp,
                record, 
                row_number() over (
                    partition by id 
                    order by id desc, cast(record_timestamp as bigint) desc
                ) RANK
        from {database_name}.{hive_table})
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


def main(spark, end_time, database_name, collections, s3_client, accumulators, update_dynamodb=False):
    replica_metadata_refresh()
    try:
        with concurrent.futures.ThreadPoolExecutor() as executor:
            processed_collections = list(
                executor.map(
                    process_collection,
                    collections,
                    itertools.repeat(spark),
                    itertools.repeat(end_time),
                    itertools.repeat(accumulators),
                    itertools.repeat(update_dynamodb),
                )
            )
    except Exception as e:
        _logger.error(e)
        raise e

    # create Hive tables
    with concurrent.futures.ThreadPoolExecutor() as executor:
        _ = list(
            executor.map(
                create_hive_table,
                itertools.repeat(spark),
                itertools.repeat(database_name),
                list(processed_collections)
            )
        )

    # tag files
    with concurrent.futures.ThreadPoolExecutor() as executor:
        _ = list(
            executor.map(
                tag_s3_objects, itertools.repeat(s3_client), processed_collections
            )
        )


def get_job_status_table():
    return boto3.resource("dynamodb").Table(JOB_STATUS_TABLE)


def scheduled_handler(args, cluster_id):
    # boto3
    job_table = get_job_status_table()
    s3_client = get_s3_client()

    # spark
    spark = SparkSession.builder.enableHiveSupport().getOrCreate()
    dks_count = spark.sparkContext.accumulator(0)
    record_count = spark.sparkContext.accumulator(0)
    max_timestamps = spark.sparkContext.accumulator(dict(), DictAccumulatorParam())
    accumulators = {
        "dks_count": dks_count,
        "record_count": record_count,
        "max_timestamps": max_timestamps,
    }

    # main
    collections = get_collections(args, job_table)

    start_times = {
        collection["hbase_table"]: {"ProcessedDataStart": collection["start_time"]}
        for collection in collections
    }
    update_db_per_collection(
        table=job_table,
        correlation_id=args.correlation_id,
        values_per_collection=start_times,
        bulk_values={
            "JobStatus": EMRStates["PROCESSING"],
            "EMRReadyTime": round(time.time() * 1000),
            "EMRClusterId": cluster_id,
            "TriggeredTime": args.triggered_time,
        },
    )
    perf_start = time.perf_counter()
    try:
        main(
            spark=spark,
            end_time=args.end_time,
            database_name=args.database_name,
            collections=collections,
            s3_client=s3_client,
            accumulators=accumulators,
            update_dynamodb=True,
        )
        update_db_with_success(
            table=job_table,
            correlation_id=args.correlation_id,
            max_timestamps=max_timestamps.value,
            bulk_values={"JobStatus": EMRStates["COMPLETED"]},
        )
        perf_end = time.perf_counter()
        total_time = round(perf_end - perf_start)

    except Exception as e:
        _logger.error(f"Failed to process collections")
        update_db_bulk_collections(
            table=job_table,
            correlation_id=args.correlation_id,
            collections=collections,
            values={"JobStatus": EMRStates["EMR_FAILED"]},
        )
        raise e

    _logger.info(
        f"time taken to process collections: {record_count.value} records"
        + f" in {total_time}s.  {dks_count.value} calls to DKS"
    )


def manual_handler(args):
    # boto3
    s3_client = get_s3_client()

    # spark
    spark = SparkSession.builder.enableHiveSupport().getOrCreate()
    dks_count = spark.sparkContext.accumulator(0)
    record_count = spark.sparkContext.accumulator(0)
    max_timestamps = spark.sparkContext.accumulator(dict(), DictAccumulatorParam())
    accumulators = {
        "dks_count": dks_count,
        "record_count": record_count,
        "max_timestamps": max_timestamps,
    }

    # main
    collections = get_collections(args)
    perf_start = time.perf_counter()
    try:
        main(
            spark=spark,
            end_time=args.end_time,
            database_name=args.database_name,
            collections=collections,
            s3_client=s3_client,
            accumulators=accumulators,
            update_dynamodb=False,
        )
        perf_end = time.perf_counter()
        total_time = round(perf_end - perf_start)

    except Exception as e:
        _logger.error(f"Failed to process collections")
        raise e

    _logger.info(
        f"time taken to process collections: {record_count.value} records"
        + f" in {total_time}s.  {dks_count.value} calls to DKS"
    )


if __name__ == "__main__":
    _logger = setup_logging(
        log_level="INFO",
        log_path=LOG_PATH,
    )
    cluster_id = os.environ.get("EMR_CLUSTER_ID")
    args = get_parameters()

    args.triggered_time = (
        ms_epoch_now() if args.triggered_time is None else args.triggered_time
    )

    if args.job_type == "scheduled":
        scheduled_handler(args, cluster_id)
    elif args.job_type == "manual":
        manual_handler(args)
    else:
        raise ArgumentError(args.job_type, "Unrecognised job_type")
