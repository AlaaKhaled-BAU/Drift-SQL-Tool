"""ClientActive block-scope resolution -- compare ONLY what this client executes.

The update workflow's core scoping rule (user requirement, PLAN-V4 B.2a):
a procedure shared across clients dispatches on @ClientActive. A diff inside
another client's gated branch (`IF @ClientActive = 165 ...`) is REAL drift but
IRRELEVANT to this client's update. This module resolves, for ONE procedure
body and ONE ClientActive ID, exactly which blocks are reachable at runtime:

  match     -> definitely this client's path: KEEP
  no_match  -> definitely some OTHER client's gate: EXCLUDE (reported, never
               silently gone -- the caller decides what visibility means)
  unknown   -> anything we cannot decide statically (= @SomeVar, compound
               predicate mixing other columns, EXISTS subqueries): KEEP +
               FLAG. Conservative by design: a wrongly-included block costs a
               human glance; a wrongly-excluded block is a missed change --
               the cardinal failure this tool exists to prevent.

Structure discovery reuses statements.py's battle-tested literal/comment-safe
depth scanner (CASE-END sharing END, BEGIN TRAN, outer AS BEGIN wrapper --
each a measured corruption bug in that module's history). An entire top-level
dispatch chain arrives as ONE IF segment (the segmenter's one-shot ELSE
suppression keeps the chain attached to its first IF -- see
statements._segment_statements), so the missing piece THIS module adds is
branch splitting INSIDE that segment, plus reachability resolution down the
chain and into nested gates.

Resolution semantics (the user's push/pop model, formalized):
  - walk the chain in order; a definite match makes every LATER branch
    unreachable FOR THIS CLIENT (including a trailing ELSE);
  - a definite no_match moves on to the next sibling;
  - an unknown keeps every later sibling possibly-reachable;
  - ELSE is reachable iff nothing before it definitely matched, uncertain if
    something before it was merely possible;
  - nesting composes: gates inside a KEPT subtree are resolved recursively;
  - explicit frame stack mirrors BEGIN-push / END-pop; CASE shares the depth
    counter but never opens a frame (scalar expression, not control flow).

Pure, no DB, no network, fully unit-tested -- diffing/statements house style.
Never mutates detection results upstream; consumers decide what excluded
means (today: the visible `irrelevant_to_client` bucket, PLAN-V4 B.1/B.2a).
"""
import hashlib
import re

try:
    from . import diffing, statements
except ImportError:  # standalone test run: python3.13 test_blocks.py
    import diffing
    import statements

# --- reuse statements.py's proven scanners (same package, deliberate coupling;
# each survived a measured corruption bug documented in that module's header) ---
_mask = statements._mask_literals_and_comments          # noqa: SLF001
_begin_end_re = statements._BEGIN_END_RE                 # noqa: SLF001
_is_begin_tran = statements._is_begin_tran               # noqa: SLF001
_segment_statements = statements._segment_statements     # noqa: SLF001
_classify = statements._classify                         # noqa: SLF001

_VAR_RE = re.compile(r"@ClientActive\b", re.IGNORECASE)

# Recognized gate shapes around the variable. Operand order matters
# (`165 = @ClientActive` appears in the wild). Anything mentioning the
# variable in an unrecognized shape is UNKNOWN, never guessed.
# Operator order: test <>, <=, >= before <, >, = so bare < or = never eats compound ops.
_BETWEEN_RE = re.compile(r"@ClientActive\s+(NOT\s+)?BETWEEN\s+(\d+)\s+AND\s+(\d+)\b", re.IGNORECASE)
_BETWEEN_AND_MASK_RE = re.compile(r"(@ClientActive\s+(?:NOT\s+)?BETWEEN\s+\d+\s+)(AND)(\s+\d+)", re.IGNORECASE)

_NE_FWD_RE = re.compile(r"@ClientActive\s*<>\s*(\d+)\b", re.IGNORECASE)
_NE_REV_RE = re.compile(r"\b(\d+)\s*<>\s*@ClientActive\b", re.IGNORECASE)
_LE_FWD_RE = re.compile(r"@ClientActive\s*<=\s*(\d+)\b", re.IGNORECASE)
_LE_REV_RE = re.compile(r"\b(\d+)\s*<=\s*@ClientActive\b", re.IGNORECASE)
_GE_FWD_RE = re.compile(r"@ClientActive\s*>=\s*(\d+)\b", re.IGNORECASE)
_GE_REV_RE = re.compile(r"\b(\d+)\s*>=\s*@ClientActive\b", re.IGNORECASE)
_LT_FWD_RE = re.compile(r"@ClientActive\s*<\s*(\d+)\b", re.IGNORECASE)
_LT_REV_RE = re.compile(r"\b(\d+)\s*<\s*@ClientActive\b", re.IGNORECASE)
_GT_FWD_RE = re.compile(r"@ClientActive\s*>\s*(\d+)\b", re.IGNORECASE)
_GT_REV_RE = re.compile(r"\b(\d+)\s*>\s*@ClientActive\b", re.IGNORECASE)
_EQ_FWD_RE = re.compile(r"@ClientActive\s*=\s*(\d+)\b", re.IGNORECASE)
_EQ_REV_RE = re.compile(r"\b(\d+)\s*=\s*@ClientActive\b", re.IGNORECASE)
_IN_RE = re.compile(r"@ClientActive\s+(NOT\s+)?IN\s*\(([^()]*)\)", re.IGNORECASE)

_OR_SPLIT_RE = re.compile(r"\bOR\b", re.IGNORECASE)
_AND_SPLIT_RE = re.compile(r"\bAND\b", re.IGNORECASE)
_ELSE_RE = re.compile(r"\bELSE\b", re.IGNORECASE)
_IF_RE = re.compile(r"\bIF\b", re.IGNORECASE)
_BODY_START_RE = re.compile(
    r"\b(BEGIN|SELECT|INSERT|UPDATE|DELETE|MERGE|EXEC|EXECUTE|DECLARE|SET|PRINT|"
    r"RAISERROR|THROW|WITH|COMMIT|ROLLBACK|TRUNCATE|RETURN|GOTO|WAITFOR|"
    r"CREATE|ALTER|DROP|WHILE|IF)\b",
    re.IGNORECASE,
)
_LABEL_RE = re.compile(r"(?im)^[ \t]*([A-Za-z_]\w*)[ \t]*:")
_GOTO_RE = re.compile(r"(?i)\bGOTO\s+([A-Za-z_]\w*)")


def _has_enclosing_parens(s: str) -> bool:
    """True if s is enclosed by a matching top-level ( ... ) pair."""
    s = s.strip()
    if not (s.startswith("(") and s.endswith(")")):
        return False
    depth = 0
    for i, c in enumerate(s):
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0 and i < len(s) - 1:
                return False
    return depth == 0


def _split_top_level(text: str, sep_re: re.Pattern) -> list[str]:
    """Split ONLY at parenthesis-depth-zero separators (an IN(...) list holds
    commas; predicates nest). Runs on comment-masked text of equal length, so
    slices map straight back onto the original string."""
    parts, last = [], 0
    depth = 0
    for m in sep_re.finditer(text):
        depth += text[last:m.start()].count("(") - text[last:m.start()].count(")")
        if depth == 0:
            parts.append(text[last:m.start()])
            last = m.end()
    parts.append(text[last:])
    return parts


def _split_and_protect_between(group_text: str) -> list[str]:
    """Split group_text by AND at depth 0, protecting the internal AND of BETWEEN."""
    masked_between = _BETWEEN_AND_MASK_RE.sub(
        lambda m: m.group(1) + " " * len(m.group(2)) + m.group(3),
        group_text
    )
    parts, last = [], 0
    depth = 0
    for m in _AND_SPLIT_RE.finditer(masked_between):
        depth += masked_between[last:m.start()].count("(") - masked_between[last:m.start()].count(")")
        if depth == 0:
            parts.append(group_text[last:m.start()])
            last = m.end()
    parts.append(group_text[last:])
    return parts


def _eval_term(term: str, cid: int) -> str:
    """One boolean term -> match | no_match | unknown."""
    t = term.strip()
    if not t or not _VAR_RE.search(t):
        return "unknown"
    if _has_enclosing_parens(t):
        return evaluate_condition(t[1:-1].strip(), cid)
    m = _BETWEEN_RE.search(t)
    if m:
        low, high = int(m.group(2)), int(m.group(3))
        inside = low <= cid <= high
        if m.group(1):  # NOT BETWEEN
            return "no_match" if inside else "match"
        return "match" if inside else "no_match"
    m = _NE_FWD_RE.search(t) or _NE_REV_RE.search(t)
    if m:
        return "no_match" if int(m.group(1)) == cid else "match"
    m = _LE_FWD_RE.search(t)
    if m:
        return "match" if cid <= int(m.group(1)) else "no_match"
    m = _LE_REV_RE.search(t)
    if m:
        return "match" if int(m.group(1)) <= cid else "no_match"
    m = _GE_FWD_RE.search(t)
    if m:
        return "match" if cid >= int(m.group(1)) else "no_match"
    m = _GE_REV_RE.search(t)
    if m:
        return "match" if int(m.group(1)) >= cid else "no_match"
    m = _LT_FWD_RE.search(t)
    if m:
        return "match" if cid < int(m.group(1)) else "no_match"
    m = _LT_REV_RE.search(t)
    if m:
        return "match" if int(m.group(1)) < cid else "no_match"
    m = _GT_FWD_RE.search(t)
    if m:
        return "match" if cid > int(m.group(1)) else "no_match"
    m = _GT_REV_RE.search(t)
    if m:
        return "match" if int(m.group(1)) > cid else "no_match"
    m = _EQ_FWD_RE.search(t) or _EQ_REV_RE.search(t)
    if m:
        return "match" if int(m.group(1)) == cid else "no_match"
    m = _IN_RE.search(t)
    if m:
        ids = {int(x) for x in re.findall(r"\d+", m.group(2))}
        inside = cid in ids
        if m.group(1):                       # NOT IN
            return "no_match" if inside else "match"
        return "match" if inside else "no_match"
    return "unknown"


def _combine(verdicts: list[str], is_conjunction: bool) -> str:
    """AND: any no_match wins, then unknown degrades, then match.
    OR : any match wins, then unknown degrades, then no_match."""
    if is_conjunction:
        if "no_match" in verdicts:
            return "no_match"
        return "unknown" if "unknown" in verdicts else "match"
    if "match" in verdicts:
        return "match"
    return "unknown" if "unknown" in verdicts else "no_match"


def evaluate_condition(condition: str | None, client_active_id) -> str:
    """Three-state verdict for ONE gate condition vs this client's ID.
    None (a bare ELSE) is decided by the CHAIN walk, never here."""
    if not condition or not condition.strip():
        return "unknown"
    try:
        cid = int(str(client_active_id).strip())
    except (TypeError, ValueError):
        return "unknown"
    masked = _mask(condition)
    if not _VAR_RE.search(masked):
        return "unknown"   # e.g. EXISTS(SELECT ... FROM ClientsActive ...) -- keep + flag
    groups = [_combine([_eval_term(t, cid) for t in _split_and_protect_between(g)],
                       is_conjunction=True)
              for g in _split_top_level(masked, _OR_SPLIT_RE)]
    return _combine(groups, is_conjunction=False)


# --- branch splitting inside ONE IF-chain segment ------------------------------

def _unwrap_body(slice_text: str) -> str | None:
    """Body content of one branch slice: strip a leading BEGIN..END wrapper
    (literal-safe depth walk) and return the inside verbatim. None when the
    wrapper is unbalanced -- treated as structure-untrusted by the caller."""
    masked = _mask(slice_text)
    bm = re.search(r"\bBEGIN\b", masked, re.IGNORECASE)
    if not bm:
        return None
    if _is_begin_tran(masked, bm.end()):
        return None
    depth = 1
    for m in _begin_end_re.finditer(masked, bm.end()):
        w = m.group().upper()
        if w == "CASE" or (w == "BEGIN" and not _is_begin_tran(masked, m.end())):
            depth += 1
        elif w == "END":
            depth -= 1
            if depth == 0:
                return slice_text[bm.end():m.start()]
    return None


def _compound_interior(text: str) -> tuple[str, int] | None:
    """Interior of a segment that is itself a BEGIN/END compound, with no
    code after the matching END. None for BEGIN TRAN or a partial block.
    Returns (unstripped_interior, interior_offset_in_text)."""
    masked = _mask(text)
    lead = len(masked) - len(masked.lstrip())
    if not re.match(r"BEGIN\b", masked[lead:], re.IGNORECASE):
        return None
    if _is_begin_tran(masked, lead + len("BEGIN")):
        return None
    bm = re.search(r"\bBEGIN\b", masked, re.IGNORECASE)
    if not bm:
        return None
    depth = 1
    end_at = close_end = None
    for m in _begin_end_re.finditer(masked, bm.end()):
        w = m.group().upper()
        if w == "CASE" or (w == "BEGIN" and not _is_begin_tran(masked, m.end())):
            depth += 1
        elif w == "END":
            depth -= 1
            if depth == 0:
                end_at, close_end = m.start(), m.end()
                break
    tail = masked[close_end:]
    # END TRY / END CATCH: the word after END is the block kind, not more code.
    if tail.strip() and not re.fullmatch(r"\s*(?:TRY|CATCH)\s*", tail, re.IGNORECASE):
        return None
    return text[bm.end():end_at], bm.end()


def _fingerprint_text(text: str) -> str:
    """Scope identity ignores spacing around operators, so `@ClientActive=66`
    and `@ClientActive = 66` are the same kept gate."""
    n = diffing.normalize_sql(text)
    return re.sub(r"\s*([=<>(),])\s*", r"\1", n)


def _render_kept_branch(kind: str, condition: str | None, inner: str, *, leading: bool = False) -> str:
    """Kept arm, with the gate line still visible. Dead arms are omitted
    entirely; this is only for match and unknown branches.
    `leading` is True for the first emitted arm of a chain so ELSE IF
    is rewritten as IF (a lone ELSE IF is not valid T-SQL)."""
    inner = (inner or "").strip("\n")
    if kind == "else":
        if leading:
            return f"BEGIN\n{inner}\nEND"
        return f"ELSE\nBEGIN\n{inner}\nEND"
    cond = (condition or "").strip()
    if kind == "elseif":
        cond = re.sub(r"^IF\s+", "", cond, count=1, flags=re.IGNORECASE)
        prefix = "IF" if leading else "ELSE IF"
    else:
        prefix = "IF"
    return f"{prefix} {cond}\nBEGIN\n{inner}\nEND"


def _parse_chain(chain_text: str) -> list[dict] | None:
    """Split ONE top-level IF-chain segment into ordered branches:
    [{kind: if|elseif|else, condition, body}]. Returns None when structure is
    untrusted (unbalanced wrappers) -- caller keeps the whole chain, flagged.
    Byte-exact branch bodies (BEGIN/END wrappers unwrapped)."""
    masked = _mask(chain_text)
    im = _IF_RE.search(masked)
    if not im:
        return None

    # One merged, position-sorted event walk over the whole chain:
    # BEGIN(non-tran)/CASE push the shared depth counter, END pops, and an
    # ELSE belongs to THIS chain only when it fires at depth 0 -- an ELSE
    # inside any nested block is that block's business (the user's stack
    # discipline, formalized).
    events = []
    for m in re.finditer(r"\bBEGIN\b|\bCASE\b|\bEND\b", masked[im.start():], re.IGNORECASE):
        events.append((im.start() + m.start(), m.group().upper()))
    for m in _ELSE_RE.finditer(masked, im.start()):
        events.append((im.start() + m.start(), "ELSE"))
    depth = 0
    else_positions = []
    for pos, w in sorted(events):
        if w == "CASE":
            depth += 1
        elif w == "BEGIN":
            if not _is_begin_tran(masked, pos + len("BEGIN")):
                depth += 1
        elif w == "END":
            depth -= 1
        elif w == "ELSE" and depth == 0:
            else_positions.append(pos)

    bounds = [im.start()] + else_positions + [len(chain_text)]
    branches = []
    for i in range(len(bounds) - 1):
        start = bounds[i]
        stop = bounds[i + 1]
        raw = chain_text[start:stop]
        raw_masked = _mask(raw)
        head = raw_masked.lstrip().upper()
        if i == 0:
            kind = "if"
            im2 = _IF_RE.search(raw_masked)
            cond, past_rel = _extract_cond(raw[im2.end():])
            past = im2.end() + past_rel
        elif _ELSE_RE.match(raw_masked.lstrip()):
            em = _ELSE_RE.search(raw_masked)
            after_else = raw[em.end():]
            # `ELSE IF`, `ELSE  IF`, and `ELSE\nIF` are one arm. A single
            # space is not the only legal separator.
            m_lead_if = re.match(r"\s*IF\b", _mask(after_else), re.IGNORECASE)
            if m_lead_if:
                kind = "elseif"
                skip = m_lead_if.end()
                cond, past_rel = _extract_cond(after_else[skip:])
                past = em.end() + skip + past_rel
            else:
                kind = "else"
                cond = None
                past = em.end()
        else:
            return None                      # slice neither IF nor ELSE -> distrust
        tail = raw[past:]
        tail_masked = _mask(tail)
        bm = re.search(r"\bBEGIN\b", tail_masked, re.IGNORECASE)
        if bm and not _is_begin_tran(tail_masked, bm.end()):
            body = _unwrap_body(tail)
            if body is None:
                return None                  # unbalanced wrapper -> distrust
            bounded = True
            body_offset = start + past + bm.end()
        else:
            body = tail
            bounded = False
            body_offset = start + past
        branches.append({"kind": kind, "condition": cond, "body": body,
                         "bounded": bounded, "start": start, "stop": stop,
                         "raw": raw, "body_offset": body_offset})
    return branches


def _extract_cond(after_if_keyword: str) -> tuple[str | None, int]:
    """(condition, offset_past_condition).

    The condition runs until a body keyword at parenthesis depth 0.
    Newlines do not end it. A SELECT inside NOT IN (...) does not end it.
    """
    masked = _mask(after_if_keyword)
    paren = 0
    i = 0
    n = len(masked)
    while i < n:
        ch = masked[i]
        if ch == "(":
            paren += 1
            i += 1
            continue
        if ch == ")":
            paren = max(0, paren - 1)
            i += 1
            continue
        if paren == 0:
            m = _BODY_START_RE.match(masked, i)
            if m:
                cond = after_if_keyword[:i].strip(" \t\r\n;")
                return (cond or None), i
        i += 1
    cond = after_if_keyword.strip(" \t\r\n;")
    return (cond or None), len(after_if_keyword)


def _outside_goto_targets(full_masked: str, branch_start: int, branch_stop: int) -> set[str]:
    outside = full_masked[:branch_start] + full_masked[branch_stop:]
    return {m.group(1).lower() for m in _GOTO_RE.finditer(outside)}


def _labels_in(masked: str) -> set[str]:
    return {m.group(1).lower() for m in _LABEL_RE.finditer(masked)}


def _segment_body(body_text: str) -> list[dict] | None:
    """Statement segmentation for a RAW body fragment. Returns None when the
    segmenter finds no boundaries at all (nothing to scope). Deliberately does
    NOT gate on cursor/vocabulary -- that decision belongs to resolve_scope's
    mode labeling, because block BOUNDARIES survive vocabulary distrust: a
    CURSOR proc's IF/BEGIN/END still balance correctly through the scanner,
    and a provably-dead other-client branch stays provably dead inside it."""
    segs = _segment_statements(body_text, include_offset=True)
    if not segs:
        return None
    out = []
    for text, line, offset in segs:
        kind, condition = _classify(text)
        out.append({"kind": kind, "condition": condition, "text": text, "line": line, "offset": offset})
    return out


_BATCH_TAIL_RE = re.compile(r"[\s;]*\bGO\b[\s;]*$", re.IGNORECASE)


def _trim_batch_tail(body_text: str) -> str:
    """Strip trailing SSMS batch separators (GO) that dump files leave after
    the closing END. Without this, _strip_outer_begin_end refuses the wrapper
    ('something follows the closing END') and the ENTIRE proc collapses into
    one unsplittable segment -- measured on the real 218KB
    OT_SendCustomersInfo dump."""
    prev = None
    while prev != body_text:
        prev = body_text
        body_text = _BATCH_TAIL_RE.sub("", body_text).rstrip()
    return body_text


def resolve_scope(definition: str, client_active_id) -> dict:
    """Classify every block in the definition against this client's ID using
    an explicit frame stack (BEGIN pushes / END pops, recursion composes).

    Tiered honesty contract (the deep-test finding on the real 218KB
    OT_SendCustomersInfo: one CURSOR anywhere used to void the whole proc):

      mode="structured"  strict statements.py gates pass (no CURSOR, some
                         recognized vocabulary). STRONG claims: fingerprint
                         equality on both sides proves the bodies differ only
                         inside blocks dead for this client.
      mode="heuristic"   gates failed but boundaries still balanced (CURSOR
                         procs, exotic vocab). The excluded_blocks list is
                         trustworthy -- a branch whose condition definitely
                         evaluates no_match never runs for this client
                         regardless of chain context -- so review scope can
                         be trimmed. NO fingerprint: equality is never claimed
                         from untrusted structure.
      ok=False           nothing decidable; compare the full definition.

    Returns {"ok": True, mode, relevant_blocks, excluded_blocks, excluded_ranges, stats,
             fingerprint (structured only), reason (heuristic caveat)}
    """
    definition = (definition or "").replace("\r\n", "\n")
    _, body, body_offset = diffing.split_param_body(definition, include_offset=True)
    if not body:
        body = definition
        body_offset = 0
    else:
        body = _trim_batch_tail(body)
    try:
        cid = int(str(client_active_id).strip())
    except (TypeError, ValueError):
        return {"ok": False, "reason": f"invalid client_active_id {client_active_id!r}"}

    masked_body = _mask(body)

    def targeted(raw: str, def_abs_start: int) -> bool:
        rel = def_abs_start - body_offset
        if rel < 0:
            return False
        labels = _labels_in(_mask(raw))
        if not labels:
            return False
        outside = _outside_goto_targets(masked_body, rel, rel + len(raw))
        return bool(labels & outside)

    top_segs = _segment_body(body)
    if top_segs is None:
        return {"ok": False,
                "reason": "no statement boundaries recognized in this body"}

    cursor_hit = bool(statements._CURSOR_RE.search(masked_body))     # noqa: SLF001
    recognized = any(s["kind"] != "OTHER" for s in top_segs)
    structured = not cursor_hit and recognized

    relevant: list[str] = []
    excluded: list[dict] = []
    excluded_ranges: list[list[int]] = []
    stats = {"match": 0, "no_match": 0, "unknown": 0, "unknown_client": 0}

    def note_unknown(condition: str | None) -> None:
        stats["unknown"] += 1
        if condition and re.search(r"@ClientActive\b", condition, re.IGNORECASE):
            stats["unknown_client"] += 1

    def walk(body_text: str, base_offset: int) -> bool:
        """True = region fully walked; False = no boundaries here (caller of
        a kept branch then keeps its whole text verbatim -- degrade, never
        drop)."""
        segs = _segment_body(body_text)
        if segs is None:
            return False

        for seg in segs:
            seg_abs_offset = base_offset + seg["offset"]
            if seg["kind"] != "IF":
                comp = _compound_interior(seg["text"])
                if comp is not None:
                    interior, interior_offset = comp
                    mark = len(relevant)
                    if walk(interior, seg_abs_offset + interior_offset):
                        head = re.match(
                            r"\s*BEGIN\s+(TRY|CATCH)\b",
                            _mask(seg["text"]),
                            re.IGNORECASE,
                        )
                        if head:
                            inner = "\n".join(relevant[mark:]).strip("\n")
                            del relevant[mark:]
                            kind = head.group(1).upper()
                            relevant.append(f"BEGIN {kind}\n{inner}\nEND {kind}")
                        continue
                relevant.append(seg["text"])
                continue
            branches = _parse_chain(seg["text"])
            if not branches:
                relevant.append(seg["text"])     # unsplittable chain: keep whole
                note_unknown(seg["text"])
                continue
            matched = False       # some earlier branch DEFINITELY runs for us
            prior_uncertain = False
            emitted = False

            def _merge_label_lines(source: str, inner: str) -> str:
                """Statement segmentation often drops standalone GOTO labels."""
                extra = [ln for ln in source.splitlines()
                         if _LABEL_RE.match(ln) and ln.strip() not in (inner or "")]
                if not extra:
                    return inner
                return "\n".join(extra + ([inner] if (inner or "").strip() else []))

            def emit_kept(kind: str, condition: str | None, body: str, body_abs_offset: int) -> None:
                """Keep the gate line around whatever of this arm still runs."""
                nonlocal emitted
                if not (body or "").strip():
                    return
                mark = len(relevant)
                if walk(body, body_abs_offset):
                    inner = "\n".join(relevant[mark:])
                    del relevant[mark:]
                else:
                    inner = body
                inner = _merge_label_lines(body, inner)
                relevant.append(_render_kept_branch(kind, condition, inner, leading=not emitted))
                emitted = True

            for b in branches:
                branch_abs_start = seg_abs_offset + b["start"]
                branch_raw = b["raw"]
                b_start_line = definition.count("\n", 0, branch_abs_start) + 1
                b_end_line = definition.count("\n", 0, branch_abs_start + len(branch_raw.rstrip())) + 1
                b_body_abs_offset = seg_abs_offset + b.get("body_offset", 0)

                if b["kind"] == "else":
                    v = "no_match" if matched else ("unknown" if prior_uncertain else "match")
                else:
                    v = evaluate_condition(b["condition"], cid)
                if v == "no_match":
                    if b.get("bounded"):
                        if targeted(branch_raw, branch_abs_start):
                            note_unknown(b.get("condition"))
                            prior_uncertain = True
                            emit_kept(b["kind"], b["condition"], b["body"] or "", b_body_abs_offset)
                            continue
                        stats["no_match"] += 1
                        excluded.append({
                            "line": b_start_line,
                            "start_line": b_start_line,
                            "end_line": b_end_line,
                            "condition": b["condition"] or "(else)",
                            "kind": "else" if b["kind"] == "else" else "other_client",
                            "body": b["body"] or "",
                        })
                        excluded_ranges.append([b_start_line, b_end_line])
                        continue
                    # Unbraced/unbounded
                    if targeted(branch_raw, branch_abs_start):
                        note_unknown(b.get("condition"))
                        prior_uncertain = True
                        emit_kept(b["kind"], b["condition"], b["body"] or "", b_body_abs_offset)
                        continue
                    body_segs = _segment_body(b["body"] or "")
                    if body_segs is not None and len(body_segs) == 1:
                        stats["no_match"] += 1
                        excluded.append({
                            "line": b_start_line,
                            "start_line": b_start_line,
                            "end_line": b_end_line,
                            "condition": b["condition"] or "(else)",
                            "kind": "else" if b["kind"] == "else" else "other_client",
                            "body": b["body"] or "",
                        })
                        excluded_ranges.append([b_start_line, b_end_line])
                        continue
                    note_unknown(b.get("condition"))
                    prior_uncertain = True
                    if b["body"]:
                        if not walk(b["body"], b_body_abs_offset):
                            relevant.append(b["body"])
                    continue
                if v == "match":
                    stats["match"] += 1
                    matched = True
                else:
                    note_unknown(b.get("condition"))
                    prior_uncertain = True
                if b.get("bounded") or v != "match":
                    # A definite match of an unbraced arm is just its statement.
                    # An unknown unbraced arm must keep the condition, or the
                    # statement would run for every client.
                    emit_kept(b["kind"], b["condition"], b["body"] or "", b_body_abs_offset)
                elif b["body"] and not walk(b["body"], b_body_abs_offset):
                    relevant.append(b["body"])
        return True

    if not walk(body, body_offset):
        return {"ok": False,
                "reason": "body structure not trustworthy for scope resolution "
                          "(unbalanced BEGIN/END); compare the full definition instead"}
    if not structured and not excluded:
        # Heuristic mode earns its keep ONLY by proving specific blocks dead.
        # Zero exclusions = nothing gained = honest refusal, never a fake ok.
        cause = ("CURSOR-based flow" if cursor_hit
                 else "unrecognized statement vocabulary")
        return {"ok": False,
                "reason": f"{cause} and no provably-dead gated block found -- "
                          "compare the full definition instead"}
    result = {"ok": True, "mode": "structured" if structured else "heuristic",
              "client_id": cid,
              "relevant_blocks": relevant, "excluded_blocks": excluded,
              "excluded_ranges": excluded_ranges,
              "stats": stats}
    if structured:
        norm = "\n--BLOCK--\n".join(_fingerprint_text(t) for t in relevant)
        result["fingerprint"] = hashlib.sha256(norm.encode()).hexdigest()[:16]
    else:
        result["fingerprint"] = None
        result["reason"] = ("CURSOR-based flow or unrecognized vocabulary in this "
                            "body -- exclusions are a trimming aid only; equality "
                            "is NOT claimed; diff the full definition for approval")
    return result
