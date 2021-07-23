import unittest
import uuid
from unittest import mock

import boto3
from botocore.stub import Stubber

from index import (
    EMRCluster,
    get_cluster_ids,
    check_path,
    get_s3_objects_list,
    delete_objs,
    S3Error,
    PathError,
)
from test_tools import *


class TestPaths(unittest.TestCase):
    def test_re_match(self):
        compliant = [
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta_j-AAA111AAA1/",
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta_j-AAA111AAA1_$folder$",
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta_j-AAA111AAA1/.tabledesc/.tableinfo.001",
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta_j-AAA111AAA1/folder1/folder2",
        ]

        not_compliant = [
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta/",
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta_$folder$",
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta/.tabledesc/.tableinfo.001",
            f"{uuid.uuid4()}/folder1/folder2/data/hbase/meta/file",
            f"{uuid.uuid4()}/folder1/folder2/",
            f"{uuid.uuid4()}/file",
            f"{uuid.uuid4()}",
        ]

        self.assertTrue(all([check_path(path) for path in compliant]))
        self.assertFalse(any([check_path(path) for path in not_compliant]))


class TestEMRCluster(unittest.TestCase):
    def setUp(self):
        self.client = boto3.client("emr")

    def test_init_1(self):
        """HBase with replica enabled"""
        with Stubber(self.client) as stubber:
            stubber.add_response("describe_cluster", cluster_response_1)
            cluster = EMRCluster("j-AAA111AAA111A", emr_client=self.client)
            self.assertEqual(cluster.name, "test-cluster1")
            self.assertEqual(cluster.cluster_id, "j-AAA111AAA111A")
            self.assertEqual(cluster.state, "STARTING")
            self.assertTrue(cluster.uses_hbase())
            self.assertTrue(cluster.is_hbase_replica())

    def test_init_2(self):
        """EMR without HBase"""
        with Stubber(self.client) as stubber:
            stubber.add_response("describe_cluster", cluster_response_2)
            cluster = EMRCluster("j-BBB111BBB111B", emr_client=self.client)
            self.assertEqual(cluster.name, "test-cluster2")
            self.assertEqual(cluster.cluster_id, "j-BBB111BBB111B")
            self.assertEqual(cluster.state, "TERMINATED")
            self.assertFalse(cluster.uses_hbase())
            self.assertFalse(cluster.is_hbase_replica())

    def test_init_3(self):
        """HBase with replica disabled"""
        with Stubber(self.client) as stubber:
            stubber.add_response("describe_cluster", cluster_response_3)
            cluster = EMRCluster("j-CCC111CCC111C", emr_client=self.client)
            self.assertEqual(cluster.name, "test-cluster3")
            self.assertEqual(cluster.cluster_id, "j-CCC111CCC111C")
            self.assertEqual(cluster.state, "TERMINATED_WITH_ERRORS")
            self.assertTrue(cluster.uses_hbase())
            self.assertFalse(cluster.is_hbase_replica())


class TestS3(unittest.TestCase):
    def setUp(self) -> None:
        self.client = boto3.client("s3")

    def test_get_s3_objects_list(self):
        paginator = self.client.get_paginator("list_objects_v2")
        with Stubber(self.client) as stubber:
            stubber.add_response("list_objects_v2", s3_paginator_response)
            keys = get_s3_objects_list(
                paginator=paginator, s3_bucket="bucket", s3_prefix="prefix"
            )
            self.assertEqual(set(keys), {"key1", "key2"})

    @mock.patch("index.check_path", lambda x: True)
    def test_delete_objects_success(self):
        keys_to_delete = [
            "prefix1/file1",
            "prefix1/file2",
            "prefix2/file3",
            "prefix2/file4",
        ]

        stub_response = {
            "Deleted": [
                {
                    "Key": key,
                    "VersionId": str(uuid.uuid4()),
                    "DeleteMarker": True,
                    "DeleteMarkerVersionId": str(uuid.uuid4()),
                }
                for key in keys_to_delete
            ]
        }

        with Stubber(self.client) as stubber:
            stubber.add_response("delete_objects", stub_response)
            delete_objs(self.client, "bucket", keys_to_delete)

    @mock.patch("index.check_path", lambda x: True)
    def test_delete_objects_fail(self):
        keys_to_delete = [
            "prefix1/file1",
            "prefix1/file2",
            "prefix2/file3",
            "prefix2/file4",
        ]

        stub_response = {
            "Errors": [
                {
                    "Key": key,
                    "VersionId": str(uuid.uuid4()),
                    "Code": "<code>",
                    "Message": str(uuid.uuid4()),
                }
                for key in keys_to_delete
            ]
        }
        with Stubber(self.client) as stubber:
            stubber.add_response("delete_objects", stub_response)
            self.assertRaises(
                S3Error, delete_objs, self.client, "bucket", keys_to_delete
            )

    @mock.patch("index.check_path", lambda x: False)
    def test_delete_objects_exception(self):
        keys_to_delete = [
            "prefix1/file1",
            "prefix1/file2",
            "prefix2/file3",
            "prefix2/file4",
        ]
        with Stubber(self.client) as stubber:
            self.assertRaises(
                PathError, delete_objs, self.client, "bucket", keys_to_delete
            )


class TestOther(unittest.TestCase):
    def test_get_cluster_ids(self):
        ids = get_cluster_ids(lambda_sns_message)
        self.assertEqual(set(ids), {"j-AAA111AAA111A"})


if __name__ == "__main__":
    unittest.main()
