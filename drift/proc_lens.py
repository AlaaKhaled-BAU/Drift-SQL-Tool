"""Compare two captured procedure definitions under drift lenses (in-memory only)."""
import difflib

try:
    from . import diffing
    from .scriptgen import _as_create_or_alter
    from .trimmer import trim_procedure
except ImportError:
    import diffing
    from scriptgen import _as_create_or_alter
    from trimmer import trim_procedure

_VALID_LENS = frozenset({"full", "active_read", "active_plus_else"})


def compare_procs(
    left_def: str,
    right_def: str,
    client_active_id,
    lens: str,
    *,
    client_settings: dict | None = None,
) -> dict:
    """left_def = master (105) capture; right_def = client capture.

    Preview/diff honor ``lens``. Copy SQL is always CREATE OR ALTER of the
    original client definition (never DDL aimed at database 105).
    """
    if lens not in _VALID_LENS:
        return {
            "ok": False,
            "reason": f"lens must be one of {sorted(_VALID_LENS)}, got {lens!r}",
            "identical": False,
            "preview_left": "",
            "preview_right": "",
            "diff_unified": "",
            "copy_sql": "",
            "copy_kind": "none",
        }

    left_def = left_def or ""
    right_def = right_def or ""

    warning = None
    left_harvest: list = []
    right_harvest: list = []

    if lens == "full":
        preview_left = left_def
        preview_right = right_def
    else:
        tl = trim_procedure(left_def, client_active_id)
        tr = trim_procedure(right_def, client_active_id)
        if not tl.get("ok") or not tr.get("ok"):
            reason = tl.get("reason") or tr.get("reason") or "trim failed"
            return {
                "ok": False,
                "reason": reason,
                "lens": lens,
                "identical": False,
                "preview_left": "",
                "preview_right": "",
                "diff_unified": "",
                "copy_sql": "",
                "copy_kind": "none",
                "warning": reason,
            }
        left_harvest = tl.get("harvest") or []
        right_harvest = tr.get("harvest") or []
        preview_left = tl["trimmed_sql"]
        preview_right = tr["trimmed_sql"]
        if lens == "active_plus_else":
            preview_left = _with_harvest_section(preview_left, left_harvest)
            preview_right = _with_harvest_section(preview_right, right_harvest)

    identical = diffing.normalize_sql(preview_left) == diffing.normalize_sql(preview_right)

    diff_unified = "\n".join(
        difflib.unified_diff(
            preview_left.splitlines(),
            preview_right.splitlines(),
            fromfile="left",
            tofile="right",
            lineterm="",
        )
    )

    copy_sql = ""
    copy_kind = "none"
    if not identical and (right_def or "").strip():
        copy_sql = _as_create_or_alter(right_def, client_settings)
        if lens == "active_plus_else":
            harvest_block = _harvest_comment_block(left_harvest)
            if harvest_block:
                copy_sql = copy_sql.rstrip() + "\n\n" + harvest_block
        copy_kind = "create_or_alter"

    return {
        "ok": True,
        "lens": lens,
        "identical": identical,
        "preview_left": preview_left,
        "preview_right": preview_right,
        "diff_unified": diff_unified,
        "copy_sql": copy_sql,
        "copy_kind": copy_kind,
        "warning": warning,
    }


def _with_harvest_section(trimmed_sql: str, harvest: list) -> str:
    block = _harvest_comment_block(harvest)
    if not block:
        return trimmed_sql
    return trimmed_sql.rstrip() + "\n\n" + block + "\n"


def _harvest_comment_block(harvest: list) -> str:
    lines: list[str] = []
    for item in harvest or []:
        if item.get("kind") != "else":
            continue
        body = (item.get("body") or "").strip()
        if not body:
            continue
        lines.append("-- HARVEST ELSE (not executed for this @ClientActive)")
        cond = item.get("condition") or "(else)"
        lines.append(f"-- condition: {cond}")
        for line in body.splitlines():
            lines.append(f"-- {line}")
        lines.append("")
    return "\n".join(lines).rstrip()
