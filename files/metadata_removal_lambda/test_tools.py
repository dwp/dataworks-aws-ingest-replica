import datetime
import json

s3_paginator_response = {
    "IsTruncated": False,
    "Contents": [
        {
            "Key": "key1",
            "LastModified": datetime.datetime(1900, 1, 1, 0, 0, 0, 0),
            "ETag": "key1tag",
            "Size": 0,
            "StorageClass": "STANDARD",
        },
        {
            "Key": "key2",
            "LastModified": datetime.datetime(1900, 1, 1, 0, 0, 0, 0),
            "ETag": "key2tag",
            "Size": 0,
            "StorageClass": "STANDARD",
        },
    ],
    "Name": "bucket",
    "Prefix": "prefix",
    "MaxKeys": 1000,
    "EncodingType": "url",
    "KeyCount": 1,
}

lambda_sns_message = json.loads(
    '{"Records": [{"EventSource": "aws:sns", "EventVersion": "1.0", "EventSubscriptionArn": "arn:aws:sns:region:<accountnumber>:emr-state-change", "Sns": {"Type": "Notification", "MessageId": "", "TopicArn": "arn:aws:sns:region:<accountnumber>:emr-state-change", "Subject": null, "Message": "{\\"version\\": \\"0\\", \\"id\\": \\"randomstring\\", \\"detail-type\\": \\"EMR Cluster State Change\\", \\"source\\": \\"aws.emr\\", \\"account\\": \\"<accountnumber>\\", \\"time\\": \\"1900-01-01T00:00:01Z\\", \\"region\\": \\"region\\", \\"resources\\": [], \\"detail\\": {\\"severity\\": \\"INFO\\", \\"stateChangeReason\\": \\"{\\\\\\"code\\\\\\":\\\\\\"USER_REQUEST\\\\\\",\\\\\\"message\\\\\\":\\\\\\"Terminatedbyuserrequest\\\\\\"}\\", \\"name\\": \\"cluster-name\\", \\"clusterId\\": \\"j-AAA111AAA111A\\", \\"state\\": \\"TERMINATED\\", \\"message\\": \\"Amazon EMR Cluster j-AAA111AAA111A (cluster-name) has terminated at 1900-01-01 00:00 UTC with a reason of USER_REQUEST.\\"}}", "Timestamp": "1900-01-01T00:00:00.000Z", "SignatureVersion": "1", "Signature": "", "SigningCertUrl": "", "UnsubscribeUrl": "", "MessageAttributes": {}}}]}'
)

keys_to_delete = [
    "prefix1/file1",
    "prefix1/file2",
    "prefix2/file3",
    "prefix2/file4",
]
