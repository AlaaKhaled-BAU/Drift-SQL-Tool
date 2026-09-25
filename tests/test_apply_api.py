"""Flask apply_start / apply_session decide — monkeypatched run_statement, no live SQL.

Run: cd apps/drift-tool && python3.13 -m pytest drift/test_apply_api.py -v
"""
import json
import sys
import unittest
import unittest.mock
from pathlib import Path
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _seed_run(tmp: Path, direction: str = "105_to_client") -> tuple[str, dict]:
    run_id = "apply-api-test"
    run_dir = tmp / run_id
    apply_dir = run_dir / direction / "apply"
    apply_dir.mkdir(parents=True, exist_ok=True)
    (apply_dir / "add_update_on_client.sql").write_text(
        "SELECT ok1;\nGO\nSELECT fail;\nGO\nSELECT ok2;",
        encoding="utf-8",
    )
    meta = {"directions": [direction], "client_active_id": "66"}
    (run_dir / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    idx = {"findings": []}
    (run_dir / direction / "index.json").write_text(json.dumps(idx), encoding="utf-8")
    run = {
        "run_dir": run_dir,
        "meta": meta,
        "workspaces": {direction: idx},
        "findings": {},
    }
    return run_id, run


class TestApplyApi(unittest.TestCase):
    def setUp(self):
        from app import APPLY_SESSIONS, RUNS, app as flask_app

        self.flask_app = flask_app
        self.client = flask_app.test_client()
        self._runs = RUNS
        self._sessions = APPLY_SESSIONS
        self._runs.clear()
        self._sessions.clear()
        self._tmpdir = Path(self.flask_app.config.get("TEST_TMP") or "/tmp/drift-apply-api")
        self._tmpdir.mkdir(parents=True, exist_ok=True)

    def _client_json(self):
        return {
            "client": {
                "server": "client.example",
                "database": "ClientDb",
                "user": "u",
                "password": "p",
            },
        }

    def test_apply_start_forbidden_client_to_105(self):
        run_id, run = _seed_run(self._tmpdir, "client_to_105")
        self._runs[run_id] = run
        r = self.client.post(
            f"/api/run/{run_id}/client_to_105/apply_start",
            json=self._client_json(),
        )
        self.assertEqual(r.status_code, 403)

    def test_apply_forbidden_when_client_equals_master(self):
        run_id, run = _seed_run(self._tmpdir)
        run["meta"]["master_side"] = {
            "kind": "live",
            "server": "client.example",
            "port": 1433,
            "database": "ClientDb",
            "user": "m",
        }
        self._runs[run_id] = run
        with unittest.mock.patch("app.livescan.connect", return_value=MagicMock()):
            r = self.client.post(
                f"/api/run/{run_id}/105_to_client/apply_start",
                json=self._client_json(),
            )
        self.assertEqual(r.status_code, 403)
        self.assertIn("master", r.get_json().get("error", "").lower())

    def test_apply_forbidden_localhost_alias_matches_master(self):
        run_id, run = _seed_run(self._tmpdir)
        run["meta"]["master_side"] = {
            "kind": "live",
            "server": "127.0.0.1",
            "port": 1433,
            "database": "Olives_BO",
        }
        self._runs[run_id] = run
        with unittest.mock.patch("app.livescan.connect", return_value=MagicMock()):
            r = self.client.post(
                f"/api/run/{run_id}/105_to_client/apply_start",
                json={"client": {"server": "localhost", "database": "Olives_BO", "user": "u", "password": "p"}},
            )
        self.assertEqual(r.status_code, 403)

    def test_prompt_then_bind_skip(self):
        from app import executor, livescan

        run_id, run = _seed_run(self._tmpdir)
        script_path = run["run_dir"] / "105_to_client" / "apply" / "add_update_on_client.sql"
        script_path.write_text(
            "SELECT ok1;\nGO\nSELECT fail;\nGO\nSELECT fail2;\nGO\nSELECT ok2;",
            encoding="utf-8",
        )
        self._runs[run_id] = run

        results = [
            {"status": "ok", "class": "ok", "msgno": 0, "msg": ""},
            {"status": "benign", "class": "duplicate_key", "msgno": 2627, "msg": "dup"},
            {"status": "benign", "class": "duplicate_key", "msgno": 2627, "msg": "dup again"},
            {"status": "ok", "class": "ok", "msgno": 0, "msg": ""},
        ]

        def fake_run_statement(_cur, _sql):
            return results.pop(0)

        mock_conn = MagicMock()

        with unittest.mock.patch.object(livescan, "connect", return_value=mock_conn), \
             unittest.mock.patch.object(executor, "run_statement", fake_run_statement):
            start = self.client.post(
                f"/api/run/{run_id}/105_to_client/apply_start",
                json=self._client_json(),
            )
        self.assertEqual(start.status_code, 200)
        body = start.get_json()
        self.assertIsNotNone(body["waiting"])
        self.assertEqual(body["waiting"]["msgno"], 2627)
        self.assertFalse(body["done"])
        sid = body["session_id"]

        with unittest.mock.patch.object(executor, "run_statement", fake_run_statement):
            decide = self.client.post(
                f"/api/apply_session/{sid}/decide",
                json={"action": "bind_skip", "msgno": 2627},
            )
        self.assertEqual(decide.status_code, 200)
        dbody = decide.get_json()
        self.assertTrue(dbody["done"])
        self.assertFalse(dbody.get("stopped"))
        statuses = [row["status"] for row in dbody["report"]]
        self.assertEqual(statuses, ["ok", "skipped", "skipped", "ok"])

    def test_x_batch_stops_on_first_error(self):
        from app import executor, livescan

        run_id, run = _seed_run(self._tmpdir)
        self._runs[run_id] = run

        results = [
            {"status": "ok", "class": "ok", "msgno": 0, "msg": ""},
            {"status": "fatal", "class": "fatal", "msgno": 3602, "msg": "severe"},
        ]

        def fake_run_statement(_cur, _sql):
            return results.pop(0)

        with unittest.mock.patch.object(livescan, "connect", return_value=MagicMock()), \
             unittest.mock.patch.object(executor, "run_statement", fake_run_statement):
            start = self.client.post(
                f"/api/run/{run_id}/105_to_client/apply_start",
                json=self._client_json(),
                headers={"X-Batch": "1"},
            )
        self.assertEqual(start.status_code, 200)
        body = start.get_json()
        self.assertIsNone(body["waiting"])
        self.assertTrue(body["done"])
        self.assertTrue(body["stopped"])
        self.assertEqual(body["report"][-1]["status"], "stopped")
        self.assertEqual(body["report"][-1]["decision"], "stop")


if __name__ == "__main__":
    unittest.main(verbosity=2)
