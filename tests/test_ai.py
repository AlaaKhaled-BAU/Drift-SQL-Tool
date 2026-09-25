"""ponytail: minimal self-check, not a framework. Run: python3.13 test_ai.py
JSON-extraction tests moved to test_ai_common.py when extract_json moved to
ai_common.py (shared with ai_merge.py) -- this file keeps only what's
actually still ai.py's own: prompt building."""
from ai import build_prompt, _MAX_DIFF_LINES


def test_build_prompt_includes_diff_and_blast_radius():
    finding = {
        "name": "[dbo].[Rpt_VoidOrder]", "type": "SqlProcedure", "role": "modified",
        "change_kind": "body", "summary": "Body changed.",
        "diff": ["--- a", "+++ b", "-old", "+new"],
        "callers": {"count": 2, "names": ["Rpt_A", "Rpt_B"]},
    }
    p = build_prompt(finding)
    assert "Rpt_VoidOrder" in p and "2 known caller(s)" in p and "Rpt_A" in p, p


def test_build_prompt_truncates_huge_diff():
    finding = {"name": "X", "type": "SqlProcedure", "role": "modified", "change_kind": "body",
               "diff": [f"line{i}" for i in range(_MAX_DIFF_LINES + 50)], "callers": {}}
    p = build_prompt(finding)
    assert "truncated" in p and f"line{_MAX_DIFF_LINES + 49}" not in p, p


def test_build_prompt_uses_columns_when_no_diff():
    finding = {"name": "[dbo].[Banks]", "type": "SqlTable", "role": "modified", "change_kind": "column",
               "columns": {"added": ["X"], "removed": [], "retyped": []}, "callers": {}}
    p = build_prompt(finding)
    assert "Column changes" in p and "added=['X']" in p, p


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
