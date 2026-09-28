"""Rebuild a procedure body containing only what @ClientActive executes."""
import re

try:
    from . import blocks, diffing
except ImportError:
    import blocks, diffing

_AS_SUFFIX = re.compile(r"\bAS\s*$", re.IGNORECASE)
_PROC_START = re.compile(r"(?is)\b(?:ALTER|CREATE)\s+(?:PROC|PROCEDURE|FUNCTION|VIEW|TRIGGER)\b")


def trim_procedure(definition: str, client_active_id) -> dict:
    if not (definition or "").strip():
        return {"ok": False, "reason": "empty definition", "trimmed_sql": None, "harvest": [], "excluded_ranges": []}
    definition = (definition or "").replace("\r\n", "\n")
    # SSMS "Script as" dumps start with USE/GO/SET. Those are not the procedure,
    # and leaving them in made a trimmed body look like the original script.
    start = _PROC_START.search(definition)
    preamble_lines = 0
    if start:
        preamble = definition[:start.start()]
        preamble_lines = preamble.count("\n")
        proc_def = definition[start.start():]
    else:
        proc_def = definition
    scope = blocks.resolve_scope(proc_def, client_active_id)
    harvest = scope.get("excluded_blocks") or []
    excluded_ranges = scope.get("excluded_ranges") or []

    if preamble_lines > 0:
        excluded_ranges = [[r[0] + preamble_lines, r[1] + preamble_lines] for r in excluded_ranges]
        for b in harvest:
            if "line" in b:
                b["line"] += preamble_lines
            if "start_line" in b:
                b["start_line"] += preamble_lines
            if "end_line" in b:
                b["end_line"] += preamble_lines

    if not scope.get("ok"):
        return {
            "ok": False,
            "reason": scope.get("reason") or "scope failed",
            "trimmed_sql": None,
            "harvest": harvest,
            "excluded_ranges": excluded_ranges,
        }
    header, _body = diffing.split_param_body(proc_def)
    header = (header or "").rstrip() or "CREATE PROCEDURE [dbo].[Unknown] AS"
    if not _AS_SUFFIX.search(header):
        header = f"{header}\nAS"
    inner = "\n".join(scope["relevant_blocks"]).strip()
    trimmed = f"{header}\nBEGIN\n{inner}\nEND"
    stats = scope.get("stats") or {}
    return {
        "ok": True,
        "mode": scope.get("mode"),
        "client_id": scope.get("client_id"),
        "trimmed_sql": trimmed,
        "harvest": harvest,
        "excluded_ranges": excluded_ranges,
        "unknown_kept": int(stats.get("unknown_client") or 0) > 0,
        "stats": stats,
    }


def handle_trim(body: dict) -> tuple[dict, int]:
    definition = (body or {}).get("definition") or ""
    cid = (body or {}).get("client_active_id")
    result = trim_procedure(definition, cid)
    return result, (200 if result.get("ok") else 400)
