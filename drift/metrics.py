"""Computed quality scorecard for a completed run. Every number here is
derived from that run's actual output on disk (index.json, meta.json, and the
captured .master.sql/.client.sql/.diff files) -- nothing hardcoded, nothing
copied from a prior session's numbers. Re-running this against a new run
recomputes everything fresh, including the accuracy sample, which is why
`sample_accuracy()` takes a seed: same run + same seed = same sample =
reproducible; a different seed re-draws an independent check.

This module answers one question per section: coverage (does the tool try to
look at everything), noise separation (is the signal usable), accuracy
(independently re-verified, not self-reported), blast radius (is the new
dependency feature actually resolving), attribution (is the crown-jewel
feature even available for this client), runtime (how long does it take).
"""
import json
import random
import re
from pathlib import Path

try:
    from . import diffing
except ImportError:  # allows standalone script execution
    import diffing

_COMMENT_LINE = re.compile(r"--[^\n]*")
_COMMENT_BLOCK = re.compile(r"/\*.*?\*/", re.DOTALL)
_WS = re.compile(r"\s+")
_PROGRAMMABLE_TYPES = {
    "SqlProcedure", "SqlView", "SqlScalarFunction",
    "SqlInlineTableValuedFunction", "SqlMultiStatementTableValuedFunction",
    "SqlDmlTrigger", "SqlDatabaseDdlTrigger",
}
# Follow-up (2026-07-26): this set predates the qwen-review L-3 extended-type
# capture (inspect_objects.py's get_fk/index/check_constraint/default_
# constraint/sequence/synonym/table_type/udt_definitions, merged into the
# SAME master_defs/client_defs dicts pipeline.py already diffs for
# programmable objects) and was never widened for it. Left alone,
# sample_accuracy() below routed every FK/index/constraint/sequence/
# synonym/table-type/UDT finding into "not captured -- limitation" and
# never even attempted to read their .master.sql/.client.sql sidecar
# files -- even though those files exist on disk now, understating real
# coverage and making it impossible to independently verify the exact
# class of finding (FK/index/etc) the D1 no_difference fix and the
# original measured D-F1 bug were both about. Role membership (SqlRole)
# is the one type genuinely still uncaptured -- no get_role_definitions
# exists -- and correctly stays outside this set.
_EXTENDED_TEXT_TYPES = {
    "SqlForeignKeyConstraint", "SqlIndex", "SqlCheckConstraint", "SqlDefaultConstraint",
    "SqlSequence", "SqlSynonym", "SqlTableType", "SqlUserDefinedDataType",
}
_TEXT_CAPTURED_TYPES = _PROGRAMMABLE_TYPES | _EXTENDED_TEXT_TYPES


def _norm(t):
    if not t:
        return ""
    t = _COMMENT_BLOCK.sub(" ", t)
    t = _COMMENT_LINE.sub(" ", t)
    return _WS.sub(" ", t).strip().casefold()


def compute(run_dir: Path, sample_size: int = 40, seed: int = 0) -> dict:
    run_dir = Path(run_dir)
    meta = json.loads((run_dir / "meta.json").read_text())
    workspaces = {}
    for d in meta["directions"]:
        workspaces[d] = json.loads((run_dir / d / "index.json").read_text())

    return {
        "run_id": meta["run_id"],
        "coverage": _coverage(workspaces),
        "noise_separation": _noise_separation(workspaces),
        "accuracy": {d: sample_accuracy(run_dir / d, idx, sample_size, seed) for d, idx in workspaces.items()},
        "blast_radius": _blast_radius_metrics(meta, workspaces),
        "attribution": _attribution_metrics(meta, workspaces),
        "runtime": _runtime_metrics(meta),
    }


def _coverage(workspaces: dict) -> dict:
    """Of everything flagged as real drift, how much gets a full captured
    diff (not just a name + role)? Answers 'how complete is the detail', not
    'was anything missed' (that's what accuracy checks)."""
    out = {}
    for d, idx in workspaces.items():
        findings = idx["findings"]
        # D1: no_difference is demoted-from-structural, not real drift (same
        # reasoning formatting_only already gets here) -- excluded from the
        # coverage denominator alongside it.
        structural = [f for f in findings if f["category"] not in ("formatting_only", "no_difference")]
        by_type = {}
        for f in structural:
            t = by_type.setdefault(f["type"], {"total": 0, "detailed": 0})
            t["total"] += 1
            # has_definition/has_columns = evidence was actually captured to disk, whether
            # or not there's a diff (added/only_on_other objects are single-sided -- no
            # diff by definition -- but their full body/columns ARE captured and written).
            if f.get("has_definition") or f.get("has_columns"):
                t["detailed"] += 1
        with_detail = sum(t["detailed"] for t in by_type.values())
        out[d] = {
            "total_structural_findings": len(structural),
            "with_full_detail": with_detail,
            "detail_coverage_pct": round(100 * with_detail / len(structural), 1) if structural else None,
            "by_type": by_type,
            "note": "Full detail = captured byte-exact definition (procs/views/funcs/triggers, and since "
                    "the L-3 extended capture: FK/index/check+default-constraint/sequence/synonym/"
                    "table-type/UDT too) or captured columns (tables), present whether the finding is a "
                    "diff or single-sided (added/only_on_other). Role membership (SqlRole) is the one "
                    "type still getting correct role/name only, no body-level capture.",
        }
    return out


def _noise_separation(workspaces: dict) -> dict:
    out = {}
    for d, idx in workspaces.items():
        c = idx["counts"]
        raw_total = sum(c.values())
        signal = c["added"] + c["modified"] + c["only_on_other"]
        out[d] = {
            "raw_differences_seen": raw_total,
            "real_signal": signal,
            "signal_pct": round(100 * signal / raw_total, 1) if raw_total else None,
            "noise_breakdown": {
                "formatting_only": c["formatting_only"], "no_difference": c.get("no_difference", 0),
                "documentation": c["documentation"],
                "cascading": c["cascading"], "excluded_client_named": c["excluded"],
            },
        }
    return out


def sample_accuracy(workspace_dir: Path, index: dict, sample_size: int, seed: int) -> dict:
    """Draws a fresh stratified random sample and independently re-derives
    each finding's classification from the captured evidence on disk --
    the same method used for manual validation, now reusable and reproducible.
    A confirmed/anomaly/limitation breakdown, not a single fudgeable number."""
    findings = index["findings"]
    by_bucket = {}
    for f in findings:
        key = "formatting" if f["category"] == "formatting_only" else \
              "no_difference" if f["category"] == "no_difference" else f["role"]
        by_bucket.setdefault(key, []).append(f)

    rng = random.Random(seed)
    per_bucket = max(1, sample_size // max(1, len(by_bucket)))
    sample = []
    for bucket, items in by_bucket.items():
        sample += rng.sample(items, min(per_bucket, len(items)))

    confirmed, anomaly, limitation = 0, 0, 0
    anomaly_details = []
    for f in sample:
        path = workspace_dir / f["path"]
        is_table = f["type"] == "SqlTable"
        # Follow-up (2026-07-26): widened from "is_programmable" / _PROGRAMMABLE_TYPES
        # to _TEXT_CAPTURED_TYPES -- FK/index/check/default-constraint/sequence/
        # synonym/table-type/UDT findings get the exact same .master.sql/.client.sql
        # sidecar files as procs/views/funcs/triggers since the L-3 extended capture
        # (same master_defs/client_defs merge in pipeline.py); only the SELECT logic
        # that produced the text differs, which this function doesn't need to know.
        is_text_captured = f["type"] in _TEXT_CAPTURED_TYPES

        # Evidence presence, per type -- tables carry columns.json (never .sql files),
        # text-captured objects carry .master.sql/.client.sql (never columns.json).
        # Checking the wrong file for a type is what produced false "anomalies" on
        # real data before this fix: every added/only_on_other TABLE looked like
        # has_master=False/has_client=False because tables never get .sql files.
        master_txt = client_txt = None
        cols = None
        if is_table:
            cols = _read_json(Path(str(path) + ".columns.json"))
            has_m = bool(cols and cols.get("master_columns"))
            has_c = bool(cols and cols.get("client_columns"))
        elif is_text_captured:
            master_txt = _read(Path(str(path) + ".master.sql"))
            client_txt = _read(Path(str(path) + ".client.sql"))
            has_m, has_c = master_txt is not None, client_txt is not None
        else:
            has_m = has_c = False  # role membership (SqlRole): genuinely not captured
        is_checkable_type = is_table or is_text_captured

        if f["category"] == "formatting_only":
            if has_m and has_c and _norm(master_txt) == _norm(client_txt) and master_txt != client_txt:
                confirmed += 1
            else:
                anomaly += 1
                anomaly_details.append({"name": f["name"], "issue": "formatting_only re-check failed"})
        elif f["category"] == "no_difference":
            # D1: this finding's role is always "modified" underneath (see
            # pipeline.py's _enrich) -- checked by CATEGORY first, same as
            # formatting_only just above, so it never falls into the
            # "modified" branch's re-check and gets falsely flagged as an
            # anomaly for being exactly what it correctly is. Note: extended
            # types (FK/index/constraint/sequence/table-type) fall to
            # `limitation` here even though D1a captures their text now --
            # is_checkable_type/is_programmable above is a pre-existing set
            # that predates that capture and wasn't widened for it; a
            # pre-existing gap, not something introduced by D1 (flagged
            # separately, not fixed in this pass).
            if is_table:
                if cols and diffing.diff_columns(cols["master_columns"], cols["client_columns"])["change_kind"] == "none":
                    confirmed += 1
                elif cols:
                    anomaly += 1
                    anomaly_details.append({"name": f["name"], "issue": "flagged no_difference but recomputed column-diff is NOT empty"})
                else:
                    limitation += 1
            elif has_m and has_c and _norm(master_txt) == _norm(client_txt):
                confirmed += 1
            elif has_m and has_c:
                anomaly += 1
                anomaly_details.append({"name": f["name"], "issue": "flagged no_difference but normalized-different"})
            else:
                limitation += 1
        elif f["role"] == "modified":
            if is_table:
                if cols and diffing.diff_columns(cols["master_columns"], cols["client_columns"])["change_kind"] != "none":
                    confirmed += 1
                elif cols:
                    anomaly += 1
                    anomaly_details.append({"name": f["name"], "issue": "flagged modified but recomputed column-diff is empty"})
                else:
                    limitation += 1
            elif has_m and has_c and _norm(master_txt) != _norm(client_txt):
                confirmed += 1
            elif has_m and has_c:
                anomaly += 1
                anomaly_details.append({"name": f["name"], "issue": "flagged modified but normalized-identical"})
            else:
                limitation += 1
        elif f["role"] == "added":
            if has_c and not has_m:
                confirmed += 1
            elif is_checkable_type:
                anomaly += 1
                anomaly_details.append({"name": f["name"], "issue": f"added but has_master={has_m} has_client={has_c}"})
            else:
                limitation += 1
        elif f["role"] == "only_on_other":
            if has_m and not has_c:
                confirmed += 1
            elif is_checkable_type:
                anomaly += 1
                anomaly_details.append({"name": f["name"], "issue": f"only_on_other but has_master={has_m} has_client={has_c}"})
            else:
                limitation += 1

    checked = confirmed + anomaly  # limitation = not checkable in Phase 1, excluded from the rate on purpose
    return {
        "sample_size": len(sample), "confirmed": confirmed, "anomaly": anomaly,
        "limitation_uncaptured_type": limitation,
        "accuracy_pct_of_checkable": round(100 * confirmed / checked, 1) if checked else None,
        "anomaly_details": anomaly_details,
        "seed": seed,
    }


def _read(path: Path):
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None


def _blast_radius_metrics(meta: dict, workspaces: dict) -> dict:
    dep = meta.get("dependency_coverage", {})
    changed = dep.get("changed_objects", 0)
    resolved = dep.get("callers_resolved_for", 0)
    out = {
        "changed_objects": changed,
        "objects_with_any_caller_found": resolved,
        "caller_resolution_pct": round(100 * resolved / changed, 1) if changed else None,
        "dynamic_sql_procs_in_db": dep.get("dynamic_sql_procs", 0),
        "note": "Caller edges from sys.sql_expression_dependencies (SQL Server's own compile-time "
                "catalog) -- exact where resolved. Objects reached only through dynamic SQL are "
                "invisible to this catalog, so this is a floor on caller count, not a ceiling.",
    }
    for d, idx in workspaces.items():
        modified = [f for f in idx["findings"] if f["role"] == "modified"]
        counts = sorted((f["callers"]["count"] for f in modified), reverse=True)
        out[d] = {
            "modified_findings": len(modified),
            "with_zero_known_callers": sum(1 for c in counts if c == 0),
            "avg_callers": round(sum(counts) / len(counts), 1) if counts else 0,
            "max_callers": counts[0] if counts else 0,
            "high_blast_radius_gt5": sum(1 for c in counts if c > 5),
        }
    return out


def _attribution_metrics(meta: dict, workspaces: dict) -> dict:
    out = {"trigger_present": meta.get("trigger_present", {})}
    for d, idx in workspaces.items():
        modified = [f for f in idx["findings"] if f["role"] == "modified"]
        attributed = sum(1 for f in modified if f.get("attribution"))
        out[d] = {
            "modified_findings": len(modified),
            "with_attribution": attributed,
            "attribution_coverage_pct": round(100 * attributed / len(modified), 1) if modified else None,
            "lost_fixes_found": len(idx.get("lost_fixes", [])),
        }
    return out


def _runtime_metrics(meta: dict) -> dict:
    timings = meta.get("timings", {})
    return {
        "total_seconds": timings.get("total"),
        "by_phase": {k: v for k, v in timings.items() if k != "total"},
    }
