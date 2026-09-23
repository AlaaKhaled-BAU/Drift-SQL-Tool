"""Flask safety tests for SQL Compare sub-tabs (no live SQL).

Run: cd apps/drift-tool && python3.13 -m pytest drift/test_compare_subtabs.py -q
"""
import json
import sys
import unittest
import zipfile
from io import BytesIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestCompareSubtabs(unittest.TestCase):
    def setUp(self):
        from app import RUNS, app as flask_app

        self.app = flask_app
        self.client = flask_app.test_client()
        self._runs = RUNS
        self._runs.clear()
        self._tmpdir = Path("/tmp/drift-compare-subtabs")
        self._tmpdir.mkdir(parents=True, exist_ok=True)

    def test_buttons_do_not_move_on_press(self):
        css = (Path(__file__).resolve().parent.parent / "static" / "style.css").read_text()
        start = css.index("button {")
        chunk = css[start:start + 700]
        self.assertNotIn("filter:", chunk)
        self.assertNotIn("transform:", chunk)

    def test_index_tab_titles(self):
        html = self.client.get("/").data.decode("utf-8")
        for tid in ("toolTabTrimmer", "toolTabCompare", "toolTabDrift"):
            self.assertIn(f'id="{tid}"', html)
            self.assertIn("title=", html.split(tid)[1][:400])

    def test_trimmer_work_bar_and_split_markup(self):
        html = self.client.get("/").data.decode("utf-8")
        self.assertIn('id="workBar"', html)
        self.assertIn('id="trimSplit"', html)
        self.assertIn('id="trimOriginal"', html)
        self.assertIn('id="trimOut"', html)
        self.assertIn('id="trimHarvest"', html)

    def test_copy_buttons_in_index(self):
        html = self.client.get("/").data.decode("utf-8")
        for bid in (
            "trimOutCopyBtn",
            "trimHarvestCopyBtn",
            "datacopyOutCopyBtn",
            "webOutCopyBtn",
            "driftCopyBtn",
        ):
            self.assertIn(f'id="{bid}"', html)

    def test_live_first_schema_markup(self):
        html = self.client.get("/").data.decode("utf-8")
        for required_id in (
            "trimPairPane",
            "pairMaster",
            "pairClient",
            "liveMasterServer",
            "db_master",
            "db_client",
            "pickBak_master",
            "pickBak_client",
        ):
            self.assertIn(f'id="{required_id}"', html)
        self.assertNotIn('id="compareSubLivescan"', html)
        self.assertNotIn('id="applyTargetServer"', html)
        self.assertNotIn("reflect client's changes onto 105", html)
        self.assertIn("Review client extras", html)

    def test_backfill_then_assemble_update(self):
        from drift import scriptgen

        run_id = "bf-test"
        direction = "105_to_client"
        run_dir = self._tmpdir / run_id
        apply_dir = run_dir / direction / "apply"
        apply_dir.mkdir(parents=True, exist_ok=True)
        finding = {
            "id": "t1",
            "name": "[dbo].[T]",
            "bare_name": "T",
            "type": "SqlTable",
            "role": "modified",
            "columns": {"added": ["Flag"], "removed": [], "retyped": []},
            "client_columns": [
                {"name": "Flag", "type": "int", "max_length": 4, "precision": 10,
                 "scale": 0, "nullable": True, "is_pk": False},
            ],
            "master_columns": [
                {"name": "Flag", "type": "int", "max_length": 4, "precision": 10,
                 "scale": 0, "nullable": True, "is_pk": False},
            ],
        }
        idx = {"findings": [{"id": "t1", "name": finding["name"], "bare_name": "T",
                             "type": "SqlTable", "role": "modified", "review": "approved",
                             "path": "02_modified/tables/T"}]}
        (run_dir / direction / "index.json").write_text(json.dumps(idx), encoding="utf-8")
        (run_dir / "meta.json").write_text(json.dumps({"directions": [direction]}), encoding="utf-8")
        self._runs[run_id] = {
            "run_dir": run_dir,
            "meta": {"directions": [direction]},
            "workspaces": {direction: idx},
            "findings": {direction: [finding]},
        }
        r = self.client.post(
            f"/api/run/{run_id}/{direction}/backfill",
            json={"finding_id": "t1", "backfill": {"Flag": "9"}},
        )
        self.assertEqual(r.status_code, 200)
        apply = self.client.post(f"/api/run/{run_id}/{direction}/apply", json={})
        self.assertEqual(apply.status_code, 200)
        self.assertIn("UPDATE", apply.get_json()["script"])

    def test_backfill_400_without_in_memory_findings(self):
        run_id = "bf-disk"
        direction = "105_to_client"
        run_dir = self._tmpdir / run_id
        (run_dir / direction).mkdir(parents=True, exist_ok=True)
        (run_dir / direction / "index.json").write_text(
            json.dumps({"findings": [{"id": "x", "review": "pending"}]}), encoding="utf-8"
        )
        (run_dir / "meta.json").write_text(json.dumps({}), encoding="utf-8")
        self._runs[run_id] = {
            "run_dir": run_dir,
            "meta": {},
            "workspaces": {direction: json.loads((run_dir / direction / "index.json").read_text())},
        }
        r = self.client.post(
            f"/api/run/{run_id}/{direction}/backfill",
            json={"finding_id": "x", "backfill": {"C": "1"}},
        )
        self.assertEqual(r.status_code, 400)

    def test_datacopy_403_without_client_dst_role(self):
        for body in ({}, {"dst_role": "master"}):
            r = self.client.post("/api/datacopy/preview", json={**body, "tables": ["SysMenu"]})
            self.assertEqual(r.status_code, 403)

    def test_package_zip_403_client_to_105(self):
        run_id = "zip-403"
        direction = "client_to_105"
        run_dir = self._tmpdir / run_id
        apply_dir = run_dir / direction / "apply"
        apply_dir.mkdir(parents=True, exist_ok=True)
        (apply_dir / "add_update_on_105.sql").write_text("SELECT 1", encoding="utf-8")
        (run_dir / "meta.json").write_text(json.dumps({}), encoding="utf-8")
        (run_dir / direction / "index.json").write_text(json.dumps({"findings": []}), encoding="utf-8")
        self._runs[run_id] = {
            "run_dir": run_dir,
            "meta": {},
            "workspaces": {direction: {"findings": []}},
        }
        r = self.client.get(f"/api/run/{run_id}/{direction}/package.zip")
        self.assertEqual(r.status_code, 403)

    def test_package_zip_200_client_script(self):
        run_id = "zip-ok"
        direction = "105_to_client"
        run_dir = self._tmpdir / run_id
        apply_dir = run_dir / direction / "apply"
        apply_dir.mkdir(parents=True, exist_ok=True)
        (apply_dir / "add_update_on_client.sql").write_text("SELECT client_ok;", encoding="utf-8")
        (run_dir / "meta.json").write_text(json.dumps({}), encoding="utf-8")
        (run_dir / direction / "index.json").write_text(json.dumps({"findings": []}), encoding="utf-8")
        self._runs[run_id] = {
            "run_dir": run_dir,
            "meta": {},
            "workspaces": {direction: {"findings": []}},
        }
        r = self.client.get(f"/api/run/{run_id}/{direction}/package.zip")
        self.assertEqual(r.status_code, 200)
        zf = zipfile.ZipFile(BytesIO(r.data))
        names = set(zf.namelist())
        self.assertIn("add_update_on_client.sql", names)
        self.assertNotIn("add_update_on_105.sql", names)

    def test_webdeploy_preview_path_escape(self):
        from drift import config

        outside = self._tmpdir / "outside-webdeploy"
        outside.mkdir(exist_ok=True)
        r = self.client.post(
            "/api/webdeploy/preview",
            json={"src_root": str(outside), "dst_root": str(config.BACKUP_BROWSE_ROOT)},
        )
        self.assertEqual(r.status_code, 400)

    def test_run_file_optional_missing_is_204(self):
        run_id = "file-opt"
        run_dir = self._tmpdir / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / "meta.json").write_text("{}", encoding="utf-8")
        self._runs[run_id] = {"run_dir": run_dir, "meta": {}, "workspaces": {}}
        r = self.client.get(
            f"/api/run/{run_id}/file?path=client_to_105/apply/execution_report.json&optional=1"
        )
        self.assertEqual(r.status_code, 204)
        r2 = self.client.get(
            f"/api/run/{run_id}/file?path=client_to_105/apply/execution_report.json"
        )
        self.assertEqual(r2.status_code, 404)


if __name__ == "__main__":
    unittest.main()
