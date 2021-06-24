import json
from dataclasses import dataclass, field
from time import time

dks_test_data = {
    "test_plaintext": "12b1a332-5b46-4ad7-bd98-6f8deea3ecb7",
    "test_ciphertext": "ZLDdPh9IXexOzCztXNtC/uFASJVFU+RhIzu7/x8DzUmenZlO",
    "test_iv": "vtA/hDISUq2BacN2iklB8g==",
    "test_encryptionkey": "9IGlYTqyhBVKZBav1uROVA==",
    "test_message": json.dumps(
        {
            "message": {
                "_id": """{"id_type}: "abcde-fghij-klmno-pqrst\"""",
                "encryption": {
                    "initialisationVector": "value1",
                    "encryptedEncryptionKey": "value2",
                    "keyEncryptionKeyId": "value3",
                },
                "dbObject": '{"key_encrypted": "value_encrypted"}',
            }
        },
        sort_keys=True,
    ),
    "expected_message": json.dumps(
        {
            "message": {
                "_id": """{"id_type}: "abcde-fghij-klmno-pqrst\"""",
                "dbObject": {"key_decrypted": "value_decrypted"},
            },
        },
        sort_keys=True,
    ),
}


@dataclass
class GetCollectionArgs:
    collections: list = field(default_factory=list)
    output_s3_bucket: str = "example-bucket"
    output_s3_prefix: str = "folder1/folder2"
    end_time: int = round(time() / 1000)


def mock_get_key_from_dks(url, kek, cek, **kwargs):
    return cek.replace("ciphertext", "plaintext")


def mock_decrypt_ciphertext(ciphertext, *args, **kwargs):
    return ciphertext.replace("encrypted", "decrypted")


def mock_get_plaintext_key(*args, **kwargs):
    return "<plaintext_key>"


def mock_get_aws_collections(*args, **kwargs):
    return [
        {
            "hbase_table": "db1:collection1",
            "hive_table": "db1_collection1",
            "tags": {"db": "db1", "table": "collection1", "pii": "true"},
        },
        {
            "hbase_table": "db2:collection2",
            "hive_table": "db2_collection2",
            "tags": {"db": "db2", "table": "collection2", "pii": "true"},
        },
    ]


def mock_retrieve_secrets(*args, **kwargs):
    return {
        "collections_all": {
            "db.db1.collection1": {"db": "db1", "table": "collection1", "pii": "true"},
            "db.db2.collection2": {"db": "db2", "table": "collection2", "pii": "true"},
        },
    }
