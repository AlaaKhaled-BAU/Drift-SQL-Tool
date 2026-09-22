"""ponytail: minimal self-check, not a framework. Run: python3.13 test_diff_render.py"""
from diff_render import render_rich_diff, render_split_diff, render_column_grid


def _lines(hunk_list):
    """Flatten all non-collapsed line-ops across hunks, for easy assertions."""
    out = []
    for h in hunk_list:
        if not h["collapsed"]:
            out.extend(h["lines"])
    return out


def test_identical_is_all_equal_no_collapse_markers_needed():
    a = "SELECT 1\nSELECT 2\nSELECT 3"
    r = render_rich_diff(a, a)
    assert len(r["hunks"]) == 1 and r["hunks"][0]["collapsed"] is False
    assert all(op["tag"] == "equal" for op in r["hunks"][0]["lines"])


def test_pure_insert():
    a = "SELECT 1"
    b = "SELECT 1\nSELECT 2"
    r = render_rich_diff(a, b)
    tags = [op["tag"] for op in _lines(r["hunks"])]
    assert "insert" in tags and "delete" not in tags, tags


def test_pure_delete():
    a = "SELECT 1\nSELECT 2"
    b = "SELECT 1"
    r = render_rich_diff(a, b)
    tags = [op["tag"] for op in _lines(r["hunks"])]
    assert "delete" in tags and "insert" not in tags, tags


def test_replace_pairs_lines_with_word_level_highlight():
    a = "SET @FromDate = 1"
    b = "SET @FromDate = 2"
    r = render_rich_diff(a, b)
    ops = _lines(r["hunks"])
    assert len(ops) == 1 and ops[0]["tag"] == "replace", ops
    # only the changed token ("1" vs "2") should be marked changed, not the whole line
    m_changed = [w["text"] for w in ops[0]["master_words"] if w["changed"]]
    c_changed = [w["text"] for w in ops[0]["client_words"] if w["changed"]]
    assert m_changed == ["1"] and c_changed == ["2"], (m_changed, c_changed)
    unchanged_master = "".join(w["text"] for w in ops[0]["master_words"] if not w["changed"])
    assert unchanged_master == "SET @FromDate = ", unchanged_master


def test_reordered_independent_statements_is_visibly_flagged_not_silently_equal():
    """Mirrors the real surgical-change #9 test (Rpt_VoidOrder): swapping two
    independent SET lines is a real text difference the tool should show
    clearly, not silently collapse or misrender as unchanged.

    difflib's LCS matcher represents this specific swap as insert+delete
    (it finds one of the two lines is byte-identical content at a new
    position, so there's no per-word "replace" to do on it) rather than two
    replace-pairs -- that's correct, standard diff behavior, not a bug: the
    real requirement is that the reorder is visible, not the exact opcode
    shape SequenceMatcher happens to choose."""
    a = "BEGIN\nset @FromDate = f(@FromDate)\nset @ToDate = f(@ToDate)\nEND"
    b = "BEGIN\nset @ToDate = f(@ToDate)\nset @FromDate = f(@FromDate)\nEND"
    r = render_rich_diff(a, b)
    ops = _lines(r["hunks"])
    tags = [op["tag"] for op in ops]
    # BEGIN/END are truly unchanged; at least one of the two swapped lines
    # must show as insert/delete/replace -- i.e. this must NOT render as
    # "all equal" (which would silently hide a real reorder from a reviewer).
    assert set(tags) != {"equal"}, tags
    assert any(t in ("insert", "delete", "replace") for t in tags), tags


def test_long_unchanged_run_collapses():
    a = "\n".join(f"line{i}" for i in range(50))
    b = a.replace("line25", "LINE25_CHANGED")
    r = render_rich_diff(a, b, context=3)
    collapsed = [h for h in r["hunks"] if h["collapsed"]]
    assert collapsed, "expected at least one collapsed run on a 50-line file with one change"
    assert sum(h["count"] for h in collapsed) > 30


def test_split_diff_pairs_the_changed_line_and_collapses_the_rest():
    """D4 accept criterion: two definitions differing on one line inside 20
    identical lines -- the changed pair must have BOTH left and right
    populated with word-level changed spans, and the unchanged lines must
    collapse (never dumped in full for a split view any more than for
    unified)."""
    lines = [f"SELECT col{i} FROM t" for i in range(20)]
    a = "\n".join(lines)
    b = "\n".join(lines[:10] + ["SELECT col10_RENAMED FROM t"] + lines[11:])
    r = render_split_diff(a, b, context=3)

    rendered = [h for h in r["hunks"] if not h["collapsed"]]
    collapsed = [h for h in r["hunks"] if h["collapsed"]]
    assert collapsed, "expected at least one collapsed run"
    assert sum(h["count"] for h in collapsed) > 10

    replace_rows = [row for h in rendered for row in h["lines"] if row["tag"] == "replace"]
    assert len(replace_rows) == 1, replace_rows
    row = replace_rows[0]
    assert row["left"] is not None and row["right"] is not None
    assert any(w["changed"] for w in row["left"]["words"])
    assert any(w["changed"] for w in row["right"]["words"])


def test_split_diff_pads_none_on_the_side_with_no_counterpart():
    a = "SELECT 1"
    b = "SELECT 1\nSELECT 2"
    r = render_split_diff(a, b)
    rows = [row for h in r["hunks"] if not h["collapsed"] for row in h["lines"]]
    insert_rows = [row for row in rows if row["tag"] == "insert"]
    assert len(insert_rows) == 1
    assert insert_rows[0]["left"] is None
    assert insert_rows[0]["right"] == {"text": "SELECT 2"}


def _col(name, type_, max_length=0, precision=0, scale=0, nullable=True, is_pk=False):
    return {"name": name, "type": type_, "max_length": max_length,
            "precision": precision, "scale": scale, "nullable": nullable, "is_pk": is_pk}


def test_column_grid_marks_added_removed_retyped_same():
    m = [_col("A", "int", is_pk=True, nullable=False), _col("B", "nvarchar", max_length=100), _col("C", "int")]
    c = [_col("A", "int", is_pk=True, nullable=False), _col("B", "nvarchar", max_length=400), _col("D", "int")]
    r = render_column_grid(m, c)
    by_name = {row["name"]: row["status"] for row in r["rows"]}
    assert by_name == {"A": "same", "B": "retyped", "C": "removed", "D": "added"}, by_name


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
