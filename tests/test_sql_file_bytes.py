"""Full Update SQL files are UTF-8 with a BOM and CRLF on every OS."""
import pathlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from drift.full_update import write_sql_file  # noqa: E402


class SqlFileByteTests(unittest.TestCase):
    def test_bom_crlf_and_arabic_round_trip(self):
        text = "USE [Olives_BO]\nGO\n-- ع\n"
        path = pathlib.Path(tempfile.mkdtemp()) / "out.sql"
        write_sql_file(path, text)
        data = path.read_bytes()
        self.assertEqual(data[:3], b"\xef\xbb\xbf")
        self.assertIn(b"\r\n", data)
        self.assertNotIn(b"\r\r\n", data)
        body = data[3:]
        self.assertNotIn(b"\n", body.replace(b"\r\n", b""))
        self.assertIn("ع", data.decode("utf-8-sig"))

    def test_already_crlf_is_not_doubled(self):
        path = pathlib.Path(tempfile.mkdtemp()) / "out.sql"
        write_sql_file(path, "A\r\nB\r\n")
        self.assertEqual(path.read_bytes(), b"\xef\xbb\xbf" + "A\r\nB\r\n".encode("utf-8"))

    def test_second_write_does_not_double_encode_or_insert_bom(self):
        text = "سطر\nم\n"
        path = pathlib.Path(tempfile.mkdtemp()) / "out.sql"
        write_sql_file(path, text)
        write_sql_file(path, text)
        data = path.read_bytes()
        expected = b"\xef\xbb\xbf" + "سطر\r\nم\r\n".encode("utf-8")
        self.assertEqual(data[:3], b"\xef\xbb\xbf")
        self.assertEqual(data, expected)
        self.assertEqual(data.count(b"\xef\xbb\xbf"), 1)
        self.assertNotIn(b"\xef\xbb\xbf", data[3:])
        self.assertNotIn(b"\n", data[3:].replace(b"\r\n", b""))
