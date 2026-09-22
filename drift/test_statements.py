"""D7: statement-level change map. ponytail: run standalone --
python3.13 test_statements.py. statements.py uses package-relative imports
(same situation as pipeline.py/compare.py -- see their own test files'
docstrings), so this needs drift-tool/ on sys.path and the `drift` package.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import statements  # noqa: E402


def _proc(body: str) -> str:
    return f"CREATE PROCEDURE dbo.Test\nAS\nBEGIN\n{body}\nEND"


def test_one_inserted_statement_at_top_is_exactly_one_added():
    """THE anti-regression test for the positional-comparison failure mode
    (the whole reason this module aligns by content, not position): a
    single inserted statement must show as exactly one `added`, never N
    cascading `changed` entries."""
    master = _proc("SELECT 2\nSELECT 3\nSELECT 4")
    client = _proc("SELECT 1\nSELECT 2\nSELECT 3\nSELECT 4")
    m, c = statements.parse_statements(master), statements.parse_statements(client)
    assert m["ok"] and c["ok"]
    tags = [a["tag"] for a in statements.align_statements(m["statements"], c["statements"])]
    assert tags == ["added", "equal", "equal", "equal"], tags


def test_added_if_branch_reports_condition():
    """The single highest-value sentence this tool can produce, per the
    plan: "a new IF @ClientActive = 165 branch was added"."""
    master = _proc("SELECT 1")
    client = _proc("SELECT 1\nIF @ClientActive = 165\nBEGIN\n    UPDATE T SET A = 1\nEND")
    m, c = statements.parse_statements(master), statements.parse_statements(client)
    assert m["ok"] and c["ok"]
    aligned = statements.align_statements(m["statements"], c["statements"])
    added = [a for a in aligned if a["tag"] == "added"]
    assert len(added) == 1, aligned
    assert added[0]["client"]["kind"] == "IF"
    assert added[0]["client"]["condition"] == "@ClientActive = 165"


def test_if_else_both_branches_stay_one_statement_not_fragmented():
    """Neither branch's closing END is followed by a semicolon -- normal
    T-SQL style, not an edge case. Measured live: sqlglot's OWN top-level
    parse.raises outright on exactly this shape (see module docstring) --
    this module's own segmenter must not."""
    definition = _proc(
        "SELECT 1 AS X\n"
        "IF @ClientActive = 165\n"
        "BEGIN\n"
        "    UPDATE T SET A = 1 WHERE B = 2\n"
        "END\n"
        "ELSE\n"
        "BEGIN\n"
        "    DELETE FROM T WHERE B = 3\n"
        "END\n"
        "EXEC dbo.SomeProc @P1 = 1"
    )
    r = statements.parse_statements(definition)
    assert r["ok"], r["reason"]
    kinds = [s["kind"] for s in r["statements"]]
    assert kinds == ["SELECT", "IF", "EXEC"], kinds
    assert r["statements"][1]["condition"] == "@ClientActive = 165"


def test_case_expression_end_is_not_mistaken_for_a_block_end():
    """Real bug found live against db/Olives_BO.sql: CASE WHEN...END is a
    scalar expression, not a BEGIN...END block, but closes with the same
    END keyword -- without tracking CASE as its own opener sharing the
    depth counter, this END was miscounted as closing the proc's outer
    BEGIN, corrupting segmentation for every proc containing a CASE
    expression anywhere (i.e. most real procs)."""
    definition = _proc(
        "SELECT @ExRate = 1 / CASE WHEN IsNull(X, 0) = 0 THEN 1 ELSE IsNull(X, @ExRate) END\n"
        "FROM T\n"
        "WHERE Y = 1"
    )
    r = statements.parse_statements(definition)
    assert r["ok"], r["reason"]
    assert len(r["statements"]) == 1
    assert r["statements"][0]["kind"] == "SELECT"


def test_begin_transaction_is_not_mistaken_for_a_block_opener():
    """Real bug found live: BEGIN TRANSACTION was counted as a real nested
    block by ONE of the two places that needed to recognize the "BEGIN
    TRAN[SACTION] is a statement" exception (they used to be two hand-
    copied checks; only one was ever updated), unbalancing BEGIN/END and
    silently defeating the outer-wrapper strip for every proc using
    explicit transactions."""
    definition = _proc(
        "DECLARE @HaveError int\n"
        "SET @HaveError = 0\n"
        "BEGIN TRANSACTION\n"
        "UPDATE T SET A = 1\n"
        "IF (@@ERROR <> 0)\n"
        "BEGIN\n"
        "    SET @HaveError = 1\n"
        "END\n"
        "COMMIT TRANSACTION"
    )
    r = statements.parse_statements(definition)
    assert r["ok"], r["reason"]
    kinds = [s["kind"] for s in r["statements"]]
    assert kinds == ["DECLARE", "SET", "OTHER", "UPDATE", "IF", "OTHER"], kinds


def test_cursor_proc_from_the_real_dump_is_ok_false():
    """Accept criterion #3: a CURSOR-containing proc must be ok=False with
    a truthful reason, never a crash and never a false "no changes".
    Real proc from db/Olives_BO.sql (shortest CURSOR-using example found
    scanning the whole file) -- kept verbatim, not simplified, so this
    test exercises the actual real-world shape."""
    real_proc = """CREATE Procedure [dbo].[copdevicereportsPermissions_ByRange]
 @COMPNNO int,
 @FromSalesman int,
 @toSalesman int
as
BEgin


DECLARE @SALESMANNO INT
DECLARE cursor_name CURSOR FOR
SELECT  PositionID
FROM SALESPERSONS
WHERE CompanyID=@COMPNNO AND ID BETWEEN @FromSalesman AND @toSalesman

OPEN cursor_name;
FETCH NEXT FROM cursor_name INTO @SALESMANNO

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC TechnicalSupportTools_CopyReportsfornewSalesman 2,@FromSalesman,@toSalesman

    FETCH NEXT FROM cursor_name INTO @SALESMANNO;
END

CLOSE cursor_name;
DEALLOCATE cursor_name;

END"""
    r = statements.parse_statements(real_proc)
    assert r["ok"] is False
    assert "CURSOR" in r["reason"]
    assert r["statements"] == []


def test_unrecognized_vocabulary_is_ok_false_not_a_false_no_changes():
    """Accept criterion #4's spirit, adapted to what measurement actually
    showed (see module docstring): the plan's original framing was "sqlglot
    degrades the WHOLE body to exp.Command -> ok=False". Measured live:
    gating on sqlglot's own top-level parse of the whole body made `ok`
    fire far more often than warranted (it raises outright on ordinary
    semicolon-optional IF/ELSE style -- worse than the plan's own measured
    7% exception rate). So `ok` here reflects whether THIS module's own
    segmentation recognized ANYTHING, not sqlglot's raw parse -- a body
    where every segment falls outside this module's statement vocabulary
    is the direct analog of the old "opaque Command" signal."""
    definition = _proc("PRINT 'diagnostic only, nothing else in this body'")
    r = statements.parse_statements(definition)
    assert r["ok"] is False
    assert "recognized statement type" in r["reason"]


def test_measured_ok_rate_against_100_real_procedures():
    """Not a pass/fail gate on the exact number (real data drifts) -- this
    documents and protects the measured baseline. Report the number
    honestly; see VALIDATION.md for the actual reported figure and full
    failure breakdown. Skips gracefully if the real dump isn't present
    (e.g. a checkout without db/Olives_BO.sql)."""
    import re
    sql_path = Path(__file__).resolve().parents[2] / "db" / "Olives_BO.sql"
    if not sql_path.is_file():
        print("  (skipped: db/Olives_BO.sql not present)")
        return
    text = sql_path.read_text(encoding="utf-8-sig")
    batches = re.split(r"(?m)^GO\s*$", text)
    procs = [b.strip() for b in batches
             if re.match(r"(?i)^\s*(create|create\s+or\s+alter)\s+procedure", b.strip())]
    sample = procs[:100]
    ok_count = sum(1 for p in sample if statements.parse_statements(p)["ok"])
    rate = 100 * ok_count / len(sample)
    print(f"  measured: {ok_count}/{len(sample)} ok ({rate:.0f}%) -- see VALIDATION.md")
    assert rate >= 64.5, f"regressed below the plan's own measured baseline: {rate:.1f}%"


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
