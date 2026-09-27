"""scratch_odbc cursor wrapper (Windows / pyodbc only)."""
import unittest

try:
    import pyodbc  # noqa: F401
except ImportError:
    raise unittest.SkipTest("pyodbc not installed") from None

from drift.scratch_odbc import _Cursor


class _FakeOdbcCursor:
    description = [("id",), ("name",)]

    def __init__(self):
        self.executed = []
        self._rows = [(1, "a"), (2, "b")]
        self._idx = 0

    def execute(self, sql, params=None):
        self.executed.append((sql, params))
        return self

    def fetchone(self):
        if self._idx >= len(self._rows):
            return None
        row = self._rows[self._idx]
        self._idx += 1
        return row

    def fetchall(self):
        return self._rows[self._idx:]
        self._idx = len(self._rows)


class ScratchOdbcCursor(unittest.TestCase):
    def test_percent_s_to_question_mark(self):
        fake = _FakeOdbcCursor()
        cur = _Cursor(fake, as_dict=False)
        cur.execute("SELECT * FROM t WHERE id = %s AND n = %s", (1, 2))
        self.assertEqual(fake.executed[0][0], "SELECT * FROM t WHERE id = ? AND n = ?")
        self.assertEqual(fake.executed[0][1], (1, 2))

    def test_dict_rows(self):
        fake = _FakeOdbcCursor()
        fake._rows = [(10, "x")]
        fake._idx = 0
        cur = _Cursor(fake, as_dict=True)
        cur.execute("SELECT id, name FROM t")
        row = cur.fetchone()
        self.assertEqual(row, {"id": 10, "name": "x"})

    def test_tuple_rows(self):
        fake = _FakeOdbcCursor()
        fake._rows = [(10, "x")]
        fake._idx = 0
        cur = _Cursor(fake, as_dict=False)
        cur.execute("SELECT id, name FROM t")
        row = cur.fetchone()
        self.assertEqual(row, (10, "x"))

    def test_fetchone_none(self):
        fake = _FakeOdbcCursor()
        fake._rows = []
        fake._idx = 0
        cur = _Cursor(fake, as_dict=True)
        self.assertIsNone(cur.fetchone())


if __name__ == "__main__":
    unittest.main()
