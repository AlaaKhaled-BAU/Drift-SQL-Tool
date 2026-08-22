"""Standalone battery for classify.py -- PLAN-V4 B.1 rule ladder.
Run: python3.13 test_classify.py   (from the drift/ directory, like
test_scriptgen.py; classify.py is stdlib-only so no package/path setup needed)

Each rule gets a purpose-built fixture; the alignment entries are hand-built
literals in statements.align_statements' output shape ({"tag", "master",
"client"} with {"kind","condition","text"} statement halves), mirroring what
pipeline._enrich stores on real findings -- same fixture philosophy as
test_statements.py without needing the segmenter.
"""
import copy

import classify


# --- fixture builders ---------------------------------------------------------

def _stmt(kind: str = "SELECT", condition=None, text: str = "SELECT 1") -> dict:
    """One statement half, in align_statements() output shape."""
    return {"kind": kind, "condition": condition, "text": text}


def _entry(tag: str, master=None, client=None) -> dict:
    """One alignment entry, in align_statements() output shape."""
    return {"tag": tag, "master": master, "client": client}


def _finding(**over) -> dict:
    """A plausible enriched finding (pipeline._enrich output subset), with a
    benign equal-only alignment so alignment-gated rules have evidence by
    default. Tests override exactly the field under test."""
    f = {"name": "[dbo].[Pro_X]", "bare_name": "Pro_X", "type": "SqlProcedure",
         "role": "modified", "category": "structural", "change_kind": "body",
         "statement_alignment": [_entry("equal", _stmt(), _stmt())]}
    f.update(over)
    return f


# --- R1 -----------------------------------------------------------------------

def test_r1_irrelevant_to_client_fires():
    f = _finding(scope={"client_id": "66", "irrelevant_to_client": True})
    r = classify.classify_finding(f)
    assert r["bucket"] == "irrelevant_to_client" and r["action"] == "skip", r
    assert r["rule"] == "R1_irrelevant_scope" and r["confidence"] == 0.95, r


def test_r1_beats_r2_when_both_true():
    """Ordering pin: a finding can be BOTH scope-irrelevant AND cosmetic
    (comment-only drift inside another client's gated branch). R1 must win --
    the audit trail should say WHY it skips (scope proof), not just 'cosmetic'."""
    f = _finding(category="formatting_only",
                 scope={"client_id": "66", "irrelevant_to_client": True})
    r = classify.classify_finding(f)
    assert r["bucket"] == "irrelevant_to_client" and r["rule"] == "R1_irrelevant_scope", r


def test_scope_false_or_absent_never_skips():
    """`is True` identity guard: pipeline only sets irrelevant_to_client when
    both fingerprints resolved; False and absent must fall through to normal
    rules, never skip."""
    r = classify.classify_finding(_finding(change_kind="param"))
    assert r["bucket"] == "small", r
    r2 = classify.classify_finding(
        _finding(change_kind="param", scope={"irrelevant_to_client": False}))
    assert r2["bucket"] == "small", r2


# --- R2 -----------------------------------------------------------------------

def test_r2_cosmetic_categories_fire():
    """All three cosmetic categories skip at 0.99 -- formatting_only,
    no_difference (D1 demotion), documentation."""
    for cat in ("formatting_only", "no_difference", "documentation"):
        r = classify.classify_finding(_finding(category=cat))
        assert r["bucket"] == "cosmetic" and r["action"] == "skip", (cat, r)
        assert r["rule"] == "R2_cosmetic_category" and r["confidence"] == 0.99, (cat, r)


# --- R3 -----------------------------------------------------------------------

def test_r3_gated_added_branch_fires():
    """The P3 shape from the parallel-test results: body change consisting
    ONLY of an added IF @ClientActive branch -> gate_wrap, even though
    change_kind says 'body' (R3 outranks R5 by ladder order)."""
    f = _finding(statement_alignment=[
        _entry("equal", _stmt(), _stmt()),
        _entry("added", None,
               {"kind": "IF", "condition": "@ClientActive = 66",
                "text": "IF @ClientActive = 66 BEGIN SELECT 1 END"}),
    ])
    r = classify.classify_finding(f)
    assert r["bucket"] == "gated_customization" and r["action"] == "gate_wrap", r
    assert r["rule"] == "R3_gated_customization" and r["confidence"] == 0.85, r


def test_r3_condition_match_is_case_insensitive():
    """Real dumps write the gate lowercase ('if @clientactive = 66 begin...');
    the token match must not care."""
    f = _finding(statement_alignment=[
        _entry("added", None,
               {"kind": "IF", "condition": "if @CLIENTACTIVE=66",
                "text": "if @CLIENTACTIVE=66 BEGIN SELECT 1 END"}),
    ])
    assert classify.classify_finding(f)["bucket"] == "gated_customization"


def test_r3_rejects_ungated_addition_and_changed_entry():
    """Two disqualifiers: (a) an added branch gating on some OTHER variable is
    shared-code drift, not this client's customization; (b) any changed entry
    means shared code was edited -- splice-up must not touch it. Both fall
    through the ladder (change_kind=None here keeps them clear of R4/R5 so
    they land on the honest R6 default)."""
    ungated = _finding(change_kind=None, statement_alignment=[
        _entry("added", None,
               {"kind": "IF", "condition": "@CompanyActive = 7",
                "text": "IF @CompanyActive = 7 BEGIN SELECT 1 END"})])
    r = classify.classify_finding(ungated)
    assert r["bucket"] == "major" and r["rule"] == "R6_default_major", r

    changed = _finding(change_kind=None, statement_alignment=[
        _entry("changed", _stmt(), _stmt("IF", "@ClientActive = 66"))])
    r2 = classify.classify_finding(changed)
    assert r2["bucket"] == "major" and r2["rule"] == "R6_default_major", r2


# --- R4 -----------------------------------------------------------------------

def test_r4_param_path_degrades_without_alignment():
    """Param-only changes apply as-is at 0.8 -- and must do so even when NO
    statement map exists (missing key entirely): missing/stale alignment
    degrades gracefully onto the param path, never KeyError."""
    f = _finding(change_kind="param")
    del f["statement_alignment"]
    r = classify.classify_finding(f)
    assert r["bucket"] == "small" and r["action"] == "apply_asis", r
    assert r["rule"] == "R4_param_small" and r["confidence"] == 0.8, r


# --- R5 -----------------------------------------------------------------------

def test_r5_small_body_passes_with_benign_lost_line():
    """Two changed statements swapping constants; the old constant line is
    'lost' but carries no risk token -> small/apply_asis at 0.7. Proves a
    benign removal passes the screen rather than being banned outright."""
    f = _finding(statement_alignment=[
        _entry("changed", _stmt(text="SELECT @A = 1"), _stmt(text="SELECT @A = 11")),
        _entry("changed", _stmt(text="SELECT @B = 2"), _stmt(text="SELECT @B = 22")),
    ])
    r = classify.classify_finding(f)
    assert r["bucket"] == "small" and r["rule"] == "R5_small_body", r
    assert r["action"] == "apply_asis" and r["confidence"] == 0.7, r


def test_r5_risk_line_demotes_to_major():
    """The conservative-demote contract: losing a WHERE-carrying master line
    (a removed DELETE...WHERE nobody reinserted) demotes R5 to major/ai_merge
    -- other clients sharing this proc would lose that filtering too."""
    f = _finding(statement_alignment=[
        _entry("equal", _stmt(), _stmt()),
        _entry("removed", _stmt(kind="DELETE", text="DELETE FROM T WHERE X = 1"), None),
    ])
    r = classify.classify_finding(f)
    assert r["bucket"] == "major" and r["action"] == "ai_merge", r
    assert r["rule"] == "R5_risk_demote" and r["confidence"] == 0.5, r


def test_r5_removed_but_reinserted_identical_is_not_risk():
    """Set-semantics pin: the same 'WHERE X = 1' line exists in a KEPT
    statement's client text, so the removed copy is NOT lost -- line-set
    difference across ALL entries, not per-entry paranoia. Contrast twin at
    the end removes the reinsertion and must demote, proving the screen sees
    the difference between the two worlds. (The removed statement's OTHER
    line is deliberately benign -- a lost DELETE/UPDATE token would demote
    regardless of the WHERE question this test exists to answer.)"""
    kept = _stmt(text="SELECT 1\nFROM T\nWHERE X = 1")

    def build(with_reinsertion: bool):
        kept_side = kept if with_reinsertion else _stmt(text="SELECT 1\nFROM T")
        return [_entry("equal", kept_side, kept_side),
                _entry("removed", _stmt(text="SELECT 2\nWHERE X = 1"), None)]

    r_ok = classify.classify_finding(_finding(statement_alignment=build(True)))
    assert r_ok["bucket"] == "small" and r_ok["rule"] == "R5_small_body", r_ok
    r_bad = classify.classify_finding(_finding(statement_alignment=build(False)))
    assert r_bad["bucket"] == "major" and r_bad["rule"] == "R5_risk_demote", r_bad


def test_r5_more_than_three_changed_demotes_to_default_major():
    """Smallness ceiling: four delta statements is beyond review-as-a-unit;
    must bypass R5 entirely and land on the honest R6 default (not the risk
    demotion -- it never entered the screen)."""
    f = _finding(statement_alignment=[
        _entry("changed", _stmt(text=f"SELECT @V = {i}"),
               _stmt(text=f"SELECT @V = {i}0"))
        for i in range(4)])
    r = classify.classify_finding(f)
    assert r["bucket"] == "major" and r["rule"] == "R6_default_major", r


# --- degradation ---------------------------------------------------------------

def test_missing_or_stale_alignment_degrades_gracefully():
    """The never-KeyError guarantee: absent key, None (_statement_map's
    explicit untrusted marker), empty list, and corrupted non-list all mean
    'no alignment evidence' -- a body finding with none of them must reach
    the R6 default without raising, never fabricate small/gated verdicts."""
    for broken in ("absent", None, [], ["not-a-dict"], "garbage"):
        f = _finding()
        if broken == "absent":
            del f["statement_alignment"]
        else:
            f["statement_alignment"] = broken
        r = classify.classify_finding(f)
        assert r["bucket"] == "major" and r["rule"] == "R6_default_major", (broken, r)


# --- batch API + purity --------------------------------------------------------

def test_classify_all_shape_counts_and_actions_consistent():
    findings = [
        _finding(name="[dbo].[Irrel]", bare_name="Irrel",
                 scope={"irrelevant_to_client": True}),
        _finding(name="[dbo].[Fmt]", bare_name="Fmt", category="formatting_only"),
        _finding(name="[dbo].[Gated]", bare_name="Gated", statement_alignment=[
            _entry("added", None, _stmt("IF", "@ClientActive = 66"))]),
        _finding(name="[dbo].[Param]", bare_name="Param", change_kind="param"),
        _finding(name="[dbo].[Risk]", bare_name="Risk", statement_alignment=[
            _entry("removed", _stmt(text="UPDATE T SET A = 1"), None)]),
        _finding(name="[dbo].[Big]", bare_name="Big", statement_alignment=[
            _entry("changed", _stmt(text=f"S{i}"), _stmt(text=f"T{i}"))
            for i in range(9)]),
    ]
    r = classify.classify_all(findings)
    assert r["buckets"]["irrelevant_to_client"] == ["Irrel"], r
    assert r["buckets"]["cosmetic"] == ["Fmt"], r
    assert r["buckets"]["gated_customization"] == ["Gated"], r
    assert r["buckets"]["small"] == ["Param"], r
    assert sorted(r["buckets"]["major"]) == ["Big", "Risk"], r
    # counts mirror bucket lists exactly
    assert set(r["counts"]) == set(r["buckets"]), r
    assert all(r["counts"][b] == len(names) for b, names in r["buckets"].items()), r
    assert sum(r["counts"].values()) == len(findings), r
    # actions keyed by bare name, matching each bucket's known action
    assert r["actions"]["Irrel"] == "skip" and r["actions"]["Fmt"] == "skip"
    assert r["actions"]["Gated"] == "gate_wrap"
    assert r["actions"]["Param"] == "apply_asis"
    assert r["actions"]["Risk"] == "ai_merge" and r["actions"]["Big"] == "ai_merge"
    # empty input degrades to the empty contract shape, not an error
    assert classify.classify_all([]) == {"buckets": {}, "actions": {}, "counts": {}}


def test_classification_never_mutates_input():
    """CRITICAL contract: detection results are evidence; classifiers do not
    write on evidence. Deep-snapshot before, deep-compare after, for BOTH the
    single-finding and batch APIs."""
    f = _finding(statement_alignment=[
        _entry("changed", _stmt(), _stmt()),
        _entry("removed", _stmt(kind="DELETE", text="DELETE FROM T WHERE X = 1"), None),
    ], scope={"client_id": "66", "irrelevant_to_client": False})
    snapshot_f = copy.deepcopy(f)
    classify.classify_finding(f)
    assert f == snapshot_f, "classify_finding mutated its input"

    lst = [f, _finding(name="[dbo].[P]", bare_name="P", change_kind="param")]
    snapshot_lst = copy.deepcopy(lst)
    classify.classify_all(lst)
    assert lst == snapshot_lst, "classify_all mutated its input"


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
