"""D7: statement-level change map -- the salvaged idea from the original
request (split a procedure into an array of statements and compare them).
Pure, no DB, no network, fully unit-testable, mirroring diffing.py's style.

Measured (§2 of PLAN-04): feeding a whole multi-statement procedure body to
sqlglot.parse() is fragile beyond the already-documented 64.5% structured /
28.5% opaque-Command / 7% exception split. Live experiments while building
this file found that even ORDINARY, common T-SQL style -- an IF/ELSE where
neither branch's closing END is followed by a semicolon, which is normal
style, not an edge case -- makes sqlglot's own top-level splitter raise
outright, worse than the measured 7%. It ALSO found a fourth failure mode
the 64.5/28.5/7 split doesn't cover: sqlglot can silently mis-parse an
unfamiliar bare statement (`THROW;`, an unbraced single-statement `IF`)
into a plausible-looking but WRONG expression-level node (`Column`,
`Alias`) instead of raising or falling back to `Command` -- worse than an
honest failure, since nothing about it looks like one.

Given both findings, trusting sqlglot to split a multi-statement body AND
classify it in one pass would make `ok` fire far more often than the
content actually warrants, on exactly the control-flow-heavy bodies (the
`@ClientActive` branching case) this feature is supposed to help most.
So statement BOUNDARIES here are found by this module's OWN literal/
comment-safe keyword-and-depth scan (reusing diffing.code_spans) -- a much
narrower, more robust problem than full T-SQL grammar. sqlglot is used
only for its strongest case: classifying/extracting the condition of ONE
already-isolated IF/WHILE segment, with a plain-text fallback when even
that fails. `ok` reflects whether THIS module's own segmentation produced
a trustworthy result (multiple real segments recognized, not a CURSOR
declaration, not everything falling into "OTHER"), not whether sqlglot's
raw parser happened to accept the whole body.
"""
import difflib
import logging
import re

import sqlglot
from sqlglot import exp

from . import diffing

# _classify()'s per-segment sqlglot attempt is already a deliberate best-
# effort with its own try/except fallback -- sqlglot's own "unsupported
# syntax, falling back to Command" warning is expected, already-handled
# noise here, not a signal anyone reading logs needs to see.
logging.getLogger("sqlglot").setLevel(logging.ERROR)

_CURSOR_RE = re.compile(r"\bCURSOR\b", re.IGNORECASE)

_TOP_LEVEL_KEYWORDS = (
    "SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "EXEC", "EXECUTE",
    "IF", "WHILE", "DECLARE", "SET", "PRINT", "RAISERROR", "THROW",
    "WITH", "COMMIT", "ROLLBACK", "TRUNCATE", "RETURN", "GOTO", "WAITFOR",
    "CREATE", "ALTER", "DROP", "BEGIN",
)
_KEYWORD_RE = re.compile(r"\b(" + "|".join(_TOP_LEVEL_KEYWORDS) + r")\b", re.IGNORECASE)
_WORD_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# CASE...END is a scalar SQL expression (CASE WHEN ... THEN ... ELSE ...
# END), completely unrelated to a BEGIN...END block -- but it closes with
# the SAME "END" keyword. Measured live against db/Olives_BO.sql: a proc
# with a CASE expression anywhere in its body (extremely common SQL, e.g.
# a single-line SELECT @x = CASE WHEN...END) threw off the BEGIN/END
# balance entirely, since that END has no BEGIN to match and was being
# counted as if it did. CASE has to share the SAME depth counter as BEGIN
# (an "opener" needing a matching END), not be ignored -- a CASE nested
# inside a real BEGIN block must still return to the BLOCK's depth when
# it closes, not to 0.
_OPEN_RE = re.compile(r"\bBEGIN\b|\bCASE\b", re.IGNORECASE)
_BEGIN_END_RE = re.compile(r"\bBEGIN\b|\bCASE\b|\bEND\b", re.IGNORECASE)
_TRAN_WORDS = {"tran", "transaction"}

_KIND_BY_KEYWORD = {
    "SELECT": "SELECT", "WITH": "SELECT",  # WITH = CTE prefix, always feeds a SELECT
    "INSERT": "INSERT", "MERGE": "INSERT",
    "UPDATE": "UPDATE", "DELETE": "DELETE",
    "EXEC": "EXEC", "EXECUTE": "EXEC",
    "IF": "IF", "WHILE": "WHILE",
    "DECLARE": "DECLARE", "SET": "SET",
}


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _is_begin_tran(masked: str, begin_end: int) -> bool:
    """True when a BEGIN match (ending at `begin_end` in `masked`) is
    `BEGIN TRAN[SACTION]` -- a statement, not a block-opener. Shared by
    _strip_outer_begin_end and _segment_statements's event builder; this
    used to be checked twice with the SAME logic hand-copied in each --
    real bug found live (measured against db/Olives_BO.sql): the copy
    inside _strip_outer_begin_end's depth-counting loop was missing,
    so `BEGIN TRANSACTION` anywhere in a proc counted as a real nested
    block, threw off the whole BEGIN/END balance, and made the outer-
    wrapper strip silently refuse to fire -- collapsing the entire body
    into one meaningless segment. One shared function now, not two."""
    after = _WORD_RE.search(masked, begin_end)
    return bool(after and after.group().lower() in _TRAN_WORDS and
                not masked[begin_end:after.start()].strip("; \t\r\n"))


def _mask_literals_and_comments(text: str) -> str:
    """Blank string/bracket spans AND comments with equal-length spaces --
    keyword scanning and depth tracking must never fire on a keyword that
    only appears inside a literal (e.g. a default value N'BEGIN work order')
    or a comment. Offsets stay valid against the original text.

    Same bytes as copying code_spans and space-filling the rest; does not
    allocate a set of every index (that dominated trim time on large procs).
    """
    n = len(text)
    out = [" "] * n
    for start, end in diffing.code_spans(text):
        out[start:end] = text[start:end]
    return diffing.mask_comments("".join(out))


def _strip_outer_begin_end(body: str) -> tuple:
    """(inner_text, offset) -- CREATE PROC ... AS BEGIN ... END is the
    overwhelmingly common real-world shape. Without this, that single
    outer BEGIN/END would read as a real nested block wrapping the ENTIRE
    body, so depth would never return to 0 for any of the real top-level
    statements inside it and everything would collapse into one
    meaningless "BEGIN...END" segment. Only strips when the body's first
    token is a real (non-tran) BEGIN whose matching END is the very last
    token -- i.e. exactly one enclosing pair, confirmed by depth actually
    returning to 0 there and nowhere earlier. `offset` is how many
    characters were removed from the front, so callers can still report
    line numbers against the ORIGINAL body, not the stripped one."""
    masked = _mask_literals_and_comments(body)
    stripped_leading = len(body) - len(body.lstrip())
    first = _WORD_RE.search(masked, stripped_leading)
    if not first or first.group().upper() != "BEGIN":
        return body, 0
    if _is_begin_tran(masked, first.end()):
        return body, 0  # BEGIN TRAN, not a block-opener

    depth = 1  # already inside the opening BEGIN consumed above as `first`
    close_start = close_end = None
    for m in _BEGIN_END_RE.finditer(masked, first.end()):
        word = m.group().upper()
        if word == "CASE" or (word == "BEGIN" and not _is_begin_tran(masked, m.end())):
            depth += 1
        elif word == "END":
            depth -= 1
            if depth == 0:
                close_start, close_end = m.start(), m.end()
                break
    if close_start is None or masked[close_end:].strip():
        return body, 0  # unbalanced, or something follows the closing END -- not a clean single wrapper
    return body[first.end():close_start], first.end()


def _segment_statements(body: str) -> list:
    """[(text, line), ...] -- byte-exact source slices, found by this
    module's own depth-tracked keyword scan, not by asking sqlglot to
    split a multi-statement blob (measured unreliable -- see module
    docstring). A depth-0 occurrence of a top-level keyword starts a new
    segment: by construction, being back at depth 0 means whatever came
    before (a `;`-terminated statement, or a control structure whose
    BEGIN/END just balanced) is already complete -- with two exceptions,
    both one-shot (they suppress exactly the ONE thing right after them,
    not everything until some later point):
      - the body right after `IF <cond>`/`WHILE <cond>` is that statement's
        OWN body, not a new statement, whether it's `BEGIN...END` or a
        single bare statement;
      - the branch right after `ELSE` is the else-branch of the IF already
        in progress, same either-shape deal.
    Either way, if the suppressed body turns out to be `BEGIN...END`, its
    own nesting is still depth-tracked normally (a stray top-level keyword
    inside it is already protected by the plain depth==0 check, no
    suppression needed for that part)."""
    original_body = body
    body, offset = _strip_outer_begin_end(body)
    masked = _mask_literals_and_comments(body)

    events = []
    for m in re.finditer(r"\bBEGIN\b", masked, re.IGNORECASE):
        # "BEGIN TRAN[SACTION]" is a statement, not a block-opener --
        # everything else ("BEGIN", "BEGIN TRY", "BEGIN CATCH") opens one.
        is_tran = _is_begin_tran(masked, m.end())
        events.append((m.start(), "tran" if is_tran else "begin", None))
    for m in re.finditer(r"\bCASE\b", masked, re.IGNORECASE):
        # A CASE...END scalar expression shares the SAME depth counter as
        # BEGIN...END (see _OPEN_RE/_BEGIN_END_RE) -- it closes with the
        # same "END" keyword, but unlike a real BEGIN it is NEVER itself a
        # segment boundary (it's always a sub-expression of the statement
        # already in progress, e.g. `SELECT @x = CASE WHEN ... END`).
        events.append((m.start(), "case_open", None))
    for m in re.finditer(r"\bEND\b", masked, re.IGNORECASE):
        events.append((m.start(), "end", None))
    for m in re.finditer(r"\bELSE\b", masked, re.IGNORECASE):
        events.append((m.start(), "else", None))
    for m in _KEYWORD_RE.finditer(masked):
        word = m.group(1).upper()
        if word != "BEGIN":  # BEGIN already classified as tran/begin above
            events.append((m.start(), "keyword", word))
    events.sort(key=lambda e: e[0])

    depth = 0
    suppress_next = False  # one-shot: consumed by the very next begin/tran/keyword
    open_word = None  # leading keyword of whichever segment is currently open
    bounds = []
    for pos, kind, word in events:
        if kind == "begin":
            if depth == 0:
                if not suppress_next:
                    bounds.append(pos)
                suppress_next = False
            depth += 1
        elif kind == "case_open":
            depth += 1  # never a boundary -- always a sub-expression, see loop above
        elif kind == "end":
            depth = max(0, depth - 1)
        elif kind == "else":
            if depth == 0:
                suppress_next = True
        else:  # "tran" or "keyword"
            if depth == 0:
                # UPDATE T SET A=1 uses "SET" as part of ITS OWN syntax,
                # not as the standalone `SET @x = 1` statement -- a bare
                # SET keyword never starts a new segment while still
                # inside the UPDATE statement that introduced it.
                if word == "SET" and open_word == "UPDATE":
                    continue
                if not suppress_next:
                    bounds.append(pos)
                    open_word = word
                suppress_next = word in ("IF", "WHILE")

    bounds = sorted(set(bounds))
    if not bounds:
        return []
    segments = []
    for i, start in enumerate(bounds):
        end = bounds[i + 1] if i + 1 < len(bounds) else len(body)
        text = body[start:end].rstrip()
        if text.strip():
            # +offset: line numbers are reported against the ORIGINAL body
            # (what a human looking at the real definition sees), not the
            # BEGIN/END-stripped text this function actually sliced.
            segments.append((text, _line_of(original_body, start + offset)))
    return segments


def _classify(text: str) -> tuple:
    """(kind, condition). kind from the first top-level keyword (found the
    same literal/comment-safe way as segmentation); condition (IF/WHILE
    only) via sqlglot on this ALREADY-ISOLATED single statement -- the case
    sqlglot handles best -- falling back to a plain text slice between the
    keyword and the first BEGIN/newline if sqlglot can't parse this
    fragment either."""
    masked = _mask_literals_and_comments(text)
    m = _KEYWORD_RE.search(masked)
    if not m:
        return "OTHER", None
    word = m.group(1).upper()
    kind = _KIND_BY_KEYWORD.get(word, "OTHER")
    if kind not in ("IF", "WHILE"):
        return kind, None

    condition = None
    try:
        node = sqlglot.parse_one(text, read="tsql")
        if isinstance(node, (exp.If, exp.Command)) or type(node).__name__ in ("IfBlock", "WhileBlock"):
            cond_node = node.args.get("this")
            if cond_node is not None and not isinstance(cond_node, exp.Command):
                condition = cond_node.sql(dialect="tsql")
    except Exception:  # noqa: BLE001 - best-effort only, never fatal to the whole finding
        pass
    if condition is None:
        # Fallback: plain text between the keyword and the first BEGIN/
        # newline -- honest, unparsed, but better than nothing for the
        # single highest-value sentence this tool can produce
        # ("a new IF @ClientActive = 165 branch was added").
        rest = text[m.end():]
        stop = re.search(r"\bBEGIN\b|\n", rest, re.IGNORECASE)
        condition = (rest[: stop.start()] if stop else rest).strip() or None
    return kind, condition


def parse_statements(definition: str) -> dict:
    """{"ok": bool, "reason": str|None, "statements": [...]}. ok=False
    whenever structure isn't trustworthy, for any reason -- never guess.

    Deliberately does NOT gate on sqlglot's own top-level parse of the
    whole body (measured to raise outright on ordinary semicolon-optional
    IF/ELSE style -- see module docstring); this module's own segmenter is
    the primary signal, sqlglot is only consulted per-segment below."""
    _, body = diffing.split_param_body(definition)
    body = body or definition
    if not body.strip():
        return {"ok": False, "reason": "empty body after the param/body split", "statements": []}

    if _CURSOR_RE.search(_mask_literals_and_comments(body)):
        return {"ok": False, "reason": "CURSOR-based control flow is not supported "
                                        "(OPEN/FETCH/CLOSE loop structure is not in this "
                                        "module's recognized statement vocabulary)",
                "statements": []}

    segments = _segment_statements(body)
    if not segments:
        return {"ok": False, "reason": "no statement boundaries recognized in this body",
                "statements": []}

    statements = []
    for text, line in segments:
        kind, condition = _classify(text)
        statements.append({
            "kind": kind, "condition": condition, "text": text,
            "norm": diffing.normalize_sql(text), "line": line,
        })

    if all(s["kind"] == "OTHER" for s in statements):
        return {"ok": False, "reason": f"none of the {len(statements)} segment(s) matched a "
                                        f"recognized statement type -- this body likely uses "
                                        f"syntax outside this module's vocabulary",
                "statements": []}
    return {"ok": True, "reason": None, "statements": statements}


def align_statements(master_stmts: list, client_stmts: list) -> list:
    """SequenceMatcher over the `norm` keys -- NOT positional. A single
    inserted statement at the top must show as exactly one `added`, not N
    cascading `changed` entries (the failure mode positional comparison
    would produce, and the reason the user's original "split into an array
    and compare" idea needed this alignment step, not a naive zip())."""
    m_keys = [s["norm"] for s in master_stmts]
    c_keys = [s["norm"] for s in client_stmts]
    sm = difflib.SequenceMatcher(a=m_keys, b=c_keys, autojunk=False)

    out = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                out.append({"tag": "equal", "master": master_stmts[i1 + k], "client": client_stmts[j1 + k]})
        elif tag == "delete":
            out.extend({"tag": "removed", "master": s, "client": None} for s in master_stmts[i1:i2])
        elif tag == "insert":
            out.extend({"tag": "added", "master": None, "client": s} for s in client_stmts[j1:j2])
        elif tag == "replace":
            m_block, c_block = master_stmts[i1:i2], client_stmts[j1:j2]
            paired = min(len(m_block), len(c_block))
            for k in range(paired):
                out.append({"tag": "changed", "master": m_block[k], "client": c_block[k]})
            out.extend({"tag": "removed", "master": s, "client": None} for s in m_block[paired:])
            out.extend({"tag": "added", "master": None, "client": s} for s in c_block[paired:])
    return out
