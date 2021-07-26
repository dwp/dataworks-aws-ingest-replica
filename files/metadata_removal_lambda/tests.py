import unittest
import uuid
from unittest import mock

import boto3
from botocore.stub import Stubber

from index import (
    get_cluster_ids,
    get_s3_objects_list,
    delete_objs,
    S3Error,
)
from test_tools import (
    lambda_sns_message,
    s3_paginator_response,
    keys_to_delete,
)


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

    def test_delete_objects_success(self):
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

    def test_delete_objects_fail(self):
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


class TestOther(unittest.TestCase):
    def test_get_cluster_ids(self):
        ids = get_cluster_ids(lambda_sns_message)
        self.assertEqual(set(ids), {"j-AAA111AAA111A"})


if __name__ == "__main__":
    unittest.main()
