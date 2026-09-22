"""Rich, GitHub-style diff rendering for the UI: proper line-pairing (not just
a sequential +/- stream like a unified diff) plus word-level intraline
highlighting for changed line pairs, and long unchanged runs collapsed with
a "N lines unchanged" marker instead of dumped in full.

Pure presentation over the SAME master_def/client_def diffing.py already
classifies -- this module never recomputes change_kind and is never called
from the detection path (compare.py/pipeline.py). It exists only so a human
looking at a finding sees what changed the way GitHub would show it, instead
of a hand-rolled +/- <pre> block.
"""
import difflib
import re

_WORD_RE = re.compile(r"\S+|\s+")


def render_rich_diff(master_def: str, client_def: str, context: int = 3) -> dict:
    """Returns {"hunks": [...]}.

    Each hunk is either:
      {"collapsed": True, "count": N}                     -- N unchanged lines, not rendered
      {"collapsed": False, "lines": [...]}                 -- rendered line-ops

    Each line-op is one of:
      {"tag": "equal"|"delete"|"insert", "text": str}
      {"tag": "replace", "master_words": [...], "client_words": [...]}  -- word-level pair

    Word entries are {"text": str, "changed": bool}.
    """
    master_lines = (master_def or "").splitlines()
    client_lines = (client_def or "").splitlines()
    sm = difflib.SequenceMatcher(a=master_lines, b=client_lines, autojunk=False)

    ops = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            ops.extend({"tag": "equal", "text": line} for line in master_lines[i1:i2])
        elif tag == "delete":
            ops.extend({"tag": "delete", "text": line} for line in master_lines[i1:i2])
        elif tag == "insert":
            ops.extend({"tag": "insert", "text": line} for line in client_lines[j1:j2])
        elif tag == "replace":
            m_block, c_block = master_lines[i1:i2], client_lines[j1:j2]
            # Same-index lines within a replace block are treated as "this line
            # changed" (git/GitHub convention) and get word-level highlighting;
            # any leftover unpaired lines (block lengths differ) are plain
            # delete/insert -- there's no sensible line to pair them against.
            paired = min(len(m_block), len(c_block))
            for k in range(paired):
                master_words, client_words = _word_pair(m_block[k], c_block[k])
                ops.append({"tag": "replace", "master_words": master_words, "client_words": client_words})
            ops.extend({"tag": "delete", "text": line} for line in m_block[paired:])
            ops.extend({"tag": "insert", "text": line} for line in c_block[paired:])

    return {"hunks": _group_into_hunks(ops, context)}


def _word_pair(master_line: str, client_line: str) -> tuple[list, list]:
    """Word/whitespace-token level diff of two lines that are known to differ.
    Returns (master_words, client_words), each a list of {"text", "changed"}."""
    m_tokens = _WORD_RE.findall(master_line)
    c_tokens = _WORD_RE.findall(client_line)
    sm = difflib.SequenceMatcher(a=m_tokens, b=c_tokens, autojunk=False)

    master_words, client_words = [], []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for t in m_tokens[i1:i2]:
                master_words.append({"text": t, "changed": False})
                client_words.append({"text": t, "changed": False})
        else:
            master_words.extend({"text": t, "changed": True} for t in m_tokens[i1:i2])
            client_words.extend({"text": t, "changed": True} for t in c_tokens[j1:j2])
    return master_words, client_words


def _group_into_hunks(ops: list, context: int) -> list:
    """Collapse long equal-only stretches; keep `context` lines of equal
    padding around each change, same convention as unified diffs/git."""
    n = len(ops)
    interesting = [i for i, o in enumerate(ops) if o["tag"] != "equal"]
    if not interesting:
        return [{"collapsed": False, "lines": ops}] if ops else []

    windows = []
    start, end = max(0, interesting[0] - context), min(n, interesting[0] + context + 1)
    for idx in interesting[1:]:
        w_start = max(0, idx - context)
        if w_start <= end:
            end = min(n, idx + context + 1)
        else:
            windows.append((start, end))
            start, end = w_start, min(n, idx + context + 1)
    windows.append((start, end))

    hunks, prev_end = [], 0
    for w_start, w_end in windows:
        if w_start > prev_end:
            hunks.append({"collapsed": True, "count": w_start - prev_end})
        hunks.append({"collapsed": False, "lines": ops[w_start:w_end]})
        prev_end = w_end
    if prev_end < n:
        hunks.append({"collapsed": True, "count": n - prev_end})
    return hunks


def render_split_diff(master_def: str, client_def: str, context: int = 3) -> dict:
    """Returns {"hunks": [...]}, same collapsed-run shape as render_rich_diff
    (a hunk is {"collapsed": True, "count": N} or {"collapsed": False,
    "lines": [...]} -- _group_into_hunks is reused verbatim, so the key is
    still called "lines" even though each entry is now a row pair, not a
    single-sided op). Each entry is
    {"tag": "equal"|"delete"|"insert"|"replace", "left": {...}|None, "right": {...}|None}
    -- None on whichever side has no counterpart for that row (a pure
    add/delete has nothing to pair against). "left"/"right" are either
    {"text": str} (equal/delete/insert) or {"words": [...]} (replace,
    word-level highlighted via the same _word_pair as the unified view).

    Identical SequenceMatcher opcode walk as render_rich_diff -- this is a
    presentation-shape difference only, never a second detection path."""
    master_lines = (master_def or "").splitlines()
    client_lines = (client_def or "").splitlines()
    sm = difflib.SequenceMatcher(a=master_lines, b=client_lines, autojunk=False)

    rows = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            rows.extend({"tag": "equal", "left": {"text": line}, "right": {"text": line}}
                        for line in master_lines[i1:i2])
        elif tag == "delete":
            rows.extend({"tag": "delete", "left": {"text": line}, "right": None} for line in master_lines[i1:i2])
        elif tag == "insert":
            rows.extend({"tag": "insert", "left": None, "right": {"text": line}} for line in client_lines[j1:j2])
        elif tag == "replace":
            m_block, c_block = master_lines[i1:i2], client_lines[j1:j2]
            paired = min(len(m_block), len(c_block))
            for k in range(paired):
                master_words, client_words = _word_pair(m_block[k], c_block[k])
                rows.append({"tag": "replace", "left": {"words": master_words}, "right": {"words": client_words}})
            rows.extend({"tag": "delete", "left": {"text": line}, "right": None} for line in m_block[paired:])
            rows.extend({"tag": "insert", "left": None, "right": {"text": line}} for line in c_block[paired:])

    return {"hunks": _group_into_hunks(rows, context)}


def render_column_grid(master_columns: list, client_columns: list) -> dict:
    """Structured before/after column grid for SqlTable findings -- there's no
    text to diff, so this is a dedicated renderer over already-captured
    columns.json, not a text-diff variant. Reuses diffing.diff_columns's
    already-validated added/removed/retyped classification, just reshapes it
    for a grid: one row per column, tagged same/added/removed/retyped."""
    try:
        from . import diffing
    except ImportError:  # allows standalone script execution
        import diffing

    d = diffing.diff_columns(master_columns, client_columns)
    m_by_name = {c["name"]: c for c in master_columns}
    c_by_name = {c["name"]: c for c in client_columns}
    retyped_by_name = {r["name"]: r for r in d["retyped"]}

    rows = []
    for name in sorted(set(m_by_name) | set(c_by_name)):
        if name in d["added"]:
            rows.append({"name": name, "status": "added", "client": diffing.column_ddl(c_by_name[name])})
        elif name in d["removed"]:
            rows.append({"name": name, "status": "removed", "master": diffing.column_ddl(m_by_name[name])})
        elif name in retyped_by_name:
            r = retyped_by_name[name]
            rows.append({
                "name": name, "status": "retyped",
                "master": diffing.column_ddl(r["master"]), "client": diffing.column_ddl(r["client"]),
            })
        else:
            rows.append({"name": name, "status": "same", "client": diffing.column_ddl(c_by_name[name])})
    return {"rows": rows, "summary": d["summary"]}
