"""ponytail: minimal self-check for the data-loss guard. Run: python3.13 test_scriptgen.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scriptgen  # noqa: E402

# direction is required (D2) -- these existing tests all exercise
# client_to_105 (client_def is the wanted side), preserving their original
# intent; direction-correctness itself is covered by the two
# test_direction_* tests below.
C2_105 = "client_to_105"


def test_only_on_other_never_included_by_default():
    findings = [{"name": "[dbo].[MasterOnlyProc]", "bare_name": "MasterOnlyProc",
                 "type": "SqlProcedure", "role": "only_on_other", "client_def": "CREATE PROCEDURE dbo.X AS SELECT 1"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "MasterOnlyProc" not in r["script"], r["script"]
    assert "CREATE" not in r["script"] and "DROP" not in r["script"]

def test_approved_proc_creates_or_alters():
    findings = [{"name": "[dbo].[Pro_X]", "bare_name": "Pro_X", "type": "SqlProcedure",
                 "role": "modified", "client_def": "CREATE PROCEDURE dbo.Pro_X AS SELECT 1"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "CREATE OR ALTER PROCEDURE dbo.Pro_X" in r["script"], r["script"]

def test_column_drop_never_auto_included():
    findings = [{"name": "[dbo].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
                 "columns": {"added": [], "removed": ["OldCol"], "retyped": []}}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "OldCol" not in r["script"]
    assert any("OldCol" in m["reason"] for m in r["manifest"]["manual_review"])

def test_column_retype_never_auto_included():
    findings = [{"name": "[dbo].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
                 "columns": {"added": [], "removed": [], "retyped": [{"name": "Amount"}]}}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "Amount" not in r["script"]
    assert any("Amount" in m["reason"] for m in r["manifest"]["manual_review"])

def test_added_column_is_safe_to_auto_add():
    col = {"name": "NewCol", "type": "int", "max_length": 4, "precision": 10, "scale": 0, "nullable": True, "is_pk": False}
    findings = [{"name": "[dbo].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
                 "columns": {"added": ["NewCol"], "removed": [], "retyped": []},
                 "client_columns": [col]}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "ALTER TABLE [dbo].[T] ADD [NewCol] int NULL" in r["script"], r["script"]


def test_added_column_uses_schema_from_finding_name():
    col = {"name": "NewCol", "type": "int", "max_length": 4, "precision": 10, "scale": 0, "nullable": True, "is_pk": False}
    findings = [{"name": "[sales].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
                 "columns": {"added": ["NewCol"], "removed": [], "retyped": []},
                 "client_columns": [col]}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "ALTER TABLE [sales].[T] ADD [NewCol] int NULL" in r["script"], r["script"]
    assert "ALTER TABLE [dbo].[T]" not in r["script"]

def test_added_table_without_bundle_stays_manual():
    findings = [{"name": "[dbo].[NewTable]", "bare_name": "NewTable", "type": "SqlTable", "role": "added"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "CREATE TABLE" not in r["script"]
    assert any("NewTable" in m["name"] for m in r["manifest"]["manual_review"])


def test_added_table_with_bundle_emits_create():
    findings = [{
        "name": "[dbo].[NewTable]", "bare_name": "NewTable", "type": "SqlTable", "role": "added",
        "table_bundle": {
            "create_sql": "CREATE TABLE [dbo].[NewTable]([ID] int NOT NULL);",
            "extras": ["CREATE INDEX IX_NewTable ON [dbo].[NewTable]([ID]);"],
        },
    }]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "CREATE TABLE [dbo].[NewTable]" in r["script"]
    assert "IX_NewTable" in r["script"]
    assert not any("NewTable" in m["name"] for m in r["manifest"]["manual_review"])

def test_deletions_stay_off_unless_explicitly_enabled():
    findings = [{"name": "[dbo].[OldProc]", "bare_name": "OldProc", "type": "SqlProcedure",
                 "role": "only_on_other", "master_def": "CREATE PROCEDURE dbo.OldProc AS SELECT 1"}]
    r_off = scriptgen.assemble(findings, "105", C2_105, include_deletions=False)
    assert "DROP" not in r_off["script"]
    r_on = scriptgen.assemble(findings, "105", C2_105, include_deletions=True)
    assert "DROP PROCEDURE [dbo].[OldProc]" in r_on["script"], r_on["script"]

def test_bad_direction_raises():
    try:
        scriptgen.assemble([], "105", "sideways")
        assert False, "expected ValueError"
    except ValueError:
        pass

def test_direction_client_to_105_picks_client_def():
    """D2: the same 'modified' finding, both directions -- client_to_105
    must use the client's (SELECT 2) version."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2"}]
    r = scriptgen.assemble(findings, "105", "client_to_105")
    assert "SELECT 2" in r["script"] and "SELECT 1" not in r["script"], r["script"]

def test_direction_105_to_client_picks_master_def():
    """Same finding, 105_to_client -- must use master's (SELECT 1) version.
    Before D2 this direction always pulled client_def, producing a no-op
    (writing the client's own existing definition back onto itself)."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2"}]
    r = scriptgen.assemble(findings, "105", "105_to_client")
    assert "SELECT 1" in r["script"] and "SELECT 2" not in r["script"], r["script"]

def test_direction_105_to_client_added_role_is_not_manual_review():
    """The entire point of the 105_to_client workspace's 'added' role is
    '105 has this, client is missing it' -- client_def is None there BY
    CONSTRUCTION. Before D2 this always fell to manual_review with
    "definition not captured", so the apply script for this direction was
    effectively always empty for exactly the findings it exists to fix."""
    findings = [{"name": "[dbo].[OnlyOn105]", "bare_name": "OnlyOn105", "type": "SqlProcedure",
                 "role": "added", "master_def": "CREATE PROC OnlyOn105 AS SELECT 1", "client_def": None}]
    r = scriptgen.assemble(findings, "client", "105_to_client")
    assert "CREATE OR ALTER PROC OnlyOn105" in r["script"], r["script"]
    assert not r["manifest"]["manual_review"], r["manifest"]["manual_review"]

def test_create_or_alter_survives_a_leading_comment():
    """D2a: measured 107/1629 (~7%) real definitions begin with a comment
    before CREATE (sys.sql_modules preserves exact batch text). The old
    `startswith("create ")` check silently no-ops on these -- bare CREATE
    against an existing object fails at execution time."""
    findings = [{"name": "[dbo].[Fn]", "bare_name": "Fn", "type": "SqlScalarFunction", "role": "modified",
                 "client_def": "--select [dbo].[Fn] (1)\nCREATE FUNCTION [dbo].[Fn] () RETURNS int AS BEGIN RETURN 1 END"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "CREATE OR ALTER FUNCTION [dbo].[Fn]" in r["script"], r["script"]
    assert "--select [dbo].[Fn] (1)" in r["script"], "leading comment should be preserved, not dropped"

def test_create_or_alter_survives_extra_whitespace():
    """D2a: measured 126 real definitions with CREATE followed by more than
    one space/tab -- happened to survive the old single-space slice by
    accident, confirmed intentionally here so a future change can't
    regress it silently."""
    findings = [{"name": "[dbo].[Fn2]", "bare_name": "Fn2", "type": "SqlScalarFunction", "role": "modified",
                 "client_def": "CREATE  function [dbo].[Fn2] () RETURNS int AS BEGIN RETURN 1 END"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "CREATE OR ALTER" in r["script"], r["script"]
    assert "function [dbo].[Fn2]" in r["script"]

def test_settings_are_emitted_for_the_wanted_side():
    """Follow-up (2026-07-26): a detected ANSI_NULLS/QUOTED_IDENTIFIER
    difference must not be silently lost when the fix is actually applied.
    Uses ansi_nulls=False deliberately -- SQL Server's own default is ON,
    so a test fixture that only ever exercised the default-True value
    could pass even if the code silently ignored `settings` and hardcoded
    ON regardless."""
    findings = [{"name": "[dbo].[Pro_X]", "bare_name": "Pro_X", "type": "SqlProcedure", "role": "modified",
                 "client_def": "CREATE PROCEDURE dbo.Pro_X AS SELECT 1",
                 "client_settings": {"ansi_nulls": False, "quoted_identifier": True}}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SET ANSI_NULLS OFF;" in r["script"], r["script"]
    assert "SET QUOTED_IDENTIFIER ON;" in r["script"], r["script"]
    # settings SET must come before the object, in its own batch (SQL Server requirement)
    assert r["script"].index("SET ANSI_NULLS OFF;") < r["script"].index("CREATE OR ALTER PROCEDURE")

def test_settings_use_the_correct_side_per_direction():
    """Same finding, both directions -- 105_to_client must use
    master_settings (ON), not client_settings (OFF), matching the same
    def_key-by-direction pattern D2 already established."""
    findings = [{"name": "[dbo].[Pro_X]", "bare_name": "Pro_X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROCEDURE dbo.Pro_X AS SELECT 1",
                 "client_def": "CREATE PROCEDURE dbo.Pro_X AS SELECT 1",
                 "master_settings": {"ansi_nulls": True, "quoted_identifier": True},
                 "client_settings": {"ansi_nulls": False, "quoted_identifier": True}}]
    r = scriptgen.assemble(findings, "client", "105_to_client")
    assert "SET ANSI_NULLS ON;" in r["script"], r["script"]
    assert "SET ANSI_NULLS OFF;" not in r["script"]

def test_missing_settings_skips_the_wrapper_without_guessing():
    """No captured settings (e.g. an old disk-reloaded run predating this
    fix) must not fabricate a default -- skip the SET wrapper entirely
    rather than guess ON."""
    findings = [{"name": "[dbo].[Pro_X]", "bare_name": "Pro_X", "type": "SqlProcedure", "role": "modified",
                 "client_def": "CREATE PROCEDURE dbo.Pro_X AS SELECT 1"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SET ANSI_NULLS" not in r["script"], r["script"]
    assert "CREATE OR ALTER PROCEDURE dbo.Pro_X" in r["script"]

def test_script_is_not_silently_atomic():
    """D2b: the generated script must be honest about what it does and
    doesn't guarantee -- XACT_ABORT so a failing batch aborts loudly,
    numbered PRINT progress so a partial run is diagnosable, and an
    explicit non-atomicity warning (GO batches can't share one
    transaction) rather than implying whole-script rollback that isn't
    real."""
    findings = [{"name": "[dbo].[Pro_X]", "bare_name": "Pro_X", "type": "SqlProcedure",
                 "role": "modified", "client_def": "CREATE PROCEDURE dbo.Pro_X AS SELECT 1"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SET XACT_ABORT ON;" in r["script"]
    assert "PRINT N'applying 1/1';" in r["script"]
    assert "NOT ATOMIC" in r["script"]

def test_merged_def_preferred_over_client_def_for_client_to_105():
    """AI-merge feature: an accepted merge proposal (client_def ALREADY
    folded into 105's current body) must win over the raw client_def --
    the whole point is it's not a blind overwrite."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1",
                 "client_def": "CREATE PROC X AS SELECT 2",
                 "merged_def": "CREATE PROC X AS IF @ClientActive = 165 SELECT 2 ELSE SELECT 1"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "IF @ClientActive = 165" in r["script"], r["script"]
    assert r["script"].count("SELECT 2") == 1 and "SELECT 1" in r["script"], r["script"]

def test_merged_def_ignored_for_105_to_client():
    """merged_def is a client_to_105-only concept (105_to_client has no
    merge/wrap notion -- its wanted side is already master_def) -- a
    finding carrying a stray merged_def must not affect this direction."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1",
                 "client_def": "CREATE PROC X AS SELECT 2",
                 "merged_def": "CREATE PROC X AS SELECT 999"}]
    r = scriptgen.assemble(findings, "client", "105_to_client")
    assert "SELECT 1" in r["script"] and "SELECT 999" not in r["script"], r["script"]

def test_no_merged_def_behaves_exactly_as_before():
    """Regression guard: a finding that never went through the AI-merge flow
    (no merged_def key at all) must be byte-identical to pre-change
    behavior -- same fixture/assertion as test_direction_client_to_105_picks_client_def."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SELECT 2" in r["script"] and "SELECT 1" not in r["script"], r["script"]


# ---- PLAN-V5 Lane C: backfill values (C3) + UDTT emission (C8) ----

def test_backfill_quoting_matrix_table_driven():
    """Port of the legacy tool's §8.3 matrix, flaws fixed (no quote-stripping,
    no unvalidated raw interpolation): numeric raw only when strictly numeric,
    strings/datetimes N-quoted with '' doubled, bit from truthy strings,
    unknown types -> None (never guessed)."""
    cases = [
        # numeric family -> RAW
        ("42", "int", "42"),
        ("-7", "bigint", "-7"),
        ("32767", "smallint", "32767"),
        ("255", "tinyint", "255"),
        ("-18.50", "decimal", "-18.50"),
        ("18.4", "numeric", "18.4"),
        ("0", "money", "0"),
        ("3.14", "float", "3.14"),
        ("-0.25", "real", "-0.25"),
        ("+12", "int", "+12"),          # signed form is still a plain number
        ("abc", "int", None),           # non-numeric refused -- never raw-guessed
        ("1; DROP TABLE x--", "int", None),   # injection-shaped value refused
        ("1e5", "float", None),         # exponent form outside the strict matrix -> skip
        # bit -> 1/0 from truthy/falsy strings
        ("1", "bit", "1"),
        ("true", "bit", "1"),
        ("YES", "bit", "1"),
        ("0", "bit", "0"),
        ("False", "bit", "0"),
        ("nO", "bit", "0"),
        ("maybe", "bit", None),         # unknown truthiness never guessed
        # datetime family -> N'...' quoted
        ("2026-01-31", "date", "N'2026-01-31'"),
        ("10:30:00", "time", "N'10:30:00'"),
        ("2026-01-31 10:30:00", "datetime", "N'2026-01-31 10:30:00'"),
        ("2026-01-31 10:30", "smalldatetime", "N'2026-01-31 10:30'"),
        ("2026-01-31T10:30:00", "datetime2", "N'2026-01-31T10:30:00'"),
        # string family + uniqueidentifier -> N'...' with quotes DOUBLED, never stripped
        ("Al'Malak", "varchar", "N'Al''Malak'"),
        ("Al'Malak", "nvarchar", "N'Al''Malak'"),
        ("x", "char", "N'x'"),
        ("x", "nchar", "N'x'"),
        ("x", "text", "N'x'"),
        ("x", "ntext", "N'x'"),
        ("ABCDEF01-2345", "uniqueidentifier", "N'ABCDEF01-2345'"),
        # unknown types -> None (caller skips with a manifest warning)
        ("5", "hierarchyid", None),
        ("5", "sql_variant", None),
        ("x", "", None),
    ]
    for value, sql_type, expected in cases:
        got = scriptgen.quote_backfill_literal(value, sql_type)
        assert got == expected, f"quote_backfill_literal({value!r}, {sql_type!r}): expected {expected!r}, got {got!r}"


def _backfill_table_finding(extra=None):
    cols = [
        {"name": "Flag", "type": "int", "max_length": 4, "precision": 10, "scale": 0, "nullable": True, "is_pk": False},
        {"name": "Note", "type": "nvarchar", "max_length": 20, "precision": 0, "scale": 0, "nullable": True, "is_pk": False},
    ]
    finding = {"name": "[dbo].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
               "columns": {"added": ["Flag", "Note"], "removed": [], "retyped": []},
               "client_columns": cols}
    if extra:
        finding.update(extra)
    return [finding]


def test_backfill_update_emitted_only_for_listed_columns_and_only_after_add():
    r = scriptgen.assemble(_backfill_table_finding({"backfill": {"Flag": "7"}}), "105", C2_105)
    s = r["script"]
    assert s.count("UPDATE ") == 1, s                       # only the listed column gets one
    add_flag = s.index("ALTER TABLE [dbo].[T] ADD [Flag]")
    update = s.index("UPDATE [dbo].[T] SET [Flag] = 7 WHERE [Flag] IS NULL;")
    assert add_flag < update, s                             # AFTER the existing ADD statement
    assert "SET [Note]" not in s, s                         # unlisted column untouched


def test_backfill_where_null_guard_present():
    r = scriptgen.assemble(
        [{"name": "[dbo].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
          "columns": {"added": ["NewCol"], "removed": [], "retyped": []},
          "client_columns": [{"name": "NewCol", "type": "int", "max_length": 4, "precision": 10,
                              "scale": 0, "nullable": True, "is_pk": False}],
          "backfill": {"NewCol": "42"}}], "105", C2_105)
    assert "UPDATE [dbo].[T] SET [NewCol] = 42 WHERE [NewCol] IS NULL;" in r["script"], r["script"]


def test_invalid_backfill_value_warns_and_skips_update():
    r = scriptgen.assemble(_backfill_table_finding({"backfill": {"Flag": "abc"}}), "105", C2_105)
    assert "UPDATE" not in r["script"], r["script"]
    warns = r["manifest"]["backfill_warnings"]
    assert len(warns) == 1 and warns[0]["column"] == "T.Flag" and "abc" in warns[0]["reason"], warns


def test_udtt_added_emits_guarded_create_with_doubled_quotes():
    definition = ("CREATE TYPE [Tvp_X] AS TABLE (\n"
                  "    [Id] int NOT NULL PRIMARY KEY,\n"
                  "    [Label] nvarchar(50) NOT NULL\n"
                  ");")
    findings = [{"name": "[dbo].[Tvp_X]", "bare_name": "Tvp_X", "type": "SqlUserDefinedTableType",
                 "role": "added", "client_def": definition}]
    r = scriptgen.assemble(findings, "105", C2_105)
    s = r["script"]
    guarded = "IF TYPE_ID(N'[dbo].[Tvp_X]') IS NULL EXEC(N'" + definition.replace("'", "''") + "');"
    assert guarded in s, s                                  # verbatim def inside EXEC, quotes doubled
    assert "CREATE OR ALTER TYPE" not in s, s               # types can't ALTER -- guard is the whole point


def test_udtt_modified_lands_manual_review():
    findings = [{"name": "[dbo].[Tvp_X]", "bare_name": "Tvp_X", "type": "SqlUserDefinedTableType",
                 "role": "modified", "client_def": "CREATE TYPE [Tvp_X] AS TABLE ([Id] int NULL);",
                 "master_def": "CREATE TYPE [Tvp_X] AS TABLE ([Id] bigint NULL);"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "TYPE_ID" not in r["script"] and "EXEC(" not in r["script"], r["script"]
    assert any(m["name"] == "[dbo].[Tvp_X]" and m["reason"] == "type modification requires dropping dependents first"
               for m in r["manifest"]["manual_review"]), r["manifest"]["manual_review"]


def test_finding_without_backfill_byte_identical_to_before():
    """A table-modified finding carrying NO backfill key must produce exactly
    what Lane C ran before this change -- full script below is hand-written
    pre-change output for this fixture, asserted byte-for-byte."""
    r = scriptgen.assemble(_backfill_table_finding(), "105", C2_105)
    expected = (
        "-- Apply script for 105, generated by drift-tool.\n"
        "-- Direction: client_to_105.\n"
        "-- ADDITIVE ONLY -- no deletions.\n"
        "-- 2 statement(s) from approved findings. 0 item(s) need manual review (see manifest.json).\n"
        "-- NOT ATOMIC: GO batches cannot share one transaction. XACT_ABORT aborts the CURRENT\n"
        "-- batch loudly on error and the PRINT lines below show exactly how far it got --\n"
        "-- but earlier batches in this script are NOT rolled back. Back up the target first.\n"
        "SET XACT_ABORT ON;\n"
        "SET NOCOUNT ON;\n"
        "PRINT N'applying 1/2';\n"
        "ALTER TABLE [dbo].[T] ADD [Flag] int NULL;\n"
        "PRINT N'applying 2/2';\n"
        "ALTER TABLE [dbo].[T] ADD [Note] nvarchar(10) NULL;\n"
    )
    assert r["script"] == expected, repr(r["script"])
    assert "UPDATE" not in r["script"] and r["manifest"]["backfill_warnings"] == [], r["manifest"]


def test_backfill_without_captured_column_metadata_warns_not_guesses():
    finding = {"name": "[dbo].[T]", "bare_name": "T", "type": "SqlTable", "role": "modified",
               "columns": {"added": ["Ghost"], "removed": [], "retyped": []},
               "client_columns": [],                      # metadata missing on wanted side
               "backfill": {"Ghost": "7"}}
    r = scriptgen.assemble([finding], "105", C2_105)
    assert "ALTER TABLE" not in r["script"] and "UPDATE" not in r["script"], r["script"]
    warns = r["manifest"]["backfill_warnings"]
    assert len(warns) == 1 and warns[0]["column"] == "T.Ghost" and "metadata not captured" in warns[0]["reason"], warns





# NOTE (Lane C): these two B.2a scope tests were stranded BELOW this file's
# original mid-file __main__ block since they were written, so the standalone
# runner never collected them (baseline was 20/20 without them); kept verbatim
# in the same dead position relative to the runner to preserve that behavior.
def test_irrelevant_to_client_skipped_by_default():
    """PLAN-V4 B.2a: scope-flagged findings stay OUT of the apply script
    unless explicitly included -- visible in manifest.skipped_irrelevant_to_client."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2",
                 "scope": {"irrelevant_to_client": True}}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SELECT 2" not in r["script"], r["script"]
    assert r["manifest"]["skipped_irrelevant_to_client"] == ["[dbo].[X]"], r["manifest"]

    r2 = scriptgen.assemble(findings, "105", C2_105, include_irrelevant=True)
    assert "SELECT 2" in r2["script"] and r2["manifest"]["skipped_irrelevant_to_client"] == []


def test_scope_absent_behaves_as_before():
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SELECT 2" in r["script"]
    assert r["manifest"]["skipped_irrelevant_to_client"] == []


def test_irrelevant_to_client_skipped_by_default():
    """PLAN-V4 B.2a: scope-flagged findings stay OUT of the apply script
    unless explicitly included -- visible in manifest.skipped_irrelevant_to_client."""
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2",
                 "scope": {"irrelevant_to_client": True}}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SELECT 2" not in r["script"], r["script"]
    assert r["manifest"]["skipped_irrelevant_to_client"] == ["[dbo].[X]"], r["manifest"]

    r2 = scriptgen.assemble(findings, "105", C2_105, include_irrelevant=True)
    assert "SELECT 2" in r2["script"] and r2["manifest"]["skipped_irrelevant_to_client"] == []


def test_scope_absent_behaves_as_before():
    findings = [{"name": "[dbo].[X]", "bare_name": "X", "type": "SqlProcedure", "role": "modified",
                 "master_def": "CREATE PROC X AS SELECT 1", "client_def": "CREATE PROC X AS SELECT 2"}]
    r = scriptgen.assemble(findings, "105", C2_105)
    assert "SELECT 2" in r["script"]
    assert r["manifest"]["skipped_irrelevant_to_client"] == []


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
