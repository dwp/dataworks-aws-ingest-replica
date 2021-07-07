import json
import unittest
from unittest import mock
from test_tools import (
    dks_test_data,
    mock_get_key_from_dks,
    mock_get_plaintext_key,
    mock_decrypt_ciphertext,
    mock_decrypt_message,
)

from generate_dataset_from_hbase import (
    filter_rows,
    list_to_csv_str,
    process_record,
    get_plaintext_key,
    decrypt_ciphertext,
    decrypt_message,
    encrypt_plaintext,
)


class TestCrypto(unittest.TestCase):
    def test_encrypt_plaintext(self):
        output_ciphertext, output_iv = encrypt_plaintext(
            dks_test_data["test_encryptionkey"],
            dks_test_data["test_plaintext"],
            dks_test_data["test_iv"],
        )

        self.assertEqual(dks_test_data["test_ciphertext"], output_ciphertext)
        self.assertEqual(dks_test_data["test_iv"], output_iv)

    def test_decrypt_ciphertext(self):
        output_plaintext = decrypt_ciphertext(
            dks_test_data["test_ciphertext"],
            dks_test_data["test_encryptionkey"],
            dks_test_data["test_iv"],
        )

        self.assertEqual(dks_test_data["test_plaintext"], output_plaintext)

    @mock.patch("generate_dataset_from_hbase.get_plaintext_key", mock_get_plaintext_key)
    @mock.patch(
        "generate_dataset_from_hbase.decrypt_ciphertext", mock_decrypt_ciphertext
    )
    def test_decrypt_message(self):
        self.assertEqual(
            dks_test_data["expected_message"],
            decrypt_message(dks_test_data["test_message"], mock.MagicMock())[1],
        )


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

    @mock.patch("generate_dataset_from_hbase.decrypt_message", mock_decrypt_message)
    def test_process_record(self):
        acc = mock.MagicMock()
        input_record = (
            "<id> column=<column>,  timestamp=12345, value=<recordvalue>"
        )
        output = process_record(input_record, "<table_name>", acc)
        self.assertIsInstance(output, list)
        self.assertEqual(len(output), 3)
        self.assertEqual(output[0], "<id>")
        self.assertEqual(output[1], "12345")
        self.assertEqual(output[2], "<recordvalue>")


class TestDksCache(unittest.TestCase):
    @mock.patch(
        "generate_dataset_from_hbase.get_key_from_dks",
        side_effect=mock_get_key_from_dks,
    )
    def test_dks_cache(self, post_mock):
        ceks = ["key1_ciphertext", "key2_ciphertext", "key3_ciphertext"]
        for _ in range(5):
            for cek in ceks:
                cek_plaintext = get_plaintext_key(url=None, kek=None, cek=cek, dks_count_acc=mock.MagicMock())
                self.assertNotEqual(cek_plaintext, cek)

        # assert one call to 'dks' per key
        self.assertEqual(post_mock.call_count, len(ceks))



if __name__ == "__main__":
    unittest.main()
