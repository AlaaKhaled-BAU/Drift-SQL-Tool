"""POST /api/compare with master_side/client_side and assemble extras script.

Run: cd apps/drift-tool && python3.13 -m pytest drift/test_compare_live_api.py -v
"""
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

REVIEW_HEADER = (
    "-- REVIEW ONLY. This tool will not execute this script. Do not apply from the UI.\n"
)


class TestCompareLiveApi(unittest.TestCase):
    def setUp(self):
        from app import RUNS, app as flask_app

        self.client = flask_app.test_client()
        self._runs = RUNS
        self._runs.clear()
        self._tmpdir = Path("/tmp/drift-compare-live-api")
        self._tmpdir.mkdir(parents=True, exist_ok=True)
        self._bak = self._tmpdir / "client.bak"
        self._bak.write_bytes(b"")

    def test_compare_accepts_live_sides_without_bak_paths(self):
        fake_result = {
            "run_id": "live-run-1",
            "run_dir": str(self._tmpdir / "live-run-1"),
            "meta": {
                "run_id": "live-run-1",
                "master_side": {"kind": "live", "server": "m", "database": "M", "password": "x"},
                "client_side": {"kind": "bak", "path": str(self._bak)},
                "directions": ["client_to_105"],
            },
            "workspaces": {"client_to_105": {"findings": [], "counts": {}}},
            "_findings": {"client_to_105": []},
        }
        with patch("app.pipeline.run_compare_sides", return_value=fake_result) as rc:
            r = self.client.post(
                "/api/compare",
                json={
                    "master_side": {
                        "kind": "live",
                        "server": "10.0.10.105",
                        "port": 1433,
                        "database": "Olives_BO",
                        "user": "sa",
                        "password": "pw",
                    },
                    "client_side": {"kind": "bak", "path": str(self._bak)},
                    "directions": ["client_to_105"],
                },
            )
        self.assertEqual(r.status_code, 200)
        self.assertIn("job_id", r.get_json())
        rc.assert_called_once()
        master_arg = rc.call_args[0][0]
        self.assertEqual(master_arg["password"], "pw")

    def test_compare_redacts_password_in_stored_meta(self):
        run_dir = self._tmpdir / "redact-run"
        run_dir.mkdir(parents=True, exist_ok=True)
        fake_result = {
            "run_id": "redact-run",
            "run_dir": str(run_dir),
            "meta": {
                "run_id": "redact-run",
                "master_side": {
                    "kind": "live",
                    "server": "m",
                    "database": "M",
                    "user": "u",
                    "password": "secret",
                },
                "client_side": {"kind": "bak", "path": str(self._bak)},
                "directions": ["client_to_105"],
            },
            "workspaces": {"client_to_105": {"findings": [], "counts": {}}},
            "_findings": {"client_to_105": []},
        }

        def worker_side_effect(*_a, **_k):
            return fake_result

        with patch("app.pipeline.run_compare_sides", side_effect=worker_side_effect):
            r = self.client.post(
                "/api/compare",
                json={
                    "master_side": fake_result["meta"]["master_side"],
                    "client_side": fake_result["meta"]["client_side"],
                },
            )
        job_id = r.get_json()["job_id"]
        import time
        from app import JOBS

        for _ in range(50):
            if JOBS[job_id]["done"]:
                break
            time.sleep(0.05)
        run = self._runs.get("redact-run")
        self.assertIsNotNone(run)
        self.assertNotIn("password", run["meta"]["master_side"])
        meta_disk = json.loads((run_dir / "meta.json").read_text(encoding="utf-8"))
        self.assertNotIn("password", meta_disk.get("master_side", {}))

    def test_assemble_client_to_105_writes_review_extras(self):
        run_id = "extras-run"
        direction = "client_to_105"
        run_dir = self._tmpdir / run_id
        apply_dir = run_dir / direction / "apply"
        apply_dir.mkdir(parents=True, exist_ok=True)
        idx = {
            "findings": [
                {
                    "id": "f1",
                    "review": "approved",
                    "name": "[dbo].[P]",
                    "bare_name": "P",
                    "type": "SqlProcedure",
                    "role": "modified",
                    "path": "01_structural/P",
                }
            ]
        }
        (run_dir / direction / "index.json").write_text(json.dumps(idx), encoding="utf-8")
        (run_dir / "meta.json").write_text(json.dumps({"directions": [direction]}), encoding="utf-8")
        full = {
            "id": "f1",
            "name": "[dbo].[P]",
            "bare_name": "P",
            "type": "SqlProcedure",
            "role": "modified",
            "client_def": "CREATE PROC dbo.P AS SELECT 1",
        }
        self._runs[run_id] = {
            "run_dir": run_dir,
            "meta": {"directions": [direction]},
            "workspaces": {direction: idx},
            "findings": {direction: [full]},
        }
        r = self.client.post(f"/api/run/{run_id}/{direction}/apply", json={})
        self.assertEqual(r.status_code, 200)
        extras = (apply_dir / "review_client_extras.sql").read_text(encoding="utf-8")
        self.assertTrue(extras.startswith(REVIEW_HEADER))
        self.assertIn("CREATE OR ALTER PROC", extras)
        still = (apply_dir / "add_update_on_105.sql").read_text(encoding="utf-8")
        self.assertNotIn(REVIEW_HEADER.strip(), still.split("\n")[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
