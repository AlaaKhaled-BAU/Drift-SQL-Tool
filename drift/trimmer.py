"""Rebuild a procedure body containing only what @ClientActive executes."""
import re

try:
    from . import blocks, diffing, statements
except ImportError:
    import blocks, diffing, statements

_AS_SUFFIX = re.compile(r"\bAS\s*$", re.IGNORECASE)
_PROC_START = re.compile(r"(?is)\b(?:ALTER|CREATE)\s+(?:PROC|PROCEDURE|FUNCTION|VIEW|TRIGGER)\b")
_DECLARE_HEAD = re.compile(r"(?is)^\s*DECLARE\s+(@[A-Za-z_]\w*)\b")
_NAME_USE = re.compile(r"(?i)@[A-Za-z_]\w*")


def _paren_split_comma(text: str) -> list[str]:
    parts, buf, depth = [], [], 0
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch == "," and depth == 0:
            parts.append("".join(buf))
            buf = []
            continue
        buf.append(ch)
    parts.append("".join(buf))
    return parts


def _hoist_one(stmt: str) -> list[str]:
    """Zero or more DECLARE texts safe to move to procedure scope."""
    masked = statements._mask_literals_and_comments(stmt)
    if re.search(r"(?i)\bCURSOR\b", masked):
        return []
    if re.search(r"(?i)\bCREATE\s+TABLE\b", masked):
        return []
    head = _DECLARE_HEAD.match(stmt)
    if not head:
        return []
    rest = stmt[head.end():]
    rest_masked = statements._mask_literals_and_comments(rest)
    if re.match(r"(?is)\s*TABLE\b", rest_masked):
        return [stmt.strip()]
    def _strip_initializer(item: str) -> str:
        item_masked = statements._mask_literals_and_comments(item)
        depth = 0
        for i, ch in enumerate(item_masked):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth = max(0, depth - 1)
            elif ch == "=" and depth == 0:
                return item[:i].rstrip()
        return item.strip()

    # rest is everything after the first @name: " int, @b int = 5"
    items = _paren_split_comma(rest)
    if not items or not items[0].strip():
        return []
    declares = [f"DECLARE {head.group(1)} {_strip_initializer(items[0])}".strip()]
    for item in items[1:]:
        piece = _strip_initializer(item).strip()
        if piece:
            declares.append(f"DECLARE {piece}")
    return declares


def hoist_declares(relevant: list[str], excluded_bodies: list[str]) -> list[str]:
    kept = "\n".join(relevant)
    kept_masked = statements._mask_literals_and_comments(kept)
    used = {m.group(0).lower() for m in _NAME_USE.finditer(kept_masked)}
    already = set()
    for stmt_text in relevant:
        for seg in statements._segment_statements(stmt_text) or []:
            text = seg[0]
            for decl in _hoist_one(text):
                found = _DECLARE_HEAD.match(decl)
                if found:
                    already.add(found.group(1).lower())
    hoisted = []
    seen = set(already)
    for blob in excluded_bodies:
        for seg in statements._segment_statements(blob) or []:
            text = seg[0]
            for decl in _hoist_one(text):
                name = _DECLARE_HEAD.match(decl).group(1).lower()
                if name in seen or name not in used:
                    continue
                seen.add(name)
                hoisted.append(decl)
    return hoisted


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
    excluded_bodies = [b.get("body") or "" for b in harvest]
    hoisted = hoist_declares(list(scope["relevant_blocks"]), excluded_bodies)
    inner = "\n".join(hoisted + list(scope["relevant_blocks"])).strip()
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
