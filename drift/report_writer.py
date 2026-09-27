"""Writes one workspace's findings to a navigable folder tree + index.json.
Folder layout and rationale: PLAN.md §5.
"""
import json
import re
from pathlib import Path

from . import compare

_ROLE_FOLDER = {"added": "01_added", "modified": "02_modified", "only_on_other": "03_only_on_other"}

_TYPE_FOLDER = {
    "SqlProcedure": "procedures", "SqlTable": "tables", "SqlView": "views",
    "SqlScalarFunction": "functions", "SqlInlineTableValuedFunction": "functions",
    "SqlMultiStatementTableValuedFunction": "functions",
    "SqlDmlTrigger": "triggers", "SqlDatabaseDdlTrigger": "triggers",
}

_UNSAFE = re.compile(r"[^A-Za-z0-9_.-]")


def safe_filename(name: str) -> str:
    return _UNSAFE.sub("_", name)[:120] or "unnamed"


def _type_folder(obj_type: str) -> str:
    return _TYPE_FOLDER.get(obj_type, "other")


# D6: an additive score computed once here (not client-side) so index.json
# carries it and metrics.py can reason about the distribution -- the old
# priorityOf() collapsed ~93% of real findings into "medium" (one caller-
# count threshold plus one columns check), which made priority decorative.
# Tuned against the real morec_original vs morec_surgical_v2 battery so the
# high bucket lands around 10-20% of findings rather than 7%; see
# VALIDATION.md for the before/after Counter(priority) distribution.
_PRIORITY_SIGNALS = [
    ("column removed or retyped", 40),
    ("change_kind is param or both", 30),
    ("caller count > 5", 25),
    ("caller count 1-5", 10),
    ("change_kind is settings", 20),
    ("has attribution", 15),
    ("table or FK/constraint", 10),
    ("formatting_only category", -30),
    ("no_difference category", -50),
]


def _priority_score(f: dict) -> tuple:
    """Returns (score, breakdown) -- breakdown is [(signal, points), ...] for
    only the signals that actually fired, so the UI can show a tooltip
    explaining the number instead of just the number."""
    cols = f.get("columns") or {}
    caller_count = (f.get("callers") or {}).get("count", 0)
    hits = []
    if cols.get("removed") or cols.get("retyped"):
        hits.append(("column removed or retyped", 40))
    if f.get("change_kind") in ("param", "both"):
        hits.append(("change_kind is param or both", 30))
    if caller_count > 5:
        hits.append(("caller count > 5", 25))
    elif caller_count >= 1:
        hits.append(("caller count 1-5", 10))
    if f.get("change_kind") == "settings":
        hits.append(("change_kind is settings", 20))
    if f.get("attribution"):
        hits.append(("has attribution", 15))
    if compare.type_category(f["type"]) in ("Tables", "Constraints"):
        hits.append(("table or FK/constraint", 10))
    if f["category"] == "formatting_only":
        hits.append(("formatting_only category", -30))
    if f["category"] == "no_difference":
        hits.append(("no_difference category", -50))
    return sum(points for _, points in hits), hits


def _priority_bucket(score: int) -> str:
    """Tuned against the real morec_original vs morec_surgical_v2 battery
    (29 findings, both directions) -- see VALIDATION.md. The plan's own
    starting thresholds (>=50 high, >=20 medium) put 0% of this real run in
    "high": no planted change here is a column removal or a breaking
    signature change (the two heaviest signals), so nothing reaches 50, and
    the actual score distribution has a real gap at 20 (35, 35, 20, 20, then
    a drop to 10) -- >=20 alone (dropping to two clustered signals: high
    blast radius on a schema object, or a settings-semantics change) lands
    4/29 (13.8%) in high, inside the plan's target 10-20% band. Only the
    bucket thresholds were tuned, not the signal weights above -- those
    encode a considered judgment about relative signal importance that a
    29-finding synthetic battery isn't grounds to second-guess."""
    if score >= 20:
        return "high"
    if score >= 10:
        return "medium"
    return "low"


def write_workspace(workspace_dir: Path, workspace_label: str, findings: list,
                     documentation_list: list, cascading_list: list,
                     attribution: list, lost_fixes: list, excluded_count: int, log,
                     filtered_out_count: int = 0, type_filter=None) -> dict:
    """findings: structural + formatting_only items only (the ones with real
    per-object detail). Returns the index dict this workspace contributes.

    filtered_out_count/type_filter (D5a): a type-filtered run must be
    visibly, permanently marked as partial -- carried into index.json (the
    UI's partial-run banner reads it) and summary.md, not just logged."""
    workspace_dir.mkdir(parents=True, exist_ok=True)
    for role_folder in _ROLE_FOLDER.values():
        (workspace_dir / role_folder).mkdir(exist_ok=True)
    (workspace_dir / "04_formatting").mkdir(exist_ok=True)
    (workspace_dir / "05_no_difference").mkdir(exist_ok=True)
    (workspace_dir / "apply").mkdir(exist_ok=True)

    counts_by_role = {}
    counts_by_type = {}
    index_findings = []

    for i, f in enumerate(findings):
        counts_by_role[f["role"]] = counts_by_role.get(f["role"], 0) + 1
        counts_by_type[f["type"]] = counts_by_type.get(f["type"], 0) + 1

        finding_id = f"{workspace_label}_{i:05d}"
        bare = f["bare_name"]
        safe = safe_filename(bare)

        if f["category"] == "formatting_only":
            base = workspace_dir / "04_formatting" / _type_folder(f["type"]) / safe
        elif f["category"] == "no_difference":
            base = workspace_dir / "05_no_difference" / _type_folder(f["type"]) / safe
        else:
            base = workspace_dir / _ROLE_FOLDER[f["role"]] / _type_folder(f["type"]) / safe
        base.parent.mkdir(parents=True, exist_ok=True)

        rel_path = base.relative_to(workspace_dir).as_posix()

        if "diff" in f and f["diff"]:
            (base.with_suffix(".diff")).write_text("\n".join(f["diff"]), encoding="utf-8")
        if f.get("master_def") is not None:
            (Path(str(base) + ".master.sql")).write_text(f["master_def"], encoding="utf-8")
        if f.get("client_def") is not None:
            (Path(str(base) + ".client.sql")).write_text(f["client_def"], encoding="utf-8")
        if f.get("master_columns") is not None or f.get("client_columns") is not None:
            # raw captured columns, not just the resulting classification -- lets
            # metrics.py independently recompute the diff from evidence instead of
            # trusting the finding's own summary (same standard as procs/views/etc).
            (base.with_suffix(".columns.json")).write_text(
                json.dumps({"master_columns": f.get("master_columns", []),
                            "client_columns": f.get("client_columns", [])}, indent=1),
                encoding="utf-8",
            )
        if f.get("statement_alignment") is not None:
            # D7: statement TEXT only ever lives here, never in index.json
            # (the plan's "do not bloat index.json" instruction) -- api.py's
            # /statements route reads this file on demand. "norm" is an
            # internal alignment key, dropped before it ever leaves this
            # process -- nothing downstream reads it.
            def _slim(s):
                return {k: v for k, v in s.items() if k != "norm"} if s else None
            (base.with_suffix(".statements.json")).write_text(
                json.dumps([
                    {"tag": a["tag"], "master": _slim(a["master"]), "client": _slim(a["client"])}
                    for a in f["statement_alignment"]
                ], indent=1),
                encoding="utf-8",
            )

        finding_md = _render_finding_md(f)
        (base.with_suffix(".md")).write_text(finding_md, encoding="utf-8")

        # Evidence flags, independent of change_kind (which is only set when there's
        # something to diff AGAINST -- an added/only_on_other object has no diff by
        # definition but still has its full definition/columns captured to disk;
        # conflating "has a diff" with "has captured evidence" undercounts coverage
        # for single-sided findings).
        has_definition = f.get("master_def") is not None or f.get("client_def") is not None
        has_columns = bool(f.get("master_columns")) or bool(f.get("client_columns"))
        priority_score, priority_breakdown = _priority_score(f)

        index_findings.append({
            "id": finding_id, "name": f["name"], "bare_name": bare, "type": f["type"],
            "action": f["action"], "role": f["role"], "category": f["category"],
            "change_kind": f.get("change_kind"), "summary": f.get("summary", ""),
            "path": rel_path, "review": "pending",
            "attribution": f.get("attribution", []),
            "callers": f.get("callers", {"count": 0, "names": [], "unresolved": 0}),
            "has_definition": has_definition, "has_columns": has_columns,
            # D6: computed once here (not client-side) so index.json carries
            # it and metrics.py can reason about the distribution.
            "priority": _priority_bucket(priority_score),
            "priority_score": priority_score,
            "priority_breakdown": priority_breakdown,
            # Lightweight flags (not the full column list) so the UI can compute a
            # priority signal (a removed/retyped column outranks a pure addition)
            # without fetching the full column detail for every row up front.
            "columns_flags": ({"added": bool(f["columns"].get("added")),
                                "removed": bool(f["columns"].get("removed")),
                                "retyped": bool(f["columns"].get("retyped"))}
                               if f.get("columns") else None),
            # D7: compact only -- ok/reason/counts, never statement text
            # (that's in the .statements.json file above, fetched on demand).
            "statement_map": f.get("statement_map"),
            # PLAN-V4 B.2a: compact scope verdict -- fingerprints + counts only,
            # never block text, so disk-reloaded runs keep the irrelevant flag
            # and classify_all's R1 fires without the in-memory cache.
            "scope": ({"irrelevant_to_client": (f.get("scope") or {}).get("irrelevant_to_client"),
                       "client_id": (f.get("scope") or {}).get("client_id")}
                      if f.get("scope") else None),
        })

    formatting_count = sum(1 for f in findings if f["category"] == "formatting_only")
    # D1: no_difference findings always have role="modified" (change_kind is
    # only ever set for objects where BOTH master_def/client_def -- or both
    # column sets -- exist, which by construction means "modified", never a
    # single-sided added/only_on_other) -- subtracted from "modified" the
    # same way formatting_count already is, so it's excluded from the
    # headline drift count while staying fully visible in its own bucket.
    no_difference_count = sum(1 for f in findings if f["category"] == "no_difference")
    index = {
        "workspace": workspace_label,
        "counts": {
            "added": counts_by_role.get("added", 0),
            "modified": counts_by_role.get("modified", 0) - formatting_count - no_difference_count,
            "only_on_other": counts_by_role.get("only_on_other", 0),
            "formatting_only": formatting_count,
            "no_difference": no_difference_count,
            "documentation": len(documentation_list),
            "cascading": len(cascading_list),
            "excluded": excluded_count,
            "filtered_out": filtered_out_count,
        },
        "by_type": counts_by_type,
        "findings": index_findings,
        "documentation_list": documentation_list,
        "cascading_list": cascading_list,
        "attribution": attribution,
        "lost_fixes": lost_fixes,
        "type_filter": sorted(type_filter) if type_filter else None,
    }

    (workspace_dir / "index.json").write_text(json.dumps(index, indent=1), encoding="utf-8")
    _write_summary_md(workspace_dir, index)
    log(f"  wrote {workspace_label}: {len(index_findings)} detailed finding(s), "
        f"{len(documentation_list)} doc-only, {len(cascading_list)} cascading (summarized)")
    return index


def _render_finding_md(f: dict) -> str:
    lines = [
        f"# {f['name']}", "",
        f"**Type:** {f['type']}  ", f"**Action:** {f['action']}  ",
        f"**Role:** {f['role']}  ", f"**Category:** {f['category']}  ",
    ]
    if f.get("change_kind"):
        lines.append(f"**Change kind:** {f['change_kind']}  ")
    lines += ["", f"{f.get('summary', '')}", ""]
    callers = f.get("callers")
    if callers:
        if callers["count"]:
            lines.append(f"## Blast radius: {callers['count']} caller(s)")
            lines.append(", ".join(f"`{c}`" for c in callers["names"]))
            if callers["unresolved"]:
                lines.append(f"\n({callers['unresolved']} additional reference(s) SQL Server itself "
                              f"couldn't fully resolve -- ambiguous or cross-database)")
            lines.append("")
        else:
            lines.append("## Blast radius: no callers found "
                          "(sys.sql_expression_dependencies -- doesn't see dynamic SQL)")
            lines.append("")
    if f.get("attribution"):
        lines.append("## Attribution (ProcedureChangeLog)")
        for a in f["attribution"]:
            lines.append(f"- [{a['side']}] {a['event']} by `{a['login']}` from `{a['host']}` at {a['when']}")
        lines.append("")
    if f.get("columns"):
        c = f["columns"]
        if c.get("added"):
            lines.append(f"**Columns added on client:** {', '.join(c['added'])}")
        if c.get("removed"):
            lines.append(f"**Columns missing from client:** {', '.join(c['removed'])}")
        if c.get("retyped"):
            lines.append(f"**Columns changed type/nullability:** {', '.join(r['name'] for r in c['retyped'])}")
    return "\n".join(lines)


def _write_summary_md(workspace_dir: Path, index: dict):
    c = index["counts"]
    lines = [
        f"# {index['workspace']} -- summary", "",
    ]
    if index.get("type_filter"):
        lines += [
            f"⚠ **PARTIAL RUN -- type filter active: {', '.join(index['type_filter'])} only.** "
            f"{c['filtered_out']} object(s) not examined because of this filter. "
            f"Do not read this as a clean full comparison.", "",
        ]
    lines += [
        f"- Added: {c['added']}", f"- Modified: {c['modified']}",
        f"- Only on the other side (informational): {c['only_on_other']}", "",
        f"Not counted above (shown separately, not drift): {c['formatting_only']} formatting-only, "
        f"{c['no_difference']} no-difference (flagged changed by SqlPackage, but every side effect "
        f"this tool can capture is identical), {c['documentation']} documentation-only, "
        f"{c['cascading']} cascading refresh, {c['excluded']} known client-named object(s) excluded.", "",
    ]
    if index.get("lost_fixes"):
        lines.append(f"⚠ {len(index['lost_fixes'])} possible lost fix(es) -- see index.json.")
    (workspace_dir / "summary.md").write_text("\n".join(lines), encoding="utf-8")


def write_meta(run_dir: Path, meta: dict):
    (run_dir / "meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
