"""Full Update HTTP API and the SQL Compare button contract. No live SQL."""
import pathlib
import sys
import time
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import app as flask_module


def _wait_job(job_id, ticks=50):
    job = None
    for _ in range(ticks):
        job = flask_module.JOBS[job_id]
        if job.get("done"):
            break
        time.sleep(0.05)
    return job


class FullUpdateApiTests(unittest.TestCase):
    def setUp(self):
        flask_module.app.config["TESTING"] = True
        self.client = flask_module.app.test_client()

    def test_defaults_match_the_python_list(self):
        from drift.proc_filter import default_rules
        body = self.client.get("/api/procedure_filter/defaults").get_json()
        rules = default_rules()
        self.assertEqual(body["rules"], rules)
        self.assertEqual(len(body["rules"]), 21)
        self.assertEqual(body["rules"][0]["value"], "alpha")
        self.assertEqual(
            {(row["op"], row["value"]) for row in body["rules"]},
            {(row["op"], row["value"]) for row in rules},
        )
        self.assertEqual(len(body["rules"]), len(rules))

    def test_stream_full_update_emits_files_without_workspaces(self):
        import queue
        from app import JOBS
        q = queue.Queue()
        q.put(None)
        JOBS["fu1"] = {
            "queue": q, "error": None, "kind": "full_update",
            "result": {"run_id": "r1", "meta": {}, "files": ["Olives_BO_schema.sql"]},
        }
        try:
            body = self.client.get("/api/stream/fu1").get_data(as_text=True)
        finally:
            JOBS.pop("fu1", None)
        self.assertIn("event: result", body)
        self.assertIn("Olives_BO_schema.sql", body)
        self.assertNotIn("workspaces", body)
        self.assertNotIn("event: error", body)

    def test_bak_script_targets_the_header_name(self):
        import app as app_module
        captured = {}
        dropped = []

        def fake_restore(path, db_name, log):
            self.assertTrue(str(db_name).startswith("drift_left_"))
            captured["physical"] = db_name
            return {
                "backup_date": "2026-01-01",
                "engine_major_version": 16,
                "database_name": "Olives_BO",
            }

        def fake_capture(connector, database_name):
            captured["read_database"] = database_name
            connector(database_name)
            return {"objects": {}, "dependencies": []}

        def fake_drop(name, log):
            dropped.append(name)

        with mock.patch.object(app_module.restore, "restore_backup", fake_restore), \
             mock.patch.object(app_module.full_update, "capture_live_catalog", fake_capture), \
             mock.patch.object(app_module, "drop_database", fake_drop), \
             mock.patch.object(app_module, "_sql_connect", lambda side: object()):
            logical, catalog = app_module.load_bak_catalog(
                "/tmp/olives_bo.bak", "drift_left_abc",
                {"server": "127.0.0.1", "port": 1433, "database": "master", "user": "sa", "password": "x"},
                lambda msg: None,
            )
        self.assertEqual(logical, "Olives_BO")
        self.assertEqual(captured["physical"], "drift_left_abc")
        self.assertEqual(captured["read_database"], "drift_left_abc")
        self.assertEqual(dropped, ["drift_left_abc"])
        tiny = {
            "objects": {
                "dbo.KeepMe": {
                    "schema": "dbo", "name": "KeepMe", "type": "SqlProcedure",
                    "definition": "CREATE PROCEDURE [dbo].[KeepMe] AS SELECT 1",
                    "ansi_nulls": True, "quoted_identifier": True, "schema_bound": False,
                }
            },
            "dependencies": [],
        }
        # A database only on the left stays in the manifest. Both sides must
        # carry the header name for the script to target it.
        files = app_module.full_update.render_full_update(
            {"databases": {logical: tiny}},
            {"databases": {logical: {"objects": {}, "dependencies": []}}},
        )
        joined = "\n".join(files["files"].values())
        self.assertIn("USE [Olives_BO]", joined)
        self.assertNotIn("drift_left_", joined)

    def test_connect_database_uses_a_copy(self):
        import app as app_module
        seen = []
        base = {"server": "127.0.0.1", "port": 1433, "database": "Olives_BO", "user": "sa", "password": "secret"}

        def fake_connect(side):
            seen.append(dict(side))
            return object()

        with mock.patch.object(app_module, "_sql_connect", fake_connect):
            app_module.connect_database(base, "Zed")
            app_module.connect_database(base, "Aaa")
        self.assertEqual([s["database"] for s in seen], ["Zed", "Aaa"])
        self.assertEqual(base["database"], "Olives_BO")

    def test_missing_catalog_path_is_400(self):
        res = self.client.post("/api/full_update", json={
            "left": {"kind": "catalog", "path": "/no/such/left_105_catalog.json"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "databases": ["Aaa"],
        })
        self.assertEqual(res.status_code, 400)
        self.assertIn("path", res.get_json()["error"].lower())

    def test_catalog_pair_writes_keepme_without_a_password(self):
        from drift.proc_filter import procedure_excluded
        self.assertFalse(procedure_excluded("KeepMe"))
        res = self.client.post("/api/full_update", json={
            "left": {"kind": "catalog", "path": "tests/fixtures/left_105_catalog.json"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "databases": ["Aaa", "Zed"],
        })
        self.assertEqual(res.status_code, 200)
        job_id = res.get_json()["job_id"]
        job = _wait_job(job_id)
        self.assertTrue(job.get("done"))
        self.assertIsNone(job.get("error"))
        run_dir = pathlib.Path(job["result"]["run_dir"])
        schema_path = run_dir / "full_update" / "Aaa_schema.sql"
        schema = schema_path.read_text(encoding="utf-8-sig")
        self.assertIn("KeepMe", schema)
        raw = schema_path.read_bytes()
        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        self.assertIn(b"\r\n", raw)
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))
        meta = (run_dir / "meta.json").read_text(encoding="utf-8")
        self.assertNotIn("password", meta.lower())
        download = self.client.get(f"/api/full_update/{job['result']['run_id']}/Aaa_schema.sql")
        self.assertEqual(download.status_code, 200)
        self.assertTrue(download.data.startswith(b"\xef\xbb\xbf"))

    def test_write_path_uses_write_sql_file(self):
        import app as app_module
        calls = []
        real = app_module.full_update.write_sql_file

        def wrapped(path, text):
            calls.append(pathlib.Path(path))
            return real(path, text)

        with mock.patch.object(app_module.full_update, "write_sql_file", wrapped):
            res = self.client.post("/api/full_update", json={
                "left": {"kind": "catalog", "path": "tests/fixtures/left_105_catalog.json"},
                "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
                "database": "Aaa",
            })
            self.assertEqual(res.status_code, 200)
            job = _wait_job(res.get_json()["job_id"])
        self.assertIsNone(job.get("error"))
        self.assertTrue(calls)
        self.assertTrue(all(path.suffix == ".sql" for path in calls))
        sample = next(path for path in calls if path.name == "Aaa_schema.sql")
        blob = sample.read_bytes()
        self.assertTrue(blob.startswith(b"\xef\xbb\xbf"))
        self.assertIn(b"\r\n", blob)

    def test_contains_excludes_and_starts_with_skips_mid_name(self):
        base = {
            "left": {"kind": "catalog", "path": "tests/fixtures/left_105_catalog.json"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "database": "Aaa",
        }
        excluded = self.client.post("/api/full_update", json={
            **base,
            "rules": [{"op": "contains", "value": "keep"}],
        })
        self.assertEqual(excluded.status_code, 200)
        excluded_job = _wait_job(excluded.get_json()["job_id"])
        self.assertIsNone(excluded_job.get("error"))
        excluded_schema = (
            pathlib.Path(excluded_job["result"]["run_dir"]) / "full_update" / "Aaa_schema.sql"
        ).read_text(encoding="utf-8-sig")
        self.assertNotIn("KeepMe", excluded_schema)
        self.assertIn("NeedsZed", excluded_schema)

        prefix = self.client.post("/api/full_update", json={
            **base,
            "rules": [{"op": "starts_with", "value": "eep"}],
        })
        self.assertEqual(prefix.status_code, 200)
        prefix_job = _wait_job(prefix.get_json()["job_id"])
        self.assertIsNone(prefix_job.get("error"))
        prefix_schema = (
            pathlib.Path(prefix_job["result"]["run_dir"]) / "full_update" / "Aaa_schema.sql"
        ).read_text(encoding="utf-8-sig")
        self.assertIn("KeepMe", prefix_schema)

    def test_all_databases_defaults_off(self):
        html = pathlib.Path("templates/index.html").read_text()
        self.assertIn('id="fullUpdateAllDbs"', html)
        self.assertIn("All databases on both sides", html)
        start = html.index('id="fullUpdateAllDbs"')
        tag = html[html.rfind("<", 0, start):html.index(">", start) + 1]
        self.assertNotIn("checked", tag)

        res = self.client.post("/api/full_update", json={
            "left": {"kind": "catalog", "path": "tests/fixtures/left_105_catalog.json"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "database": "Zed",
        })
        self.assertEqual(res.status_code, 200)
        job = _wait_job(res.get_json()["job_id"])
        self.assertIsNone(job.get("error"))
        names = list(job["result"]["files"])
        self.assertIn("Zed_schema.sql", names)
        self.assertNotIn("Aaa_schema.sql", names)
        self.assertFalse(job["result"]["meta"].get("all_databases"))

    def test_blocked_server_is_400(self):
        res = self.client.post("/api/full_update", json={
            "left": {"kind": "live", "server": "10.0.10.105", "database": "Olives_BO", "user": "sa", "password": "x"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "database": "Olives_BO",
        })
        self.assertEqual(res.status_code, 400)
        self.assertIn("10.0.10.105", res.get_json()["error"])

    def test_download_rejects_parent_segment(self):
        res = self.client.get("/api/full_update/rid/foo..sql")
        self.assertEqual(res.status_code, 400)

    def test_filter_ui_has_no_second_copy_of_the_tokens(self):
        js = pathlib.Path("static/app.js").read_text()
        html = pathlib.Path("templates/index.html").read_text()
        self.assertIn("/api/procedure_filter/defaults", js)
        self.assertNotIn("hammoudeh", js)
        self.assertNotIn("hammoudeh", html)
        self.assertNotIn("thuraya", js)

    def test_full_update_button_markup(self):
        html = pathlib.Path("templates/index.html").read_text()
        self.assertIn('id="go"', html)
        self.assertIn(">Compare<", html)
        self.assertRegex(html, r'id="fullUpdateBtn"[^>]*>Full Update<')
        self.assertNotRegex(html, r'id="fullUpdateBtn"[^>]*\bdisabled\b')
        self.assertIn('id="procFilterBtn"', html)
        self.assertIn(">Procedures filter<", html)
        self.assertIn('id="procFilterDialog"', html)
        self.assertIn('id="procFilterContainsBtn"', html)
        self.assertIn(">Contains<", html)
        self.assertIn('id="procFilterStartsBtn"', html)
        self.assertIn(">Starts with<", html)

    def test_full_update_button_stays_disabled_until_the_stream_ends(self):
        js = pathlib.Path("static/app.js").read_text()
        start = js.index("fullUpdateBtn.addEventListener")
        handler = js[start:js.index("/* end fullUpdateBtn */")]
        self.assertLess(handler.index("setBusy("), handler.index("fetch("))
        between = handler[handler.index("fetch("):handler.index("new EventSource")]
        self.assertNotIn("clearBusy(", between)
        self.assertNotIn("disabled = false", between)
        self.assertIn('addEventListener("result"', handler)
        self.assertIn('addEventListener("error"', handler)
        self.assertIn("clearBusy(fullUpdateBtn)", handler[handler.index('addEventListener("result"'):])


if __name__ == "__main__":
    unittest.main()
