"""ponytail: minimal self-check for D6's additive priority score -- the one
part of report_writer.py with genuinely new logic (this file didn't exist
before D6). Run: python3.13 test_report_writer.py

report_writer.py uses package-relative imports (`from . import compare`),
same situation as pipeline.py/compare.py -- needs drift-tool/ on sys.path."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.report_writer import _priority_bucket, _priority_score  # noqa: E402


def _finding(**overrides):
    base = {"type": "SqlProcedure", "category": "structural", "change_kind": None,
            "callers": {"count": 0}, "attribution": [], "columns": None}
    base.update(overrides)
    return base


def test_no_signals_scores_zero_and_low():
    score, hits = _priority_score(_finding())
    assert score == 0 and hits == []
    assert _priority_bucket(score) == "low"


def test_column_removed_scores_40():
    score, hits = _priority_score(_finding(columns={"removed": ["X"], "retyped": []}))
    assert score == 40
    assert hits == [("column removed or retyped", 40)]


def test_column_retyped_also_scores_40():
    score, _ = _priority_score(_finding(columns={"removed": [], "retyped": [{"name": "X"}]}))
    assert score == 40


def test_signature_change_scores_30():
    for kind in ("param", "both"):
        score, _ = _priority_score(_finding(change_kind=kind))
        assert score == 30, kind


def test_body_only_change_scores_nothing_for_this_signal():
    score, _ = _priority_score(_finding(change_kind="body"))
    assert score == 0


def test_caller_count_thresholds():
    assert _priority_score(_finding(callers={"count": 6}))[0] == 25
    assert _priority_score(_finding(callers={"count": 1}))[0] == 10
    assert _priority_score(_finding(callers={"count": 5}))[0] == 10  # exactly 5 is the "1-5" band, not ">5"
    assert _priority_score(_finding(callers={"count": 0}))[0] == 0


def test_settings_change_scores_20():
    score, _ = _priority_score(_finding(change_kind="settings"))
    assert score == 20


def test_attribution_scores_15():
    score, _ = _priority_score(_finding(attribution=[{"login": "x"}]))
    assert score == 15


def test_table_or_constraint_type_scores_10():
    assert _priority_score(_finding(type="SqlTable"))[0] == 10
    assert _priority_score(_finding(type="SqlForeignKeyConstraint"))[0] == 10
    assert _priority_score(_finding(type="SqlView"))[0] == 0, "a view is not a table or constraint"


def test_formatting_only_and_no_difference_are_negative():
    assert _priority_score(_finding(category="formatting_only"))[0] == -30
    assert _priority_score(_finding(category="no_difference"))[0] == -50


def test_signals_stack_additively():
    f = _finding(type="SqlTable", callers={"count": 63}, columns={"removed": [], "retyped": []})
    score, hits = _priority_score(f)
    assert score == 25 + 10  # caller>5 + table
    assert len(hits) == 2


def test_bucket_thresholds_tuned_against_real_battery():
    """Tuned against the real morec_original vs morec_surgical_v2 battery --
    see VALIDATION.md. >=20 high / >=10 medium / else low, not the plan's
    literal starting >=50/>=20 (which put 0% of that real run in "high")."""
    assert _priority_bucket(20) == "high"
    assert _priority_bucket(19) == "medium"
    assert _priority_bucket(10) == "medium"
    assert _priority_bucket(9) == "low"
    assert _priority_bucket(0) == "low"
    assert _priority_bucket(-30) == "low"


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
