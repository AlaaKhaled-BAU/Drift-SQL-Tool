"""Integration: restore Olives_BO.bak twice, plant QA drift on client scratch only,
exercise livescan / proc_lens / trimmer / scriptgen detections.

Requires RUN_LIVE_DB=1 and /media/alaa/data/olives_pos/Olives_BO.bak on the host
(mounted into the scratch container via config.BACKUP_BROWSE_ROOT).

Run:
  cd apps/drift-tool && RUN_LIVE_DB=1 python3.13 drift/test_bak_restore_inject.py -v
"""
import os
import subprocess
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from drift import config, docker_mgmt, inspect_objects, livescan, proc_lens, restore, scriptgen, trimmer  # noqa: E402

BAK_PATH = Path("/media/alaa/data/olives_pos/Olives_BO.bak")
CLIENT_ACTIVE_ID = 66

ZZ_QA_PROC_ORIG = """
CREATE PROCEDURE dbo.zz_qa_proc @ClientActive int = NULL
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
 END
 ELSE
 BEGIN
  SELECT 'else-orig'
 END
 SELECT 'shared'
END
"""

ZZ_QA_ELSE_ONLY_ORIG = """
CREATE PROCEDURE dbo.zz_qa_else_only @ClientActive int = NULL
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm-shared'
 END
 ELSE
 BEGIN
  SELECT 'else-orig'
 END
END
"""


def _log(msg: str) -> None:
    print(msg, flush=True)


def _ddl(db_name: str, sql: str) -> None:
    conn = restore._connect(db_name)
    cur = conn.cursor()
    cur.execute(sql)
    conn.close()


def _scan_db(db_name: str) -> dict:
    conn = restore._connect(db_name)
    cur = conn.cursor(as_dict=True)
    snap = livescan.scan(cur)
    conn.close()
    return snap


def _proc_def(db_name: str, bare: str) -> str:
    defs = inspect_objects.get_definitions(db_name, {bare})
    return defs.get(bare) or ""


def _pick_alter_table(cur) -> str | None:
    cur.execute(
        "SELECT t.name FROM sys.tables t "
        "JOIN sys.columns c ON c.object_id = t.object_id "
        "WHERE t.is_ms_shipped = 0 "
        "GROUP BY t.name HAVING COUNT(*) >= 1 ORDER BY t.name"
    )
    for row in cur.fetchall():
        name = row["name"] if isinstance(row, dict) else row[0]
        if name.startswith("zz_qa_"):
            continue
        return name
    return None


@unittest.skipUnless(os.environ.get("RUN_LIVE_DB") == "1", "set RUN_LIVE_DB=1 for scratch MSSQL integration")
@unittest.skipUnless(BAK_PATH.is_file(), f"missing backup: {BAK_PATH}")
class BakRestoreInjectIntegration(unittest.TestCase):
    master_db: str = ""
    client_db: str = ""
    report: dict
    alter_table: str | None = None
    skip_column_b: str | None = None
    SKIP_PIPELINE_SQLPACKAGE: str | None = None

    @classmethod
    def setUpClass(cls):
        cls.report = {"planted": {}, "detected": {}, "timings": {}, "failures": []}

    def _t(self, label: str):
        return _PhaseTimer(self.report["timings"], label)

    def _plant(self, case: str, expected):
        self.report["planted"][case] = expected

    def _detect(self, case: str, actual):
        self.report["detected"][case] = actual

    def _fail(self, case: str, detail: str):
        self.report["failures"].append(f"{case}: {detail}")

    def _assert_case(self, case: str, ok: bool, detail: str = ""):
        if not ok:
            self._fail(case, detail or "assertion failed")

    def test_bak_restore_inject_detections(self):
        ts = int(time.time())
        self.master_db = f"zz_qa_master_{ts}"
        self.client_db = f"zz_qa_client_{ts}"

        try:
            with self._t("ensure_running"):
                docker_mgmt.ensure_running(_log)

            with self._t("restore_master"):
                restore.restore_backup(BAK_PATH, self.master_db, _log)
            with self._t("restore_client"):
                restore.restore_backup(BAK_PATH, self.client_db, _log)

            # --- identical procs on both (original ELSE) ---
            with self._t("create_procs_both"):
                for db in (self.master_db, self.client_db):
                    _ddl(db, ZZ_QA_PROC_ORIG)
                    _ddl(db, ZZ_QA_ELSE_ONLY_ORIG)

            snap_m = _scan_db(self.master_db)
            snap_c = _scan_db(self.client_db)
            r0 = livescan.quick_compare(snap_m, snap_c)
            self._plant("baseline_procs_match", {"body_changed": [], "extra_in_b": []})
            self._detect("baseline_procs_match", {
                "body_changed": r0["body_changed"],
                "extra_in_b": [x for x in r0["extra_in_b"] if x.startswith("zz_qa_")],
            })
            self._assert_case(
                "baseline_procs_match",
                "zz_qa_proc" not in r0["body_changed"] and "zz_qa_else_only" not in r0["body_changed"],
                f"unexpected early drift: {r0}",
            )

            # --- client-only arm inject on zz_qa_proc ---
            _ddl(
                self.client_db,
                """
ALTER PROCEDURE dbo.zz_qa_proc @ClientActive int = NULL
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
  SELECT 'INJECT-ARM'
 END
 ELSE
 BEGIN
  SELECT 'else-orig'
 END
 SELECT 'shared'
END
""",
            )
            snap_m = _scan_db(self.master_db)
            snap_c = _scan_db(self.client_db)
            r_proc = livescan.quick_compare(snap_m, snap_c)
            self._plant("zz_qa_proc_body_changed", "zz_qa_proc in body_changed")
            self._detect("zz_qa_proc_body_changed", r_proc["body_changed"])
            self._assert_case(
                "zz_qa_proc_body_changed",
                "zz_qa_proc" in r_proc["body_changed"],
                str(r_proc["body_changed"]),
            )

            master_def = _proc_def(self.master_db, "zz_qa_proc")
            client_def = _proc_def(self.client_db, "zz_qa_proc")
            lens_full = proc_lens.compare_procs(
                master_def, client_def, CLIENT_ACTIVE_ID, "full", direction="client_to_105"
            )
            self._plant("proc_lens_full_not_identical", {"identical": False, "copy_has_INJECT": True})
            self._detect("proc_lens_full_not_identical", {
                "identical": lens_full.get("identical"),
                "copy_sql_snip": (lens_full.get("copy_sql") or "")[:200],
            })
            self._assert_case("proc_lens_full_not_identical", lens_full.get("identical") is False)
            self._assert_case(
                "proc_lens_copy_inject",
                "INJECT-ARM" in (lens_full.get("copy_sql") or ""),
                lens_full.get("copy_sql", "")[:500],
            )

            # --- client-only ELSE on zz_qa_else_only ---
            _ddl(
                self.client_db,
                """
ALTER PROCEDURE dbo.zz_qa_else_only @ClientActive int = NULL
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm-shared'
 END
 ELSE
 BEGIN
  SELECT 'else-INJECT'
 END
END
""",
            )
            master_else = _proc_def(self.master_db, "zz_qa_else_only")
            client_else = _proc_def(self.client_db, "zz_qa_else_only")
            ar = proc_lens.compare_procs(master_else, client_else, CLIENT_ACTIVE_ID, "active_read")
            full_else = proc_lens.compare_procs(master_else, client_else, CLIENT_ACTIVE_ID, "full")
            ape = proc_lens.compare_procs(master_else, client_else, CLIENT_ACTIVE_ID, "active_plus_else")
            self._plant("else_only_lens", {
                "active_read_identical": True,
                "full_identical": False,
                "active_plus_else_identical": False,
            })
            self._detect("else_only_lens", {
                "active_read_identical": ar.get("identical"),
                "full_identical": full_else.get("identical"),
                "active_plus_else_identical": ape.get("identical"),
            })
            self._assert_case("else_only_active_read", ar.get("identical") is True, str(ar))
            self._assert_case("else_only_full_diff", full_else.get("identical") is False)
            self._assert_case("else_only_ape_diff", ape.get("identical") is False)

            trim_c = trimmer.trim_procedure(client_else, CLIENT_ACTIVE_ID)
            self._plant("trimmer_hides_else_inject", "else-INJECT not in trimmed_sql")
            trimmed = trim_c.get("trimmed_sql") or ""
            self._detect("trimmer_hides_else_inject", {
                "ok": trim_c.get("ok"),
                "has_else_inject": "else-INJECT" in trimmed,
                "has_arm": "arm-shared" in trimmed,
            })
            self._assert_case("trimmer_hides_else_inject", trim_c.get("ok") and "else-INJECT" not in trimmed)

            # --- extra table client-only ---
            _ddl(
                self.client_db,
                "CREATE TABLE dbo.zz_qa_extra (Id int NOT NULL PRIMARY KEY, Note nvarchar(40) NULL)",
            )
            snap_m = _scan_db(self.master_db)
            snap_c = _scan_db(self.client_db)
            r_extra = livescan.quick_compare(snap_m, snap_c)
            self._plant("zz_qa_extra_extra_in_b", "zz_qa_extra in extra_in_b (a=master,b=client)")
            self._detect("zz_qa_extra_extra_in_b", {
                "extra_in_b": r_extra["extra_in_b"],
                "missing_in_b": r_extra["missing_in_b"],
            })
            self._assert_case(
                "zz_qa_extra_extra_in_b",
                "zz_qa_extra" in r_extra["extra_in_b"],
                str(r_extra),
            )

            # --- added column on client (step B) ---
            conn = restore._connect(self.client_db)
            cur = conn.cursor(as_dict=True)
            self.alter_table = _pick_alter_table(cur)
            conn.close()
            if self.alter_table:
                try:
                    _ddl(
                        self.client_db,
                        f"ALTER TABLE dbo.[{self.alter_table}] ADD [zz_qa_col] nvarchar(20) NULL",
                    )
                except Exception as e:  # noqa: BLE001
                    self.skip_column_b = str(e)
                    self._plant("column_added", f"skipped B: {e}")
                else:
                    snap_m = _scan_db(self.master_db)
                    snap_c = _scan_db(self.client_db)
                    r_col = livescan.quick_compare(snap_m, snap_c)
                    col_key = f"{self.alter_table}.zz_qa_col"
                    self._plant("column_added", col_key)
                    self._detect("column_added", r_col["columns"]["added"])
                    self._assert_case("column_added", col_key in r_col["columns"]["added"], str(r_col["columns"]))

                    cols_map = inspect_objects.get_columns(self.client_db, {self.alter_table})
                    col_meta = next(
                        (c for c in cols_map.get(self.alter_table, []) if c["name"] == "zz_qa_col"),
                        None,
                    )
                    if col_meta:
                        finding = [{
                            "name": f"[dbo].[{self.alter_table}]",
                            "bare_name": self.alter_table,
                            "type": "SqlTable",
                            "role": "modified",
                            "columns": {"added": ["zz_qa_col"], "removed": [], "retyped": []},
                            "master_columns": cols_map.get(self.alter_table, []),
                            "client_columns": cols_map.get(self.alter_table, []),
                        }]
                        asm = scriptgen.assemble(finding, "105", "client_to_105")
                        self._plant("scriptgen_added_column", "ALTER ADD zz_qa_col in script")
                        self._detect("scriptgen_added_column", asm["script"][:300])
                        self._assert_case(
                            "scriptgen_added_column",
                            "zz_qa_col" in asm["script"] and "ALTER TABLE" in asm["script"],
                            asm["script"],
                        )
            else:
                self.skip_column_b = "no suitable user table"
                self._plant("column_added", "skipped B: no table")

            # --- optional pipeline / sqlpackage ---
            self._try_pipeline()

        finally:
            with self._t("drop_databases"):
                restore.drop_database(self.master_db, _log)
                restore.drop_database(self.client_db, _log)

        self._print_report()
        self.assertEqual([], self.report["failures"], "\n".join(self.report["failures"]))

    def _try_pipeline(self):
        try:
            from drift import pipeline  # noqa: WPS433 — optional heavy import
        except ImportError as e:
            self.SKIP_PIPELINE_SQLPACKAGE = f"import pipeline: {e}"
            return

        if not Path(config.SQLPACKAGE_BIN).is_file():
            self.SKIP_PIPELINE_SQLPACKAGE = "sqlpackage binary missing"
            return

        with self._t("pipeline_same_bak_zero"):
            try:
                z = pipeline.run_compare(
                    str(BAK_PATH),
                    str(BAK_PATH),
                    directions=["client_to_105"],
                    log=_log,
                    type_filter={"Tables", "Procedures"},
                )
                findings = z.get("findings_by_direction", {}).get("client_to_105", [])
                drift_count = len([f for f in findings if f.get("role") != "identical"])
                self._plant("pipeline_same_bak", {"drift_findings": 0})
                self._detect("pipeline_same_bak", {"drift_findings": drift_count, "run_id": z.get("run_id")})
                self._assert_case("pipeline_same_bak", drift_count == 0, f"count={drift_count}")
            except Exception as e:  # noqa: BLE001
                self.SKIP_PIPELINE_SQLPACKAGE = f"same-bak compare: {e}"
                return

        bak_name = f"zz_qa_mut_{int(time.time())}.bak"
        container_bak = f"/var/opt/mssql/data/{bak_name}"
        host_mutated = config.WORK_DIR / bak_name
        with self._t("backup_mutated_client"):
            try:
                _ddl(
                    self.client_db,
                    f"BACKUP DATABASE [{self.client_db}] TO DISK = '{container_bak}' WITH INIT, FORMAT",
                )
            except Exception as e:  # noqa: BLE001
                self.SKIP_PIPELINE_SQLPACKAGE = f"BACKUP scratch: {e}"
                return

        cp = subprocess.run(
            ["docker", "cp", f"{config.CONTAINER_NAME}:{container_bak}", str(host_mutated)],
            capture_output=True,
            text=True,
        )
        if cp.returncode != 0:
            self.SKIP_PIPELINE_SQLPACKAGE = f"docker cp failed: {cp.stderr.strip()}"
            return

        with self._t("pipeline_mutated_bak"):
            try:
                m = pipeline.run_compare(
                    str(BAK_PATH),
                    str(host_mutated),
                    directions=["105_to_client"],
                    log=_log,
                    type_filter={"Tables", "Procedures"},
                    client_active_id=CLIENT_ACTIVE_ID,
                )
                findings = m.get("findings_by_direction", {}).get("105_to_client", [])
                names = {f.get("bare_name") or f.get("name") for f in findings}
                self._plant("pipeline_mutated", {"zz_qa_extra": "added", "zz_qa_proc": "modified"})
                self._detect("pipeline_mutated", {
                    "finding_count": len(findings),
                    "bare_names_sample": sorted(names)[:30],
                })
            except Exception as e:  # noqa: BLE001
                self.SKIP_PIPELINE_SQLPACKAGE = f"mutated compare: {e}"
            finally:
                if host_mutated.is_file():
                    host_mutated.unlink(missing_ok=True)

    def _print_report(self):
        _log("\n=== bak_restore_inject REPORT ===")
        for case in sorted(set(self.report["planted"]) | set(self.report["detected"])):
            _log(f"  [{case}]")
            _log(f"    planted:  {self.report['planted'].get(case)}")
            _log(f"    detected: {self.report['detected'].get(case)}")
        _log("  timings:")
        for k, v in self.report["timings"].items():
            _log(f"    {k}: {v:.1f}s")
        if self.skip_column_b:
            _log(f"  column B note: {self.skip_column_b}")
        if self.SKIP_PIPELINE_SQLPACKAGE:
            _log(f"  SKIP_PIPELINE_SQLPACKAGE: {self.SKIP_PIPELINE_SQLPACKAGE}")
        if self.report["failures"]:
            _log("  FAIL:")
            for f in self.report["failures"]:
                _log(f"    - {f}")
        else:
            _log("  FAIL: (none)")


class _PhaseTimer:
    def __init__(self, timings: dict, label: str):
        self.timings = timings
        self.label = label
        self.t0 = 0.0

    def __enter__(self):
        self.t0 = time.time()
        return self

    def __exit__(self, *exc):
        self.timings[self.label] = time.time() - self.t0
        return False


if __name__ == "__main__":
    unittest.main(verbosity=2)
