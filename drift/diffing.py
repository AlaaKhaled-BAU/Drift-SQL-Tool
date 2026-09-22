"""Pure diff + classification logic. No AI, no network, no DB -- takes two
definition strings, returns what changed and how. Fully unit-testable.
"""
import difflib
import re

_COMMENT_LINE = re.compile(r"--[^\n]*")
_COMMENT_BLOCK = re.compile(r"/\*.*?\*/", re.DOTALL)
_WS = re.compile(r"\s+")

# Body starts after the parameter list. Common T-SQL style has a standalone
# "AS" line right before BEGIN; that's the reliable split point. Falls back to
# the first word-boundary AS if no standalone line exists.
_STANDALONE_AS = re.compile(r"(?im)^[ \t]*AS[ \t]*\r?$")
_FIRST_AS = re.compile(r"(?i)\bAS\b")


def code_spans(text: str) -> list[tuple[int, int]]:
    """(start, end) offsets of every span of `text` that is NOT inside a
    '...' string literal or a [...] bracketed identifier (both support
    doubled-char escaping: '' inside a string, ]] inside a bracket).
    normalize_sql()/split_param_body() only ever strip comments, collapse
    whitespace, casefold, or search for the AS split point within these
    spans -- never inside a literal/identifier, so a default value like
    N'Status AS Of -- pending' can't corrupt normalization or be mistaken
    for the real parameter/body boundary (closes the exact gap named in the
    prior version of this file's own "ponytail" comment). Public (no leading
    underscore) because scriptgen.py also reuses it to locate the real
    CREATE keyword past a leading comment (D2a) -- same literal/comment-
    aware scanning problem, not worth a second implementation."""
    spans = []
    i, n = 0, len(text)
    start = 0
    while i < n:
        ch = text[i]
        if ch in ("'", "["):
            if i > start:
                spans.append((start, i))
            close = "'" if ch == "'" else "]"
            i += 1
            while i < n:
                if text[i] == close:
                    if i + 1 < n and text[i + 1] == close:  # doubled = escaped, not a close
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            start = i
        else:
            i += 1
    if start < n:
        spans.append((start, n))
    return spans


def mask_comments(chunk: str) -> str:
    """Blank out comment text with equal-length spaces so AS-search match
    offsets stay valid against the original chunk -- used only to decide
    WHERE the split point is, never to produce returned text."""
    chunk = _COMMENT_BLOCK.sub(lambda m: " " * len(m.group()), chunk)
    chunk = _COMMENT_LINE.sub(lambda m: " " * len(m.group()), chunk)
    return chunk


def normalize_sql(text: str) -> str:
    if not text:
        return ""
    out = []
    last = 0
    for start, end in code_spans(text):
        if start > last:
            out.append(text[last:start])  # literal/bracketed span -- byte-exact, untouched
        chunk = text[start:end]
        chunk = _COMMENT_BLOCK.sub(" ", chunk)
        chunk = _COMMENT_LINE.sub(" ", chunk)
        chunk = _WS.sub(" ", chunk)
        out.append(chunk.casefold())
        last = end
    if last < len(text):
        out.append(text[last:])
    return "".join(out).strip()


def split_param_body(definition: str) -> tuple[str, str]:
    """Best-effort split of a CREATE PROC/FUNC/TRIGGER into (param_block, body).
    Searches only outside string literals/bracketed identifiers and with
    comments masked out, so neither a literal nor a comment containing the
    word AS can be mistaken for the real split point."""
    for pattern in (_STANDALONE_AS, _FIRST_AS):
        for start, end in code_spans(definition):
            masked = mask_comments(definition[start:end])
            m = pattern.search(masked)
            if m:
                return definition[: start + m.start()], definition[start + m.end() :]
    return definition, ""


def settings_diff(master_settings: dict | None, client_settings: dict | None) -> str | None:
    """master_settings/client_settings: {"ansi_nulls": bool, "quoted_identifier": bool}
    per module, or None if not captured. Returns a human note if either
    setting differs, else None. A settings-only difference changes runtime
    semantics even when the visible SQL text is byte-identical, so the
    caller must never let it collapse into formatting_only/none."""
    if not master_settings or not client_settings:
        return None
    diffs = []
    for key, label in (("ansi_nulls", "ANSI_NULLS"), ("quoted_identifier", "QUOTED_IDENTIFIER")):
        m, c = master_settings.get(key), client_settings.get(key)
        if m is not None and c is not None and m != c:
            diffs.append(f"{label}: master={'ON' if m else 'OFF'} client={'ON' if c else 'OFF'}")
    return "; ".join(diffs) if diffs else None


def diff_programmable(master_def: str, client_def: str, split_params: bool = True) -> dict:
    """Compare two object definitions. split_params=True (the default --
    procs/views/functions/triggers) sub-classifies into param/body/both via
    the AS split. split_params=False is for flat DDL with no param/body
    shape at all -- indexes/FKs/constraints/sequences/synonyms/table-types/
    UDTs (qwen-review L-3's extended capture) -- where guessing a param/body
    split off a false "AS" would just be misleading; these report a single
    'structural' change_kind instead."""
    master_def = master_def or ""
    client_def = client_def or ""

    if normalize_sql(master_def) == normalize_sql(client_def):
        change_kind = "formatting_only" if master_def != client_def else "none"
    elif not split_params:
        change_kind = "structural"
    else:
        m_param, m_body = split_param_body(master_def)
        c_param, c_body = split_param_body(client_def)
        param_changed = normalize_sql(m_param) != normalize_sql(c_param)
        body_changed = normalize_sql(m_body) != normalize_sql(c_body)
        if param_changed and body_changed:
            change_kind = "both"
        elif param_changed:
            change_kind = "param"
        elif body_changed:
            change_kind = "body"
        else:
            # normalized-different overall but neither half changed alone --
            # can happen if the AS split point itself shifted. Call it body.
            change_kind = "body"

    diff_lines = list(difflib.unified_diff(
        master_def.splitlines(), client_def.splitlines(),
        fromfile="master_105", tofile="client", lineterm="",
    ))

    return {
        "change_kind": change_kind,
        "diff": diff_lines,
        "summary": _summary_for(change_kind),
    }


def _summary_for(change_kind: str) -> str:
    return {
        "none": "No difference.",
        "formatting_only": "Formatting only (whitespace/comments) -- no behavior change.",
        "param": "Parameters changed (signature differs); body is the same.",
        "body": "Body changed (logic differs); parameters are the same.",
        "both": "Both parameters and body changed.",
        "structural": "Definition changed.",
    }.get(change_kind, "Changed.")


_SIZED_TYPES = {"varchar", "nvarchar", "char", "nchar", "varbinary", "binary"}
_PRECISION_TYPES = {"decimal", "numeric"}

# ponytail: convert.py has its own near-identical _column_ddl/_SIZED_TYPES/
# _PRECISION_TYPES over a differently-shaped column dict (type_name/is_nullable
# vs this module's type/nullable) -- not unified here to avoid touching
# convert.py's already-validated, working .sql export under time pressure.
# Real DRY debt; upgrade path: normalize both call sites on inspect_objects'
# column shape, then delete convert.py's copy.


def rendered_type(col: dict) -> str:
    """Type name WITH width/precision, e.g. nvarchar(50), decimal(18,4).
    A bare type-name compare would miss nvarchar(50)->nvarchar(4000) entirely."""
    t = col["type"]
    if t in _SIZED_TYPES:
        length = "max" if col["max_length"] == -1 else (
            col["max_length"] // 2 if t in ("nvarchar", "nchar") else col["max_length"]
        )
        return f"{t}({length})"
    if t in _PRECISION_TYPES:
        return f"{t}({col['precision']},{col['scale']})"
    return t


def column_ddl(col: dict) -> str:
    nullability = "NULL" if col["nullable"] else "NOT NULL"
    return f"[{col['name']}] {rendered_type(col)} {nullability}"


def diff_columns(master_cols: list[dict], client_cols: list[dict]) -> dict:
    """Compare two column lists (each: {name, type, max_length, precision,
    scale, nullable, is_pk}). Returns added/removed/retyped -- the set
    difflib can't give us for tables. Compares the FULL rendered type
    (width/precision included), not just the bare type name."""
    m_by_name = {c["name"]: c for c in master_cols}
    c_by_name = {c["name"]: c for c in client_cols}

    added = sorted(set(c_by_name) - set(m_by_name))       # client has, master doesn't
    removed = sorted(set(m_by_name) - set(c_by_name))      # master has, client doesn't
    retyped = []
    for name in sorted(set(m_by_name) & set(c_by_name)):
        m, c = m_by_name[name], c_by_name[name]
        if (rendered_type(m), m["nullable"], m["is_pk"]) != (rendered_type(c), c["nullable"], c["is_pk"]):
            retyped.append({"name": name, "master": m, "client": c})

    if not added and not removed and not retyped:
        change_kind = "none"
    elif retyped and (added or removed):
        change_kind = "both"
    elif retyped:
        change_kind = "column"
    else:
        change_kind = "column"

    parts = []
    if added:
        parts.append(f"{len(added)} column(s) added on client")
    if removed:
        parts.append(f"{len(removed)} column(s) missing from client")
    if retyped:
        parts.append(f"{len(retyped)} column(s) changed type/nullability")
    summary = "; ".join(parts) + "." if parts else "No column difference."

    return {
        "change_kind": change_kind,
        "added": added,
        "removed": removed,
        "retyped": retyped,
        "summary": summary,
    }
