"""Deterministic finding classifier -- PLAN-V4 B.1 "small / gated / major /
excluded" ladder.

Consumes ONE enriched finding dict straight out of pipeline._enrich() and
answers the only question the update button needs per finding: what do we do
with this? The plan's boundary statement (B.0) is law here:

    CLASSIFY = deterministic rules first; AI only as labeled fallback

so this module is pure, stdlib-only (a single `re` import -- no sibling-module
imports at all, so unlike scriptgen.py it needs no try/except ImportError
standalone-run fallback), never touches a database or a model, NEVER mutates
the finding it reads, and NEVER raises on missing/stale evidence: every field
is read through .get() chains and isinstance guards, because disk-reloaded
runs (index.json round-trips, recompare()) may carry findings whose
statement_alignment is absent, None, an empty list, or otherwise stale --
"evidence unavailable" degrades to the coarser rules, it does not crash.

The ladder (FIRST MATCH WINS -- order is the safety story):

  R1  scope.irrelevant_to_client is True      -> irrelevant_to_client / skip
      (blocks.py proved BOTH sides' reachable-for-this-client code identical;
      the diff lives only in blocks some other client executes. Beats
      everything, including cosmetic -- visibility of *why* we skip differs.)
  R2  category formatting_only/no_difference/documentation -> cosmetic / skip
      (nothing semantic to apply; D1 demotions and comment-only drift land
      here so they are counted, visible, and never scripted).
  R3  statement_alignment shows ONLY added branches whose client-side
      condition references @ClientActive     -> gated_customization / gate_wrap
      (the P3 shape from the parallel-test results: a new ELSE IF
      @ClientActive = <id> branch. gatewrap.splice_up() can fold it
      deterministically; no AI call needed).
  R4  change_kind == param                   -> small / apply_asis
      (defaults-only signature change; body untouched, apply verbatim).
  R5  change_kind == body AND alignment present AND <= 3 changed/added
      entries, screened against lost-line risk -> small / apply_asis,
      demoted to major when a risk token is being LOST (see RISK_RES).
  R6  everything else                        -> major / ai_merge
      (the honest default: low confidence, human reviews, AI drafts).

R5's risk screen, precisely: build the SET of master-side text lines absent
from the client side across ALL alignment entries, normalized to whitespace-
collapsed non-blank lines. Set semantics (not per-entry) is deliberate: a line
removed from one statement but reinserted IDENTICALLY elsewhere in the client
body is not lost at all, and must not trigger the screen. If any genuinely
lost line matches one of RISK_RES the finding is demoted to major -- losing a
WHERE/JOIN/TOP/<=/>=/COMMIT/ROLLBACK/THROW/EXEC/INSERT INTO/UPDATE/DELETE line
can change behavior for EVERY client sharing the proc, not just this one, so
conservative demotion beats confident application (same posture as blocks.py:
a wrongly-included item costs a glance, a wrongly-applied one is a missed
regression). Whitespace normalization before set comparison keeps indentation
shifts and blank-line churn from fabricating phantom losses.

Every verdict carries which rule fired + a confidence float, per B.1: "Every
item carries classification + confidence + which rule fired." Low-confidence
majors are exactly the short list the human reviews.
"""
import re

# --- contract constants -------------------------------------------------------

# R2: categories that mean "no semantic difference to apply". documentation is
# compare.py's comment/metadata-only category; no_difference is pipeline._enrich's
# D1 demotion of SqlPackage phantom changes; formatting_only is diffing.py's
# whitespace/case-only verdict. All three are visible-but-unscriptable by design.
COSMETIC_CATEGORIES = ("formatting_only", "no_difference", "documentation")

# R3: the client-side gate condition must reference the dispatch variable.
# Case-insensitive SUBSTRING match, not blocks._VAR_RE's \b-anchored form: the
# contract for this module says "contains", and over-matching here is harmless
# (gate_wrap re-verifies structure downstream; under-matching would silently
# push real gated customizations into AI merge).
GATE_TOKEN = "@clientactive"

# R5: losing any master-side line containing these means OTHER clients'
# runtime behavior could change when the small change is applied as-is --
# predicate loss (WHERE/JOIN), row-count semantics (TOP), comparison-width
# flips (<-><=), transaction-scope changes (COMMIT/ROLLBACK), error-surface
# changes (THROW), and data-mutation statements (EXEC/INSERT INTO/UPDATE/
# DELETE). Compiled once, case-insensitive; scanned against whitespace-
# normalized lines. Module constant per contract -- tests pin its membership.
RISK_RES = (
    re.compile(r"\bWHERE\b", re.IGNORECASE),
    re.compile(r"\bJOIN\b", re.IGNORECASE),
    re.compile(r"\bTOP\s*\(", re.IGNORECASE),
    re.compile(r"<=", re.IGNORECASE),
    re.compile(r">=", re.IGNORECASE),
    re.compile(r"\bCOMMIT\b", re.IGNORECASE),
    re.compile(r"\bROLLBACK\b", re.IGNORECASE),
    re.compile(r"\bTHROW\b", re.IGNORECASE),
    re.compile(r"\bEXEC\b", re.IGNORECASE),
    re.compile(r"\bINSERT\s+INTO\b", re.IGNORECASE),
    re.compile(r"\bUPDATE\b", re.IGNORECASE),
    re.compile(r"\bDELETE\b", re.IGNORECASE),
)

# R5's smallness ceiling: more than this many changed/added statements and the
# body is no longer "small" by inspection -- route to AI merge instead of
# pretending a 5-statement rewrite is reviewable as a unit.
MAX_SMALL_DELTAS = 3


def _verdict(bucket: str, action: str, rule: str, confidence: float) -> dict:
    """The ONE verdict shape, built fresh every time -- classification output
    must never alias anything inside the input finding."""
    return {"bucket": bucket, "action": action, "rule": rule,
            "confidence": float(confidence)}


def _alignment(f: dict) -> list | None:
    """statement_alignment, but ONLY when it is usable evidence: a non-empty
    list whose every element is a dict-shaped entry. Anything else -- key
    missing (pre-D7 run), None (_statement_map's explicit 'structure
    untrusted' value), empty list, non-list, or a corrupted entry inside an
    otherwise-plausible list from a hand-edited index.json -- means 'no
    alignment evidence', and every alignment-gated rule must degrade rather
    than guess. One bad entry poisons the whole map ON PURPOSE: partially
    trusting corrupt evidence is how confident wrong verdicts get made. This
    is the never-KeyError guarantee's front door."""
    a = f.get("statement_alignment")
    return a if isinstance(a, list) and a and all(isinstance(e, dict) for e in a) else None


def _side(entry: dict, which: str) -> dict:
    """One alignment entry's master/client half, defensively. align_statements
    emits None for the absent side of added/removed pairs; a malformed entry
    must degrade to 'empty statement' instead of raising."""
    s = entry.get(which)
    return s if isinstance(s, dict) else {}


def _line_set(alignment: list, which: str) -> set:
    """Set of whitespace-normalized non-blank text lines across ALL entries'
    given side. Equal entries contribute identical lines to both pools and
    cancel out of the difference; removed/changed entries contribute their
    old master lines; that cancellation IS the 'removed-but-reinserted
    identically is not a loss' rule. Lines collapse internal whitespace runs
    and drop blanks: indentation shifts and empty lines carry no SQL
    semantics, and letting them differ would fabricate phantom losses (or
    hide real ones behind noise). Case is preserved -- the risk scan is
    case-insensitive anyway, and case-sensitive sets keep the loss test
    conservative."""
    out = set()
    for entry in alignment:
        text = str(_side(entry, which).get("text") or "")
        for raw in text.splitlines():
            line = " ".join(raw.split())
            if line:
                out.add(line)
    return out


def _is_gated_customization(alignment: list) -> bool:
    """R3's exact shape: every non-equal entry is an ADDED branch whose
    client-side condition references @ClientActive (case-insensitive). One
    changed or removed statement anywhere disqualifies -- that is shared-code
    surgery, not a pure customization addition. At least ONE added entry is
    required: an all-equal alignment vacuously satisfies 'every non-equal
    entry...' but has nothing to wrap, and gate_wrap with zero branches is a
    meaningless action (such findings are caught by R2's no_difference in
    practice; this guard is defense in depth, not the primary path)."""
    deltas = [e for e in alignment if e.get("tag") != "equal"]
    if not deltas:
        return False
    for e in deltas:
        if e.get("tag") != "added":
            return False
        cond = str(_side(e, "client").get("condition") or "")
        if GATE_TOKEN not in cond.lower():
            return False
    return True


def classify_finding(f: dict) -> dict:
    """f = enriched finding dict from pipeline._enrich.

    Returns {"bucket": str, "action": str, "rule": str, "confidence": float}.
    FIRST MATCH WINS down the R1..R6 ladder. Read-only over `f` -- the caller's
    dict is never mutated, ever (detection results are evidence; classifiers do
    not write on evidence)."""
    # R1 -- scope proof outranks everything, including cosmetic: blocks.py only
    # sets irrelevant_to_client when BOTH sides resolved structured AND their
    # relevant-code fingerprints match, i.e. the entire diff provably executes
    # never for this client. `is True` (identity) on purpose: the field is a
    # real bool when present and ABSENT when scoping didn't run -- truthy
    # garbage must not trigger a skip.
    scope = f.get("scope")
    if isinstance(scope, dict) and scope.get("irrelevant_to_client") is True:
        return _verdict("irrelevant_to_client", "skip", "R1_irrelevant_scope", 0.95)

    # R2 -- cosmetic categories skip, visibly counted, never scripted.
    if f.get("category") in COSMETIC_CATEGORIES:
        return _verdict("cosmetic", "skip", "R2_cosmetic_category", 0.99)

    alignment = _alignment(f)

    # R3 -- pure gated-branch additions get the deterministic splice.
    if alignment is not None and _is_gated_customization(alignment):
        return _verdict("gated_customization", "gate_wrap",
                        "R3_gated_customization", 0.85)

    # R4 -- defaults-only parameter change: apply verbatim. Sits BELOW R3 on
    # purpose (a param change plus a gated branch addition is still gated
    # content needing the wrap) and needs no alignment evidence, so stale or
    # missing statement maps degrade cleanly onto this path.
    if f.get("change_kind") == "param":
        return _verdict("small", "apply_asis", "R4_param_small", 0.8)

    # R4b -- additive-only table column change: scriptgen already emits the
    # exact ALTER TABLE ADD from captured column metadata, so this is as
    # deterministic as param changes. Any removal/retype present -> not small.
    if f.get("change_kind") == "column" and f.get("columns_flags"):
        flags = f["columns_flags"]
        if flags.get("added") and not flags.get("removed") and not flags.get("retyped"):
            return _verdict("small", "apply_asis", "R4b_column_additive_small", 0.8)

    # R5 -- small-body screen. Gates first: body-only change WITH alignment
    # evidence AND few enough delta statements to review as a unit. Then the
    # lost-line risk screen; passing it earns apply_asis at lower confidence
    # than R4 (body edits deserve less trust than signature edits), failing it
    # demotes to major -- conservative, documented above at RISK_RES.
    if f.get("change_kind") == "body" and alignment is not None:
        deltas = [e for e in alignment if e.get("tag") in ("changed", "added")]
        if len(deltas) <= MAX_SMALL_DELTAS:
            lost = _line_set(alignment, "master") - _line_set(alignment, "client")
            for line in lost:
                if any(rx.search(line) for rx in RISK_RES):
                    return _verdict("major", "ai_merge", "R5_risk_demote", 0.5)
            return _verdict("small", "apply_asis", "R5_small_body", 0.7)
        # >MAX_SMALL_DELTAS deltas: too big to call small -- fall through.

    # R6 -- everything else. The honest default and deliberately the LOWEST
    # confidence in the module: majors are the human-review short list, and
    # the ladder is designed so surprise landings here are safe landings.
    return _verdict("major", "ai_merge", "R6_default_major", 0.5)


def classify_all(findings: list) -> dict:
    """Classify a whole workspace's findings in input order.

    Returns {"buckets": {bucket: [bare_name, ...]},
             "actions": {name: action},
             "counts":  {bucket: n}} -- counts always mirror the bucket lists
    (counts[b] == len(buckets[b])), and actions is keyed by bare_name for
    direct lookup by the UI/scriptgen layers. bare_name falls back to name
    then "<unnamed>" because pre-enrichment callers may pass raw compare()
    items. Single source of truth: delegates each finding to classify_finding,
    so the two APIs can never disagree. Read-only over the input list."""
    buckets: dict = {}
    actions: dict = {}
    counts: dict = {}
    for item in findings or []:
        v = classify_finding(item) if isinstance(item, dict) else \
            _verdict("major", "ai_merge", "R6_default_major", 0.5)
        name = None
        if isinstance(item, dict):
            name = item.get("bare_name") or item.get("name")
        name = name or "<unnamed>"
        buckets.setdefault(v["bucket"], []).append(name)
        actions[name] = v["action"]
        counts[v["bucket"]] = counts.get(v["bucket"], 0) + 1
    return {"buckets": buckets, "actions": actions, "counts": counts}
