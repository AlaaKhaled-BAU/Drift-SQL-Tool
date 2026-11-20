import json
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

MASTER = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
  SELECT 'b'
 END
END"""

CLIENT = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
  SELECT 'extra'
 END
END"""


class ClientChangesApiTests(unittest.TestCase):
    def setUp(self):
        from app import RUNS, app as flask_app
        import drift.config as config

        self.client = flask_app.test_client()
        self._runs = RUNS
        self._runs.clear()
        self.run_id = "client-changes-api"
        self.run_dir = config.OUTPUT_DIR / self.run_id
        if self.run_dir.exists():
            shutil.rmtree(self.run_dir)
        proc_dir = self.run_dir / "client_to_105" / "02_modified"
        proc_dir.mkdir(parents=True)
        (self.run_dir / "meta.json").write_text(json.dumps({
            "directions": ["client_to_105"],
            "client_active_id": None,
        }), encoding="utf-8")
        findings = [
            {"id": "proc1", "type": "SqlProcedure", "role": "modified", "category": "structural",
             "name": "dbo.zz_keep", "bare_name": "zz_keep", "path": "02_modified/zz_keep"},
            {"id": "only105", "type": "SqlTable", "role": "only_on_other", "category": "structural",
             "name": "dbo.OnMaster", "bare_name": "OnMaster", "path": "03_only_on_other/OnMaster"},
            {"id": "integ", "type": "SqlProcedure", "role": "added", "category": "structural",
             "name": "dbo.ABS_Integ_GetDataFromAPI", "bare_name": "ABS_Integ_GetDataFromAPI",
             "path": "01_added/ABS_Integ_GetDataFromAPI"},
        ]
        (self.run_dir / "client_to_105" / "index.json").write_text(
            json.dumps({"findings": findings}), encoding="utf-8")
        base = proc_dir / "zz_keep"
        Path(str(base) + ".master.sql").write_text(MASTER, encoding="utf-8")
        Path(str(base) + ".client.sql").write_text(CLIENT, encoding="utf-8")

    def tearDown(self):
        self._runs.clear()
        if self.run_dir.exists():
            shutil.rmtree(self.run_dir)

    def test_list_keeps_trimmed_procedure_and_drops_only_on_105_and_integ(self):
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes",
            json={"client_active_id": 66},
        )
        self.assertEqual(res.status_code, 200)
        rows = {row["id"]: row for row in res.get_json()["rows"]}
        self.assertTrue(rows["proc1"]["list"])
        self.assertEqual(rows["proc1"]["inspect"], "procedure")
        self.assertNotIn("master_def", rows["proc1"])
        self.assertFalse(rows["only105"]["list"])
        self.assertFalse(rows["integ"]["list"])
        self.assertEqual(rows["integ"]["kind"], "name_excluded")

    def test_inspect_returns_a_hide_and_an_extra(self):
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes/inspect",
            json={"client_active_id": 66, "finding_ids": ["proc1"]},
        )
        self.assertEqual(res.status_code, 200)
        diff = res.get_json()["diffs"]["proc1"]
        self.assertTrue(diff["ok"])
        tags = [
            row.get("tag")
            for hunk in diff["hunks"] if not hunk.get("collapsed")
            for row in hunk["lines"]
        ]
        self.assertIn("delete", tags)
        self.assertIn("insert", tags)
        self.assertNotIn("copy_sql", diff)

    def test_missing_client_active_does_not_list_the_procedure(self):
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes",
            json={"client_active_id": None},
        )
        self.assertEqual(res.status_code, 200)
        body = res.get_json()
        self.assertTrue(body["needs_client_active"])
        proc = next(row for row in body["rows"] if row["id"] == "proc1")
        self.assertFalse(proc["list"])
        self.assertEqual(proc["kind"], "needs_client_active")
