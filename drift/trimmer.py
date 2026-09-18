"""Rebuild a procedure body containing only what @ClientActive executes."""
import re

try:
    from . import blocks, diffing
except ImportError:
    import blocks, diffing

_AS_SUFFIX = re.compile(r"\bAS\s*$", re.IGNORECASE)


def trim_procedure(definition: str, client_active_id) -> dict:
    if not (definition or "").strip():
        return {"ok": False, "reason": "empty definition", "trimmed_sql": None, "harvest": []}
    scope = blocks.resolve_scope(definition, client_active_id)
    if not scope.get("ok"):
        return {
            "ok": False,
            "reason": scope.get("reason") or "scope failed",
            "trimmed_sql": None,
            "harvest": scope.get("excluded_blocks") or [],
        }
    header, _body = diffing.split_param_body(definition)
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
        "harvest": scope.get("excluded_blocks") or [],
        "unknown_kept": int(stats.get("unknown") or 0) > 0,
        "stats": stats,
    }


def handle_trim(body: dict) -> tuple[dict, int]:
    definition = (body or {}).get("definition") or ""
    cid = (body or {}).get("client_active_id")
    result = trim_procedure(definition, cid)
    return result, (200 if result.get("ok") else 400)
