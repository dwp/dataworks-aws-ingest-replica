import json
import unittest
from unittest import mock

from generate_dataset_from_hbase import decrypt_ciphertext
from generate_dataset_from_hbase import decrypt_message
from generate_dataset_from_hbase import encrypt_plaintext
from generate_dataset_from_hbase import filter_rows, list_to_csv_str, process_record

test_plaintext = "12b1a332-5b46-4ad7-bd98-6f8deea3ecb7"
test_ciphertext = "ZLDdPh9IXexOzCztXNtC/uFASJVFU+RhIzu7/x8DzUmenZlO"
test_iv = "vtA/hDISUq2BacN2iklB8g=="
test_encryptionkey = "9IGlYTqyhBVKZBav1uROVA=="
test_message = json.dumps(
    {
        "message": {
            "encryption": {
                "initialisationVector": "value1",
                "encryptedEncryptionKey": "value2",
                "keyEncryptionKeyId": "value3",
            },
            "dbObject": '{"key_encrypted": "value_encrypted"}',
        }
    }
)
expected_message = json.dumps(
    {"message": {"dbObject": {"key_decrypted": "value_decrypted"}}}
)


def mock_decrypt_ciphertext(ciphertext, *args, **kwargs):
    return ciphertext.replace("encrypted", "decrypted")


def mock_get_plaintext_key(*args, **kwargs):
    return "<plaintext_key>"


class TestCrypto(unittest.TestCase):
    def test_encrypt_plaintext(self):
        output_ciphertext, output_iv = encrypt_plaintext(
            test_encryptionkey, test_plaintext, test_iv
        )

        self.assertEqual(test_ciphertext, output_ciphertext)
        self.assertEqual(test_iv, output_iv)

    def test_decrypt_ciphertext(self):
        output_plaintext = decrypt_ciphertext(
            test_ciphertext, test_encryptionkey, test_iv
        )

        self.assertEqual(test_plaintext, output_plaintext)

    @mock.patch("generate_dataset_from_hbase.get_plaintext_key", mock_get_plaintext_key)
    @mock.patch("generate_dataset_from_hbase.decrypt_ciphertext", mock_decrypt_ciphertext)
    def test_decrypt_message(self):
        self.assertEqual(expected_message, decrypt_message(test_message))


class TestSparkFunctions(unittest.TestCase):
    def test_filter_rows(self):
        # returns True
        self.assertTrue(filter_rows("column=1234kj123lk4jhl"))
        self.assertTrue(filter_rows("1234kj123lk4jhlcolumn="))
        self.assertTrue(filter_rows("abccasd098column=1234kj123lk4jhl"))

        # returns False
        self.assertFalse(filter_rows("1234kjnsd8fu093e"))
        self.assertFalse(filter_rows(None))
        self.assertFalse(filter_rows(123))
        self.assertFalse(filter_rows(["123", 123]))
        self.assertFalse(filter_rows(""))
        self.assertFalse(filter_rows([""]))

    def test_list_to_csv_str(self):
        test_values = [
            ([123, "some text", '"', '"""'], '123,some text,"""",""""""""'),
            ([None, "some-text", "\n\\4", "text"], ',some-text,"\n\\4",text'),
            ([None, None], ","),
            (["", ""], ","),
            (["", "", "\n"], ',,"\n"'),
        ]

        for i in test_values:
            self.assertEqual(list_to_csv_str(i[0]), i[1])

    @mock.patch("generate_dataset_from_hbase.decrypt_message", lambda x: x)
    def test_process_record(self):
        input_record = (
            "<id> column=<column>,  timestamp=<timestamp>, value=<recordvalue>"
        )
        output = process_record(input_record)
        self.assertIsInstance(output, list)
        self.assertEqual(len(output), 3)
        self.assertEqual(output[0], "<id>")
        self.assertEqual(output[1], "<timestamp>")
        self.assertEqual(output[2], "<recordvalue>")


if __name__ == "__main__":
    unittest.main()