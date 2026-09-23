"""POST /api/live/databases — fake cursor, no live SQL.

Run: cd apps/drift-tool && python3.13 -m pytest drift/test_live_picker.py -v
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestLiveDatabases(unittest.TestCase):
    def setUp(self):
        from app import app as flask_app

        self.client = flask_app.test_client()

    def test_databases_requires_server(self):
        r = self.client.post("/api/live/databases", json={})
        self.assertEqual(r.status_code, 400)

    def test_databases_lists_user_dbs(self):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_cur.fetchall.return_value = [("Olives_BO",), ("OtherDb",)]
        mock_conn.cursor.return_value = mock_cur
        mock_conn.close = MagicMock()

        with patch("app._sql_connect_for_list", return_value=mock_conn):
            r = self.client.post(
                "/api/live/databases",
                json={
                    "server": "10.0.0.5",
                    "port": 1433,
                    "user": "sa",
                    "password": "secret",
                },
            )
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertTrue(body["ok"])
        self.assertEqual(body["databases"], ["Olives_BO", "OtherDb"])
        mock_cur.execute.assert_called_once()
        sql = mock_cur.execute.call_args[0][0]
        self.assertIn("sys.databases", sql)
        self.assertIn("database_id > 4", sql)
        mock_conn.close.assert_called_once()


if __name__ == "__main__":
    unittest.main(verbosity=2)
