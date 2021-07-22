import boto3
import json
import os
import re
from botocore.client import BaseClient
from botocore.paginate import Paginator
from typing import List


class PathError(Exception):
    """Raise when object path is not in expected prefix"""


class S3Error(Exception):
    """Raise when S3 operations are not successful"""


class EMRCluster:
    """EMR object derived from describe_cluster output"""

    def __init__(self, cluster_id, emr_client=None):
        self.cluster_id = cluster_id
        self._client = self.get_emr_client() if emr_client is None else emr_client
        self._cluster_description = self._client.describe_cluster(ClusterId=cluster_id)
        self.name = self._cluster_description["Cluster"]["Name"]
        self.state = self._cluster_description["Cluster"]["Status"]["State"]
        self._configurations = {
            config["Classification"]: config
            for config in self._cluster_description["Cluster"]["Configurations"]
        }
        self._uses_hbase = None
        self._applications = None

    def uses_hbase(self):
        if self._uses_hbase is None:
            self._uses_hbase = "HBase" in self.get_applications()
        return self._uses_hbase

    def get_applications(self):
        if self._applications is None:
            self._applications = [
                application["Name"]
                for application in self._cluster_description["Cluster"]["Applications"]
            ]
        return self._applications

    def get_hbase_configuration(self):
        if self.uses_hbase():
            hbase_site_conf = self.get_classification("hbase-site")
            hbase_conf = self.get_classification("hbase")
            hbase_readreplica = hbase_conf["Properties"].get(
                "hbase.emr.readreplica.enabled", "false"
            )
            hbase_readreplica = True if hbase_readreplica.lower() == "true" else False
            hbase_root_dir = hbase_site_conf["Properties"]["hbase.rootdir"]
            hbase_match = re.match(
                r"s3://(?P<bucket>[A-Za-z0-9_.-]+)/(?P<prefix>.*)", hbase_root_dir
            )
            return {
                "hbase_rootdir": hbase_root_dir,
                "hbase_bucket": hbase_match["bucket"],
                "hbase_prefix": hbase_match["prefix"],
                "hbase_readreplica": hbase_readreplica,
            }

    def get_classification(self, classification: str):
        return self._configurations.get(classification, {"Properties": {}})

    def is_hbase_replica(self):
        hbase_config = self.get_hbase_configuration()
        return (
            True
            if hbase_config.get("hbase_readreplica", "").lower() == "true"
            else False
        )

    def __str__(self):
        return f"{self.cluster_id}\t{self.name}\t{self.state}"

    @staticmethod
    def get_emr_client():
        return boto3.client("emr")


def get_emr_client():
    return boto3.client("emr")


def get_s3_client():
    return boto3.client("s3")


def get_s3_paginator(s3_client: BaseClient = None):
    if not s3_client:
        s3_client = get_s3_client()
    return s3_client.get_paginator("list_objects_v2")


def get_cluster_ids(records: List[dict]):
    return [
        json.loads(record["Sns"]["Message"])["detail"]["clusterId"]
        for record in records
    ]


def delete_objs(s3_client: BaseClient, s3_bucket: str, object_keys: List):
    """Checks keys match replica pattern and deletes each object by key"""
    for key in object_keys:
        match = re.match(r"j-[A-Z0-9]+.*", key.split("meta_")[1])
        if not match:
            raise PathError(f"Path doesn't match replica meta pattern: {key}")
    print("All keys match pattern")
    print("Deleting Keys")
    response = s3_client.delete_objects(
        Bucket=s3_bucket, Delete={"Objects": [{"Key": key} for key in object_keys]}
    )

    if "Errors" in response:
        raise S3Error(f"Errors during object deletion:\n{response['Errors']}")
    else:
        print("Deletion response contains no errors")

    if "Deleted" in response:
        print("Files deleted:")
        [print("DELETED: " + item["Key"]) for item in response["Deleted"]]
    else:
        print("Deletion response does not contain deleted files")


def get_s3_objects_list(paginator: Paginator, s3_bucket: str, s3_prefix: str):
    s3_response = paginator.paginate(Bucket=s3_bucket, Prefix=s3_prefix)
    object_keys = []
    for page in s3_response:
        if "Contents" in page:
            object_keys += [item["Key"] for item in page["Contents"]]
    return object_keys


def handler(event, context):
    emr_client = get_emr_client()
    s3_client = get_s3_client()
    s3_paginator = get_s3_paginator(s3_client)

    cluster_ids = get_cluster_ids(event["Records"])
    clusters = [EMRCluster(cluster_id, emr_client) for cluster_id in cluster_ids]
    [print(cluster) for cluster in clusters]
    replicas_to_manage = [
        cluster
        for cluster in clusters
        if cluster.is_hbase_replica()
           and "intraday" in cluster.name
           and cluster.state in ["TERMINATED", "TERMINATED_WITH_ERRORS"]
    ]

    if len(replicas_to_manage) == 0:
        print("No replica cluster metadata to manage")
    else:
        for cluster in replicas_to_manage:
            config = cluster.get_hbase_configuration()
            cluster_prefix = os.path.join(
                config["hbase_prefix"], "data", "hbase", "meta_" + cluster.cluster_id
            )
            s3_bucket = config["hbase_bucket"]
            object_keys = get_s3_objects_list(s3_paginator, s3_bucket, cluster_prefix)
            print(f"CLUSTER ID: {cluster.cluster_id}")
            print(f"CLUSTER meta prefix: {cluster_prefix}")
            [print(f"    {key}") for key in object_keys]
            if len(object_keys) > 0:
                delete_objs(s3_client, s3_bucket, object_keys)
            else:
                print(f"No meta to delete for cluster id: {cluster.cluster_id}")
