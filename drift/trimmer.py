"""Rebuild a procedure body containing only what @ClientActive executes."""
import re

try:
    from . import blocks, diffing, statements
except ImportError:
    import blocks, diffing, statements

_AS_SUFFIX = re.compile(r"\bAS\s*$", re.IGNORECASE)
_MODULE_RE = re.compile(
    r"(?is)\b(?:CREATE(?:\s+OR\s+ALTER)?|ALTER)\s+(PROC|PROCEDURE|FUNCTION|VIEW|TRIGGER)\b"
)
_USE_RE = re.compile(r"(?is)^\s*USE\b")
_SET_BATCH_RE = re.compile(r"(?is)^\s*SET\s+(?:ANSI_NULLS|QUOTED_IDENTIFIER)\b")
_GO_LINE_RE = re.compile(r"(?i)^\s*GO\s*$")
_CLIENT_ACTIVE_RE = re.compile(r"(?i)@ClientActive\b")
_DECLARE_CLIENT_RE = re.compile(r"(?is)\bDECLARE\b[^;]*?@ClientActive\b")
_DECLARE_HEAD = re.compile(r"(?is)^\s*DECLARE\s+(@[A-Za-z_]\w*)\b")
_NAME_USE = re.compile(r"(?i)@[A-Za-z_]\w*")
_PROBE_HEADER = "CREATE PROCEDURE dbo._trim_probe\n    @ClientActive int\nAS\n"


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


def _split_go_batches(definition: str) -> list[tuple[str, int]]:
    """Split on a GO line whose masked text is only GO. Returns (text, 1-based start line).

    Newlines inside a string are blanked in the mask, so line i of the source
    is read from the mask at the same character offsets, not by splitting the mask.
    """
    masked = statements._mask_literals_and_comments(definition)
    lines = definition.split("\n")
    batches: list[tuple[str, int]] = []
    buf: list[str] = []
    start_line = 1
    offset = 0
    for idx, raw in enumerate(lines, start=1):
        mask_line = masked[offset:offset + len(raw)]
        offset += len(raw) + 1
        if _GO_LINE_RE.match(mask_line):
            text = "\n".join(buf)
            if text.strip():
                batches.append((text, start_line))
            buf = []
            start_line = idx + 1
            continue
        if not buf:
            start_line = idx
        buf.append(raw)
    text = "\n".join(buf)
    if text.strip():
        batches.append((text, start_line))
    return batches


def _module_kind(batch: str) -> str | None:
    """Procedure, function, view, or trigger, matched only outside strings and comments."""
    masked = statements._mask_literals_and_comments(batch)
    match = _MODULE_RE.search(masked)
    if not match:
        return None
    word = match.group(1).upper()
    if word in ("PROC", "PROCEDURE"):
        return "procedure"
    return word.lower()


def _masked(text: str) -> str:
    return statements._mask_literals_and_comments(text or "")


def _mentions_client_active(sql: str) -> bool:
    return bool(_CLIENT_ACTIVE_RE.search(_masked(sql)))


def _declares_client_active(sql: str) -> bool:
    return bool(_DECLARE_CLIENT_RE.search(_masked(sql)))


def _has_outer_begin_end(text: str) -> bool:
    stripped = (text or "").strip()
    if not stripped:
        return False
    masked = _masked(stripped)
    if re.match(r"(?is)^BEGIN\s+(?:TRAN|TRANSACTION)\b", masked):
        return False
    if not re.match(r"(?is)^BEGIN\b", masked):
        return False
    return re.search(r"(?is)\bEND\s*$", masked) is not None


def _starts_with_return(text: str) -> bool:
    return bool(re.match(r"(?is)^RETURN\b", _masked((text or "").strip())))


def _shift_scope(scope: dict, batch_line: int) -> None:
    delta = batch_line - 1
    if delta <= 0:
        return
    for pair in scope.get("excluded_ranges") or []:
        pair[0] += delta
        pair[1] += delta
    for block in scope.get("excluded_blocks") or []:
        for key in ("line", "start_line", "end_line"):
            if key in block:
                block[key] += delta


def _meta_from(scope: dict) -> dict:
    stats = scope.get("stats") or {}
    return {
        "mode": scope.get("mode"),
        "client_id": scope.get("client_id"),
        "stats": stats,
        "unknown_kept": int(stats.get("unknown_client") or 0) > 0,
    }


def _reassemble_module(batch: str, scope: dict, kind: str | None) -> str:
    header, body = diffing.split_param_body(batch)
    excluded = scope.get("excluded_blocks") or []
    hoisted = hoist_declares(
        list(scope["relevant_blocks"]),
        [b.get("body") or "" for b in excluded],
    )
    # Nothing was cut from a function, view, or trigger: keep the source text,
    # including RETURNS TABLE AS RETURN and a leading comment.
    if kind != "procedure" and not excluded and not hoisted:
        return batch
    header = (header or "").rstrip()
    if header and not _AS_SUFFIX.search(header):
        header = f"{header}\nAS"
    inner = "\n".join(hoisted + list(scope["relevant_blocks"])).strip()
    if kind in ("procedure", "trigger") or _has_outer_begin_end(body or ""):
        if not _has_outer_begin_end(inner):
            inner = f"BEGIN\n{inner}\nEND"
    elif kind == "function" and _starts_with_return(body or "") and not _starts_with_return(inner):
        inner = f"RETURN\n{inner}" if inner else "RETURN"
    if not header:
        return inner
    return f"{header}\n{inner}"


def _emit_loose(scope: dict) -> str:
    excluded = scope.get("excluded_blocks") or []
    hoisted = hoist_declares(
        list(scope["relevant_blocks"]),
        [b.get("body") or "" for b in excluded],
    )
    inner = "\n".join(hoisted + list(scope["relevant_blocks"])).strip()
    if _mentions_client_active(inner) and not _declares_client_active(inner):
        inner = f"DECLARE @ClientActive int = {scope.get('client_id')};\n{inner}"
    return inner


def _trim_module(batch: str, client_active_id, batch_line: int) -> dict:
    scope = blocks.resolve_scope(batch, client_active_id)
    if not scope.get("ok"):
        reason = scope.get("reason") or "scope failed"
        if "invalid client_active_id" in reason:
            return {"invalid": True, "reason": reason}
        return {"sql": batch, "reason": reason}
    _shift_scope(scope, batch_line)
    return {
        "sql": _reassemble_module(batch, scope, _module_kind(batch)),
        "harvest": scope.get("excluded_blocks") or [],
        "ranges": scope.get("excluded_ranges") or [],
        "meta": _meta_from(scope),
    }


def _trim_loose(batch: str, client_active_id) -> dict:
    scope = blocks.resolve_scope(_PROBE_HEADER + batch, client_active_id)
    if not scope.get("ok"):
        reason = scope.get("reason") or "scope failed"
        if "invalid client_active_id" in reason:
            if _mentions_client_active(batch):
                return {"invalid": True, "reason": reason}
            return {"sql": batch}
        return {"sql": batch, "reason": reason}
    return {"sql": _emit_loose(scope), "meta": _meta_from(scope)}


def _trim_batch(batch: str, client_active_id, batch_line: int) -> dict:
    if _module_kind(batch):
        return _trim_module(batch, client_active_id, batch_line)
    masked = _masked(batch)
    if _USE_RE.match(masked) or _SET_BATCH_RE.match(masked):
        return {"sql": batch}
    return _trim_loose(batch, client_active_id)


def trim_procedure(definition: str, client_active_id) -> dict:
    if not (definition or "").strip():
        return {"ok": False, "reason": "empty definition", "trimmed_sql": None, "harvest": [], "excluded_ranges": []}
    definition = (definition or "").replace("\r\n", "\n").replace("\r", "\n")
    batches = _split_go_batches(definition)
    if not batches:
        return {
            "ok": True,
            "trimmed_sql": definition,
            "harvest": [],
            "excluded_ranges": [],
        }
    parts: list[str] = []
    harvest: list = []
    ranges: list = []
    reason = None
    meta = None
    for text, line in batches:
        outcome = _trim_batch(text, client_active_id, line)
        if outcome.get("invalid"):
            return {
                "ok": False,
                "reason": outcome.get("reason") or "scope failed",
                "trimmed_sql": None,
                "harvest": [],
                "excluded_ranges": [],
            }
        parts.append(outcome.get("sql") or "")
        harvest.extend(outcome.get("harvest") or [])
        ranges.extend(outcome.get("ranges") or [])
        if outcome.get("reason"):
            reason = reason or outcome["reason"]
        if outcome.get("meta"):
            meta = outcome["meta"]
    result = {
        "ok": True,
        "trimmed_sql": "\nGO\n".join(parts),
        "harvest": harvest,
        "excluded_ranges": ranges,
    }
    if reason:
        result["reason"] = reason
    if meta:
        result.update(meta)
    return result


def handle_trim(body: dict) -> tuple[dict, int]:
    definition = (body or {}).get("definition") or ""
    cid = (body or {}).get("client_active_id")
    result = trim_procedure(definition, cid)
    return result, (200 if result.get("ok") else 400)
