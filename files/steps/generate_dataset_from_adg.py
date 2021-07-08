import argparse
import csv
import datetime
import io
import itertools
import json
import os.path
from concurrent.futures import ThreadPoolExecutor

from pyspark.sql import SparkSession


def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )

    parser.add_argument("--adg_s3_location", type=str, required=True)
    parser.add_argument("--collections", type=str, nargs="+", required=True)
    parser.add_argument("--output_s3_bucket", type=str, required=True)
    parser.add_argument("--output_s3_prefix", type=str, required=True)

    args, unrecognized_args = parser.parse_known_args()
    return args


def parse_collections(collections, s3_path, s3_bucket, s3_prefix):
    collections = [
        {
            "db": collection.split(":")[0],
            "topic": collection.split(":")[1],
        }
        for collection in collections
    ]

    for collection in collections:
        collection.update(
            {
                "s3_path": os.path.join(s3_path, collection["db"], collection["topic"])
                + "/",
                "output_path": "s3://"
                + os.path.join(
                    s3_bucket, s3_prefix, collection["db"], collection["topic"], "0"
                )
                + "/",
            }
        )
    return collections


def get_rdds(spark, collections):
    for collection in collections:
        collection.update({"rdd": spark.sparkContext.textFile(collection["s3_path"])})


def process_timestamp(timestamp: dict):
    if timestamp is None:
        return 0
    else:
        return round(
            datetime.datetime.strptime(
                timestamp["d_date"], "%Y-%m-%dT%H:%M:%S.%fZ"
            ).timestamp()
            * 1000
        )


def process_rdds(collections):
    """Take a list of collections dictionaries containing rdds and process them"""

    def process_rdd(collection, *functions):
        """Apply function(s) to collection rdd"""
        for function in functions:
            collection["rdd"] = collection["rdd"].map(function)
        return collection

    def process_record(x):
        """function to apply to each record, returns list with id, timestamp, record"""
        record = json.loads(x)
        id = record["_id"]
        timestamp = process_timestamp(record.get("_lastModifiedDateTime", None))
        return [str(x) for x in [id, timestamp, x]]

    def output_csv_string(x):
        output = io.StringIO("")
        csv.writer(output).writerow(x)
        return output.getvalue().strip()

    with ThreadPoolExecutor() as executor:
        _ = list(
            executor.map(
                process_rdd,
                list(collections),
                itertools.repeat(process_record),
                itertools.repeat(output_csv_string),
            )
        )


def output_rdds_from_collections(collections):
    def output_rdd(collection):
        collection["rdd"].saveAsTextFile(
            collection["output_path"],
            compressionCodecClass="com.hadoop.compression.lzo.LzopCodec",
        )

    with ThreadPoolExecutor() as executor:
        _ = list(executor.map(output_rdd, collections))


def main():
    args = get_parameters()
    spark = SparkSession.builder.enableHiveSupport().getOrCreate()
    collections = parse_collections(
        args.collections,
        args.adg_s3_location,
        args.output_s3_bucket,
        args.output_s3_prefix,
    )
    get_rdds(spark, collections)
    process_rdds(collections)
    output_rdds_from_collections(collections)


if __name__ == "__main__":
    main()
