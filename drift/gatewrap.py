"""Deterministic two-direction IF-block wrapping -- PLAN-V4 B.2, scissors
not model. The AI merge works but is per-finding, costs a call, and can
hallucinate; for the common gated cases the splice is done with byte-safe
text surgery over statements.py-proven segmentation (via blocks.py's reuse
of it), falling back to the AI-merge flow whenever structure can't be
trusted. Both functions NEVER raise on malformed input and NEVER guess:
every distrust path returns None and the caller falls back.

  client_to_105  (back-port)   -> splice_up(): fold the CLIENT's changed
    statements into 105's current body behind THIS client's gate. Appends an
    `ELSE IF @ClientActive = <id>` branch to 105's existing top-level gate
    chain, or wraps 105's whole body in a new IF/ELSE when no chain exists.
    Other clients' logic is untouched by construction.

  105_to_client  (push update) -> preserve_down(): take MASTER's new body,
    then re-append every TOP-LEVEL gated branch found in the CLIENT's old
    body whose normalized condition master lacks -- verbatim, BEFORE any
    trailing ELSE branch (reachability: appended after ELSE it would never
    run, and `ELSE ... ELSE` isn't even valid T-SQL). Pushing raw master_def
    here would silently DELETE the client's customization -- the exact
    disaster class this tool exists to prevent.

Branch rebuild discipline: conditions and body bytes come out of
blocks._parse_chain verbatim; only the BEGIN/END wrapper around each body is
canonicalized (semantically identical for unbraced one-liners). Everything is
re-parsed before being emitted -- a splice we cannot re-parse is a splice we
do not ship.
"""
import re

try:
    from . import blocks, diffing, statements
except ImportError:  # allows `python3.13 test_gatewrap.py` to run standalone
    import blocks
    import diffing
    import statements

# --- reuse blocks.py's proven scanners (same package, deliberate coupling;
# each survived a measured corruption bug documented in that module's header) ---
_mask = blocks._mask                                    # noqa: SLF001
_parse_chain = blocks._parse_chain                      # noqa: SLF001
_segment_body = blocks._segment_body                    # noqa: SLF001
_unwrap_body = blocks._unwrap_body                      # noqa: SLF001
_trim_batch_tail = blocks._trim_batch_tail              # noqa: SLF001
_is_begin_tran = blocks._is_begin_tran                  # noqa: SLF001
_begin_end_re = statements._BEGIN_END_RE                # noqa: SLF001
_VAR_RE = blocks._VAR_RE                                # noqa: SLF001
_CURSOR_RE = statements._CURSOR_RE                      # noqa: SLF001


def _client_id(client_active_id) -> int | None:
    """Coerced gate ID, or None when unusable -- the ID is embedded into a
    condition string, so garbage in would mean a corrupt proc out."""
    try:
        return int(str(client_active_id).strip())
    except (TypeError, ValueError):
        return None


def _split_header_body(definition: str) -> tuple[str, str] | None:
    """(header up to and including AS, body tail) or None when no AS boundary
    was found at all -- without it there is no trustworthy place to re-splice."""
    _, body = diffing.split_param_body(definition)
    if not body or not definition.endswith(body):
        return None
    return definition[: len(definition) - len(body)], _trim_batch_tail(body.strip())


def _is_balanced(text: str) -> bool:
    """Literal/comment-safe BEGIN/CASE vs END depth walk over a whole region.
    False whenever some END closes past zero or the counter never returns --
    the caller refuses to rewrite anything it cannot prove balanced."""
    masked = _mask(text)
    depth = 0
    for m in _begin_end_re.finditer(masked):
        word = m.group().upper()
        if word == "CASE" or (word == "BEGIN" and not _is_begin_tran(masked, m.end())):
            depth += 1
        elif word == "END":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def _cond_norm(condition: str | None) -> str:
    """Normalized gate identity for dedupe comparisons. _parse_chain keeps an
    ELSE-IF branch's own `IF` keyword inside its condition text, so it is
    stripped first: 'IF @ClientActive = 66' and '@ClientActive = 66' are the
    same gate."""
    cond = (condition or "").strip()
    if re.match(r"^IF\b", cond, re.IGNORECASE):
        cond = cond[2:].lstrip()
    return diffing.normalize_sql(cond)


def _render_branch(b: dict) -> str:
    """Canonical rebuild of ONE parsed branch: the parsed condition text and
    body bytes are embedded verbatim; only the wrapper is canonicalized to
    BEGIN..END (semantically identical for unbraced one-liners). NOTE:
    _parse_chain keeps an ELSE-IF branch's own `IF` keyword INSIDE its
    condition text (it slices from just past `ELSE`), so it is stripped here
    before the prefix is re-emitted."""
    inner = b["body"] or ""
    if b["kind"] == "else":
        return f"ELSE\nBEGIN\n{inner}\nEND"
    cond = (b["condition"] or "").strip()
    if b["kind"] == "elseif":
        cond = re.sub(r"^IF\s+", "", cond, count=1, flags=re.IGNORECASE)
        prefix = "ELSE IF"
    else:
        prefix = "IF"
    return f"{prefix} {cond}\nBEGIN\n{inner}\nEND"


def _as_elseif(rendered: str) -> str:
    """A gate contributed INTO an existing chain must arrive as ELSE IF --
    a bare IF would start a NEW statement and swallow the chain's following
    ELSE into itself (caught live by the reparse guard; kept honest here)."""
    return re.sub(r"^IF\b", "ELSE IF", rendered, count=1, flags=re.IGNORECASE)


def _insert_before_trailing_else(branches: list[dict], parts: list[str],
                                 new_part: str) -> list[str]:
    """parts with new_part placed BEFORE a trailing ELSE branch (reachability),
    else appended last. A chain has at most one top-level ELSE and it must be
    the final branch."""
    insert_at = len(parts)
    for i, b in enumerate(branches):
        if b["kind"] == "else":
            insert_at = i
            break
    parts.insert(insert_at, new_part)
    return parts


def _replace_span(text: str, old: str, new: str) -> str | None:
    """text with the first occurrence of old swapped for new, found by plain
    slicing (segment texts are byte-exact slices of their body, so offsets
    outside the span are untouched by construction)."""
    idx = text.find(old)
    if idx < 0:
        return None
    return text[:idx] + new + text[idx + len(old):]


def splice_up(master_def: str, delta_statements: list, client_active_id) -> str | None:
    """PLAN-V4 B.2 client_to_105 back-port: fold the CLIENT's changed
    statements into 105's current body behind THIS client's gate.

    delta_statements: align_statements() output entries shaped
      {"tag": "added"|"changed"|..., "master": {...}, "client": {...}};
    the CLIENT-side "text" of every added/changed entry is collected as the
    new gated branch body, in alignment order.

    Returns the merged full definition, or None whenever structure is
    untrusted (_parse_chain failure, empty/unrecognized segments, CURSOR
    flow, unbalanced BEGIN/END, unusable client id, empty deltas, any
    exception) -- the caller falls back to AI merge. Never raises."""
    try:
        cid = _client_id(client_active_id)
        if cid is None or not master_def:
            return None
        collected = []
        for entry in delta_statements or []:
            if entry.get("tag") not in ("added", "changed"):
                continue
            side = entry.get("client") or {}
            text = (side.get("text") or "").strip()
            if not text:
                continue
            # Same trust rule blocks._parse_chain applies to branch wrappers,
            # applied to the fragments we are about to embed: a fragment that
            # opens a BEGIN it never closes would corrupt the rebuilt chain.
            if re.search(r"\bBEGIN\b", _mask(text), re.IGNORECASE) and _unwrap_body(text) is None:
                return None
            collected.append(text)
        if not collected:
            return None
        split = _split_header_body(master_def)
        if split is None:
            return None
        header, body = split
        if not body or not _is_balanced(body):
            return None
        if _CURSOR_RE.search(body):
            return None
        segs = _segment_body(body)
        if not segs:
            return None
        joined = "\n".join(collected)

        chain_seg = next((s for s in segs if s["kind"] == "IF"
                          and s["condition"] and _VAR_RE.search(s["condition"])), None)
        if chain_seg is not None:
            branches = _parse_chain(chain_seg["text"])
            if not branches:
                return None
            parts = [_render_branch(b) for b in branches]
            new_branch = f"ELSE IF @ClientActive = {cid}\nBEGIN\n{joined}\nEND"
            parts = _insert_before_trailing_else(branches, parts, new_branch)
            new_chain = "\n".join(parts)
            reparsed = _parse_chain(new_chain)
            if not reparsed or len(reparsed) != len(branches) + 1:
                return None
            new_body = _replace_span(body, chain_seg["text"], new_chain)
            if new_body is None:
                return None
        else:
            # No gate chain at top level: wrap the WHOLE original body as the
            # generic path -- its bytes ride along verbatim inside the ELSE.
            new_body = (f"IF @ClientActive = {cid}\nBEGIN\n{joined}\nEND\n"
                        f"ELSE\nBEGIN\n{body}\nEND")
        return f"{header}\n{new_body}"
    except Exception:  # noqa: BLE001 - malformed input degrades to fallback, never crashes
        return None


def _gated_branches(definition: str) -> list[dict] | None:
    """Top-level gated branches ({norm, rendered}) across every @ClientActive
    IF-chain of ONE definition, deduped within the source by normalized
    condition (a duplicated gate is kept once -- which duplicate is newer
    is unknowable from text alone). None = structure untrusted."""
    _, body = diffing.split_param_body(definition)
    body = _trim_batch_tail((body or definition).strip())
    if not body or _CURSOR_RE.search(body) or not _is_balanced(body):
        return None
    segs = _segment_body(body)
    if not segs:
        return None
    out = []
    seen_norms = set()
    for s in segs:
        if s["kind"] != "IF" or not s["condition"] or not _VAR_RE.search(s["condition"]):
            continue
        branches = _parse_chain(s["text"])
        if not branches:
            return None
        for b in branches:
            if b["kind"] == "else":
                continue
            norm = _cond_norm(b["condition"])
            if not norm or norm in seen_norms:
                continue
            seen_norms.add(norm)
            out.append({"norm": norm, "rendered": _render_branch(b)})
    return out


def preserve_down(master_def_new: str, client_def_old: str) -> str | None:
    """PLAN-V4 B.2 105_to_client push: MASTER's new body, but every TOP-LEVEL
    gated branch found in the CLIENT's OLD body whose normalized condition
    (diffing.normalize_sql) master lacks gets re-appended VERBATIM to master's
    chain -- BEFORE a trailing ELSE branch when one exists (appended after it
    the branch could never run), else at chain end.

    Returns the merged full definition, or None when structure is untrusted
    OR when the client contributes zero extra gates (every client condition
    already exists in master's chain, so the caller keeping plain master_def
    loses nothing). Never mutates inputs, never raises."""
    try:
        if not master_def_new or not client_def_old:
            return None
        client_gates = _gated_branches(client_def_old)
        if not client_gates:
            return None
        split = _split_header_body(master_def_new)
        if split is None:
            return None
        header, m_body = split
        if not m_body:
            return None
        segs = _segment_body(m_body)
        if not segs:
            return None
        chain_seg = next((s for s in segs if s["kind"] == "IF"
                          and s["condition"] and _VAR_RE.search(s["condition"])), None)
        if chain_seg is None:
            # Client HAS gates master's body cannot host (no trusted chain to
            # receive them): refusing beats splicing them somewhere unproven.
            return None
        branches = _parse_chain(chain_seg["text"])
        if not branches:
            return None
        master_norms = {_cond_norm(b["condition"])
                        for b in branches if b["kind"] != "else"}
        extras = [g for g in client_gates if g["norm"] not in master_norms]
        if not extras:
            return None
        parts = [_render_branch(b) for b in branches]
        parts = _insert_before_trailing_else(
            branches, parts,
            "\n".join(_as_elseif(g["rendered"]) for g in extras))
        new_chain = "\n".join(parts)
        reparsed = _parse_chain(new_chain)
        if not reparsed or len(reparsed) != len(branches) + len(extras):
            return None
        new_body = _replace_span(m_body, chain_seg["text"], new_chain)
        if new_body is None:
            return None
        return f"{header}\n{new_body}"
    except Exception:  # noqa: BLE001 - malformed input degrades to fallback, never crashes
        return None
