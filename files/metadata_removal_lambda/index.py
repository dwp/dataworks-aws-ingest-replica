import json
import logging
import os
from typing import List

import boto3
from botocore.client import BaseClient
from botocore.paginate import Paginator

_logger = logging.getLogger()
_logger.setLevel(logging.INFO)


class S3Error(Exception):
    """Raise when S3 operations are not successful"""


def get_env():
    if not all([item in os.environ for item in ["hbase_prefix", "hbase_bucket"]]):
        raise EnvironmentError("hbase_prefix or hbase_bucket not found in environ")
    return os.environ.get("hbase_prefix"), os.environ.get("hbase_bucket")


def get_emr_client() -> BaseClient:
    return boto3.client("emr")


def get_s3_client() -> BaseClient:
    return boto3.client("s3")


def get_s3_paginator(s3_client: BaseClient = None) -> Paginator:
    if not s3_client:
        s3_client = get_s3_client()
    return s3_client.get_paginator("list_objects_v2")


def get_cluster_ids(event: dict) -> List:
    return [
        json.loads(record["Sns"]["Message"])["detail"]["clusterId"]
        for record in event["Records"]
    ]


def delete_objs(s3_client: BaseClient, s3_bucket: str, object_keys: List) -> None:
    """Checks keys match replica pattern and deletes each object by key"""
    response = s3_client.delete_objects(
        Bucket=s3_bucket, Delete={"Objects": [{"Key": key} for key in object_keys]}
    )

    if "Errors" in response:
        raise S3Error(f"Errors during object deletion:\n{response['Errors']}")
    else:
        _logger.debug("Deletion response contains no errors")

    if "Deleted" in response:
        [_logger.info("DELETED: " + item["Key"]) for item in response["Deleted"]]
    else:
        _logger.warning("Deletion response does not contain deleted files")


def get_s3_objects_list(
    paginator: Paginator, s3_bucket: str, s3_prefix: str
) -> List[str]:
    s3_response = paginator.paginate(Bucket=s3_bucket, Prefix=s3_prefix)
    object_keys = []
    for page in s3_response:
        if "Contents" in page:
            object_keys += [item["Key"] for item in page["Contents"]]
    return object_keys


def handler(event, _):
    hbase_prefix, hbase_bucket = get_env()

    s3_client = get_s3_client()
    s3_paginator = get_s3_paginator(s3_client)

    cluster_ids = get_cluster_ids(event)
    meta_prefixes = {id_: hbase_prefix + id_ for id_ in cluster_ids}

    meta_keys = {
        id_: [
            key for key in get_s3_objects_list(s3_paginator, hbase_bucket, meta_prefix)
        ]
        for id_, meta_prefix in meta_prefixes.items()
    }

    for id_, keys in meta_keys.items():
        if keys:
            _logger.info(f"Deleting keys for cluster {id_}:")
            delete_objs(s3_client, hbase_bucket, keys)
        else:
            _logger.warning(f"No metadata keys for cluster {id_}")
