"""End-to-end battery: nested IF fixture through trimmer, diffing (compare), drift lenses.

Run:
  cd apps/drift-tool && python3.13 -m pytest drift/test_nested_if_battery.py -v
  cd apps/drift-tool && python3.13 drift/test_nested_if_battery.py  # writes report
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import app as flask_app  # noqa: E402
from drift.blocks import evaluate_condition, resolve_scope  # noqa: E402
from drift.diffing import diff_programmable  # noqa: E402
from drift.proc_lens import compare_procs  # noqa: E402
from drift.trimmer import trim_procedure  # noqa: E402

_FIX = Path(__file__).resolve().parent.parent / "fixtures"
MASTER = (_FIX / "OT_NestedIfBattery_master.sql").read_text(encoding="utf-8")
CLIENT = (_FIX / "OT_NestedIfBattery_client.sql").read_text(encoding="utf-8")

CID = 66


def _proc(body: str) -> str:
    return f"CREATE PROCEDURE [dbo].[OT_NestedIfBattery] AS\nBEGIN\n{body}\nEND"


class NestedIfBattery(unittest.TestCase):
    def test_condition_evaluator_matrix(self):
        cases = [
            ("@ClientActive IN (66, 99)", 66, "match"),
            ("@ClientActive IN (66, 99)", 50, "no_match"),
            ("@ClientActive NOT IN (33, 44)", 66, "match"),
            ("@ClientActive IN (50, 51)", 50, "match"),
            ("@ClientActive IN (50, 51)", 66, "no_match"),
            ("66 = @ClientActive", 66, "match"),
            ("@ClientActive = 165 OR @CompNo = 2", 66, "unknown"),
        ]
        for cond, cid, want in cases:
            self.assertEqual(evaluate_condition(cond, cid), want, cond)

    def test_trim_client_66_keeps_runtime_and_gates(self):
        r = trim_procedure(MASTER, CID)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        for token in (
            "master-arm-in-66",
            "runtime-and-ne",
            "runtime-or-in",
            "runtime-not-lt",
            "runtime-ge-le",
            "master-rev-eq-66",
            "master-not-in-66",
            "master-shared-tail",
        ):
            self.assertIn(token, sql, token)
        for gone in (
            "master-arm-165",
            "master-else-harvest",
            "master-generic-50-51",
            "nested-ghost-inner-66",
            "nested-outer-165-only",
        ):
            self.assertNotIn(gone, sql, gone)
        kinds = {h.get("kind") for h in r["harvest"]}
        self.assertTrue(kinds)  # excluded arms exist

    def test_trim_client_165_path(self):
        r = trim_procedure(MASTER, 165)
        self.assertTrue(r["ok"])
        sql = r["trimmed_sql"]
        self.assertIn("master-arm-165", sql)
        self.assertNotIn("master-arm-in-66", sql)

    def test_nested_ghost_client_66_inside_165_block_is_ignored(self):
        """Inner @ClientActive = 66 under outer @ClientActive = 165 must not run for client 66."""
        r = resolve_scope(MASTER, 66)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = "\n".join(r["relevant_blocks"])
        self.assertNotIn("nested-ghost-inner-66", joined)
        self.assertNotIn("nested-outer-165-only", joined)
        t = trim_procedure(MASTER, 66)
        self.assertTrue(t["ok"])
        self.assertNotIn("nested-ghost-inner-66", t["trimmed_sql"])
        drift = compare_procs(MASTER, CLIENT, 66, "active_read")
        self.assertTrue(drift["ok"])
        self.assertNotIn("nested-ghost-inner-66", drift["preview_left"])
        self.assertNotIn("nested-ghost-inner-66-client", drift["preview_right"])

    def test_nested_ghost_client_165_keeps_outer_not_inner_66(self):
        r = trim_procedure(MASTER, 165)
        self.assertTrue(r["ok"])
        sql = r["trimmed_sql"]
        self.assertIn("nested-outer-165-only", sql)
        self.assertNotIn("nested-ghost-inner-66", sql)

    def test_trim_generic_client_50(self):
        r = trim_procedure(MASTER, 50)
        self.assertTrue(r["ok"])
        sql = r["trimmed_sql"]
        self.assertIn("master-generic-50-51", sql)
        self.assertNotIn("master-arm-in-66", sql)

    def test_sql_compare_diff_programmable(self):
        d = diff_programmable(MASTER, CLIENT)
        self.assertEqual(d["change_kind"], "body")
        self.assertIn("client-arm-in-66", d.get("summary", "") + str(d))

    def test_drift_lens_active_read_hides_irrelevant_else(self):
        r = compare_procs(MASTER, CLIENT, CID, "active_read")
        self.assertTrue(r["ok"])
        self.assertFalse(r["identical"])
        self.assertIn("client-arm-in-66", r["preview_right"])
        self.assertNotIn("client-else-harvest", r["preview_right"])
        self.assertIn("CREATE OR ALTER", r["copy_sql"])
        self.assertEqual(r["copy_side"], "client")

    def test_drift_lens_full_shows_else(self):
        r = compare_procs(MASTER, CLIENT, CID, "full")
        self.assertTrue(r["ok"])
        self.assertIn("client-else-harvest", r["preview_right"])

    def test_api_trim_route(self):
        c = flask_app.test_client()
        resp = c.post("/api/trim", json={"definition": MASTER, "client_active_id": CID})
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertTrue(data["ok"])
        self.assertIn("master-arm-in-66", data["trimmed_sql"])


def write_report(path: Path) -> dict:
    report = {"procedure": "OT_NestedIfBattery", "client_active_id": CID, "checks": []}

    def record(name: str, ok: bool, detail: str = ""):
        report["checks"].append({"name": name, "ok": ok, "detail": detail})

    for cond, cid, want in [
        ("@ClientActive IN (66, 99)", 66, "match"),
        ("@ClientActive IN (50, 51)", 66, "no_match"),
    ]:
        got = evaluate_condition(cond, cid)
        record(f"evaluate_condition({cond!r}, {cid})", got == want, f"got {got}")

    t66 = trim_procedure(MASTER, 66)
    record("trimmer @66", t66.get("ok") and "master-arm-in-66" in (t66.get("trimmed_sql") or ""))

    t165 = trim_procedure(MASTER, 165)
    record("trimmer @165", t165.get("ok") and "master-arm-165" in (t165.get("trimmed_sql") or ""))

    d = diff_programmable(MASTER, CLIENT)
    record("sql_compare diff_programmable", d.get("change_kind") == "body", str(d.get("change_kind")))

    for lens in ("full", "active_read", "active_plus_else"):
        r = compare_procs(MASTER, CLIENT, CID, lens)
        record(f"drift lens {lens}", r.get("ok"), f"identical={r.get('identical')}")

    ar = compare_procs(MASTER, CLIENT, CID, "active_read")
    record(
        "drift active_read hides else",
        "client-else-harvest" not in (ar.get("preview_right") or ""),
    )

    c = flask_app.test_client()
    api = c.post("/api/trim", json={"definition": MASTER, "client_active_id": CID}).get_json()
    record("POST /api/trim", api.get("ok"))

    ghost = trim_procedure(MASTER, 66)
    record(
        "nested ghost @66 inside @165 block ignored",
        "nested-ghost-inner-66" not in (ghost.get("trimmed_sql") or ""),
    )
    g165 = trim_procedure(MASTER, 165)
    record(
        "nested @165 keeps outer not inner-66",
        "nested-outer-165-only" in (g165.get("trimmed_sql") or "")
        and "nested-ghost-inner-66" not in (g165.get("trimmed_sql") or ""),
    )

    report["passed"] = sum(1 for x in report["checks"] if x["ok"])
    report["failed"] = sum(1 for x in report["checks"] if not x["ok"])
    report["verdict"] = "PASS" if report["failed"] == 0 else "FAIL"

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    md = [
        "# OT_NestedIfBattery — validation report",
        "",
        f"**Verdict:** {report['verdict']} ({report['passed']}/{len(report['checks'])} checks)",
        "",
        "| Check | OK | Detail |",
        "|-------|-----|--------|",
    ]
    for row in report["checks"]:
        md.append(f"| {row['name']} | {'yes' if row['ok'] else '**no**'} | {row['detail']} |")
    md.append("")
    md.append("## Trimmer excerpt (@ClientActive=66)")
    md.append("```sql")
    md.append((t66.get("trimmed_sql") or "")[:2500])
    md.append("```")
    path.with_suffix(".md").write_text("\n".join(md), encoding="utf-8")
    return report


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "work" / "OT_NestedIfBattery_report"
    rep = write_report(out.with_suffix(".json"))
    print(json.dumps(rep, indent=2))
    raise SystemExit(0 if rep["verdict"] == "PASS" else 1)
