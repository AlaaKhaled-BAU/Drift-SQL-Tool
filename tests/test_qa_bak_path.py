"""Regression: ISSUE-001 — bak Full Update crashed before restore.

Found by /qa on 2026-10-28.
Report: .gstack/qa-reports/qa-report-127-0-0-1-2026-10-28.md

restore.restore_backup calls Path.resolve(). The Full Update route handed it
the JSON string, so a real .bak died with 'str' object has no attribute 'resolve'.
"""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as app_module  # noqa: E402


class BakPathRegressionTests(unittest.TestCase):
    def test_load_bak_catalog_resolves_a_string_path(self):
        seen = {}

        def fake_restore(path, db_name, log):
            # Same call the real function makes on its first line of local mode.
            seen["resolved"] = path.resolve()
            seen["name"] = path.name
            self.assertTrue(str(db_name).startswith("drift_left_"))
            return {
                "backup_date": "2026-01-01",
                "engine_major_version": 16,
                "database_name": "Olives_BO",
            }

        def fake_capture(connector, database_name):
            return {"objects": {}, "dependencies": []}

        with mock.patch.object(app_module.restore, "restore_backup", fake_restore), \
             mock.patch.object(app_module.full_update, "capture_live_catalog", fake_capture), \
             mock.patch.object(app_module, "drop_database", lambda name, log: None), \
             mock.patch.object(app_module, "_sql_connect", lambda side: object()):
            logical, _catalog = app_module.load_bak_catalog(
                "/tmp/olives_bo.bak", "drift_left_qa001",
                {"server": "127.0.0.1", "port": 1433, "database": "master",
                 "user": "sa", "password": "x"},
                lambda msg: None,
            )
        self.assertEqual(logical, "Olives_BO")
        self.assertEqual(seen["name"], "olives_bo.bak")
        self.assertTrue(str(seen["resolved"]).endswith("olives_bo.bak"))


if __name__ == "__main__":
    unittest.main()
