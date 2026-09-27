"""HTTP API for scratch server settings."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from drift import config

import app as app_module
from app import JOBS, app

_ENV_KEYS = (
    "DRIFT_SCRATCH_SERVER", "DRIFT_SCRATCH_PORT", "DRIFT_SCRATCH_USER",
    "DRIFT_SCRATCH_PASSWORD", "DRIFT_SCRATCH_AUTH",
)


def _clear_scratch_env():
    return patch.dict("os.environ", {k: "" for k in _ENV_KEYS}, clear=False)


def _temp_settings():
    path = Path(tempfile.mkdtemp()) / "scratch_server.json"
    return patch.object(config, "SCRATCH_SETTINGS_FILE", path), path


class ScratchApi(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_get_never_returns_password(self):
        p, path = _temp_settings()
        with p, _clear_scratch_env():
            config.save_scratch_settings({
                "mode": "local", "server": "h", "port": 1433,
                "auth": "sql", "user": "u", "password": "topsecret",
            })
            r = self.client.get("/api/scratch/settings")
            body = r.get_json()
        self.assertNotIn("password", body)
        self.assertTrue(body["has_password"])

    def test_save_blocked_when_env_locked(self):
        with patch.dict("os.environ", {"DRIFT_SCRATCH_SERVER": "x"}, clear=False):
            r = self.client.post("/api/scratch/settings", json={"mode": "docker"})
        self.assertEqual(r.status_code, 409)

    def test_save_blocked_while_compare_running(self):
        p, _path = _temp_settings()
        JOBS["x"] = {"kind": "compare", "done": False}
        try:
            with p, _clear_scratch_env():
                r = self.client.post("/api/scratch/settings", json={"mode": "docker"})
            self.assertEqual(r.status_code, 409)
        finally:
            JOBS.pop("x", None)

    def test_save_bad_input_400(self):
        p, _path = _temp_settings()
        with p, _clear_scratch_env():
            r = self.client.post("/api/scratch/settings", json={"mode": "local"})
        self.assertEqual(r.status_code, 400)
        self.assertIn("server", r.get_json()["error"])

    def test_test_endpoint_reports_connect_error(self):
        p, _path = _temp_settings()
        with p, _clear_scratch_env(), patch.object(app_module, "_scratch_test_connect") as conn_fn:
            conn_fn.side_effect = RuntimeError("login failed for user")
            r = self.client.post("/api/scratch/test", json={
                "mode": "local", "server": "badhost", "port": 1433,
                "auth": "sql", "user": "u", "password": "p",
            })
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertFalse(body["ok"])
        self.assertIn("error", body)
        self.assertNotIn("password", json.dumps(body))


if __name__ == "__main__":
    unittest.main()
