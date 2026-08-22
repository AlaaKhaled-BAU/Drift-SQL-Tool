"""Self-check for preflight.py (PLAN-V4 B.3) -- fake-cursor harness, no live DB.

find_column_dependencies() issues its catalog queries in a FIXED documented
order; this harness scripts one fetchall() result sequence per execute call
and pops them in exactly that order. The assumed order (kept in lockstep with
the docstring in preflight.py -- change either side together):
    call 1: defaults   (sys.default_constraints)
    call 2: checks     (sys.check_constraints)
    call 3: fks        (sys.foreign_keys, both FK roles UNIONed)
    call 4: stats      (sys.stats + stats_columns)
    call 5: computed   (sys.computed_columns)
    call 6: indexes    (sys.indexes + index_columns + tables + columns)

Covered here: table/column names reach SQL only as %s bind params (house
security rule); deps dict populated from scripted rows; plan phases strictly
teardown -> alter -> rebuild; recreation SQL byte-equal to the captured
definitions; missing captured detail lands in warnings, never fabricated SQL.
Run: python3.13 test_preflight.py
"""
import sys
from pathlib import Path

# preflight.py is import-clean (no sibling imports) but we use the same
# sys.path/package pattern as test_inspect_objects.py so the suite runs
# identically from any working directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import preflight  # noqa: E402

TABLE = "T"
COLUMN = "A"
ALTER_STMT = "ALTER TABLE [T] ALTER COLUMN [A] nvarchar(200);"


class _ScriptedCursor:
    """Records every execute(sql, params); each fetchall() consumes the next
    scripted sequence, in preflight's documented six-query call order."""

    def __init__(self, sequences):
        self.sequences = list(sequences)
        self.calls = []  # list of (sql, params)

    def execute(self, sql, params=None):
        self.calls.append((sql, params))

    def fetchall(self):
        return self.sequences.pop(0) if self.sequences else []


def _full_deps_cursor():
    """One column with the full dependency set: default + check + FK + stat +
    two indexes (a clustered PK and a unique filtered nonclustered index)."""
    return _ScriptedCursor([
        [{"name": "DF_T_A", "definition": "((0))"}],
        [{"name": "CK_T_A", "definition": "([A]>(0))"}],
        [{"name": "FK_Other_T"}],
        [{"name": "_WA_Sys_00000001_A"}],
        [],  # computed
        [
            {"name": "PK_T", "is_unique": 1, "is_primary_key": 1, "type_desc": "CLUSTERED",
             "filter_definition": None, "col_name": "A", "is_descending_key": 0,
             "is_included_column": 0},
            {"name": "IX_T_A", "is_unique": 1, "is_primary_key": 0, "type_desc": "NONCLUSTERED",
             "filter_definition": "([A] > 0)", "col_name": "A", "is_descending_key": 0,
             "is_included_column": 0},
        ],
    ])


def test_params_bound_as_scalars_never_interpolated():
    # House security rule: hostile identifiers must appear in the params tuple,
    # NEVER in the SQL text. An interpolated quote/semicolon payload would
    # break out of the identifier context entirely.
    hostile_col = "A'); DROP TABLE zz; --"
    cur = _full_deps_cursor()
    preflight.find_column_dependencies(cur, TABLE, hostile_col)
    assert len(cur.calls) == 6, "query-call order drifted from the documented six queries"
    for sql, params in cur.calls:
        assert hostile_col not in sql, f"identifier interpolated into SQL text: {sql}"
        assert params[0] == TABLE and params[1] == hostile_col


def test_deps_populated_from_scripted_catalog():
    cur = _full_deps_cursor()
    deps = preflight.find_column_dependencies(cur, TABLE, COLUMN)
    assert deps["defaults"] == [{"name": "DF_T_A", "definition": "((0))"}]
    assert deps["checks"] == [{"name": "CK_T_A", "definition": "([A]>(0))"}]
    assert deps["fks"] == [{"name": "FK_Other_T"}]
    assert deps["stats"] == [{"name": "_WA_Sys_00000001_A"}]
    assert deps["computed"] is False
    ix = {i["name"]: i for i in deps["indexes"]}
    assert ix["PK_T"]["is_primary_key"] is True and ix["PK_T"]["type_desc"] == "CLUSTERED"
    assert ix["PK_T"]["key_cols"] == [("A", "ASC")]
    assert ix["IX_T_A"]["is_unique"] is True and ix["IX_T_A"]["filter"] == "([A] > 0)"


def test_plan_phases_strictly_teardown_alter_rebuild():
    deps = preflight.find_column_dependencies(_full_deps_cursor(), TABLE, COLUMN)
    plan = preflight.build_column_alter_plan(TABLE, COLUMN, ALTER_STMT, deps)
    phases = [s["phase"] for s in plan["steps"]]
    n_teardown = phases.index("alter")
    assert phases == ["teardown"] * n_teardown + ["alter"] + \
        ["rebuild"] * (len(phases) - n_teardown - 1), phases
    # the alter step is the caller's statement VERBATIM -- no reformatting
    assert plan["steps"][n_teardown]["sql"] == ALTER_STMT
    # stats refresh is always last: it regenerates what teardown dropped
    assert plan["steps"][-1]["sql"] == f"UPDATE STATISTICS [{TABLE}];"
    # teardown order: constraints -> stats -> fks -> indexes
    teardown_sql = [s["sql"] for s in plan["steps"][:n_teardown]]
    assert teardown_sql == [
        f"ALTER TABLE [{TABLE}] DROP CONSTRAINT [DF_T_A];",
        f"ALTER TABLE [{TABLE}] DROP CONSTRAINT [CK_T_A];",
        f"DROP STATISTICS [{TABLE}].[_WA_Sys_00000001_A];",
        f"ALTER TABLE [{TABLE}] DROP CONSTRAINT [FK_Other_T];",  # dropped by design...
        f"ALTER TABLE [{TABLE}] DROP CONSTRAINT [PK_T];",
        f"DROP INDEX [IX_T_A] ON [{TABLE}];",
    ]
    # ...with the must-re-add warning, since only its NAME was captured
    assert any("FK_Other_T" in w for w in plan["warnings"]), plan["warnings"]


def test_recreation_sql_byte_equal_to_captured_definitions():
    deps = preflight.find_column_dependencies(_full_deps_cursor(), TABLE, COLUMN)
    plan = preflight.build_column_alter_plan(TABLE, COLUMN, ALTER_STMT, deps)
    rebuild_sql = [s["sql"] for s in plan["steps"] if s["phase"] == "rebuild"]
    expected = [
        # PK constraint rebuilt from captured name/type/key columns
        f"ALTER TABLE [{TABLE}] ADD CONSTRAINT [PK_T] PRIMARY KEY CLUSTERED ([A] ASC);",
        # unique filtered index rebuilt from captured cols + filter text verbatim
        f"CREATE UNIQUE NONCLUSTERED INDEX [IX_T_A] ON [{TABLE}] ([A] ASC) WHERE ([A] > 0);",
        # default/check rebuilt around the engine's own expression text, unmodified
        f"ALTER TABLE [{TABLE}] ADD CONSTRAINT [DF_T_A] DEFAULT ((0)) FOR [A];",
        f"ALTER TABLE [{TABLE}] ADD CONSTRAINT [CK_T_A] CHECK ([A]>(0));",
        f"UPDATE STATISTICS [{TABLE}];",
    ]
    assert rebuild_sql == expected, rebuild_sql
    # determinism: identical inputs -> byte-identical plan, twice
    plan2 = preflight.build_column_alter_plan(TABLE, COLUMN, ALTER_STMT, deps)
    assert plan == plan2


def test_missing_definitions_land_warnings_not_fabricated_sql():
    # Policy under test: an object we CANNOT recreate verbatim is never
    # dropped-and-lost silently nor recreated from guessed SQL -- it is left
    # untouched with an explicit warning (the executor's benign classes catch
    # the resulting dependent error at run time instead).
    cur = _ScriptedCursor([
        [{"name": "DF_bad", "definition": None}],          # no captured definition
        [{"name": "CK_bad", "definition": ""}],            # empty captured definition
        [{"name": "FK_x"}],                                # FKs never carry definitions
        [],
        [],
        [
            {"name": None, "is_unique": 0, "is_primary_key": 0, "type_desc": None,
             "filter_definition": None, "col_name": None, "is_descending_key": 0,
             "is_included_column": 0},                     # unnamed index row
            {"name": "IX_nocols", "is_unique": 0, "is_primary_key": 0,
             "type_desc": "NONCLUSTERED", "filter_definition": None, "col_name": None,
             "is_descending_key": 0, "is_included_column": 0},  # no key columns captured
        ],
    ])
    deps = preflight.find_column_dependencies(cur, TABLE, COLUMN)
    plan = preflight.build_column_alter_plan(TABLE, COLUMN, ALTER_STMT, deps)
    all_sql = [s["sql"] for s in plan["steps"]]
    joined = "\n".join(all_sql)
    for bad in ("[DF_bad]", "[CK_bad]", "[IX_nocols]", "CREATE INDEX"):
        assert bad not in joined, f"fabricated SQL for uncapturable object: {bad}"
    warnings_joined = " ".join(plan["warnings"])
    for token in ("DF_bad", "CK_bad", "IX_nocols"):
        assert token in warnings_joined, f"missing warning for {token}"
    assert any("unnamed index" in w for w in plan["warnings"])
    # the FK IS dropped (required for the alter to proceed) but flagged loudly
    assert f"ALTER TABLE [{TABLE}] DROP CONSTRAINT [FK_x];" in all_sql
    assert any("FK_x" in w and "NOT be recreated" in w for w in plan["warnings"])
    # phase discipline survives even the degraded path
    phases = [s["phase"] for s in plan["steps"]]
    assert phases == ["teardown"] * phases.index("alter") + ["alter"] + \
        ["rebuild"] * (len(phases) - phases.index("alter") - 1), phases


def test_computed_column_warns_but_plan_still_emitted():
    cur = _ScriptedCursor([[], [], [], [], [{"name": COLUMN}], []])
    deps = preflight.find_column_dependencies(cur, TABLE, COLUMN)
    assert deps["computed"] is True
    plan = preflight.build_column_alter_plan(TABLE, COLUMN, ALTER_STMT, deps)
    assert any("COMPUTED" in w for w in plan["warnings"]), plan["warnings"]
    # plan still emitted so the caller sees the full picture; executor will
    # surface the engine's refusal as a fatal at run time.
    assert any(s["phase"] == "alter" and s["sql"] == ALTER_STMT for s in plan["steps"])


def test_clean_column_minimal_plan():
    cur = _ScriptedCursor([[], [], [], [], [], []])
    deps = preflight.find_column_dependencies(cur, TABLE, COLUMN)
    plan = preflight.build_column_alter_plan(TABLE, COLUMN, ALTER_STMT, deps)
    assert [(s["phase"], s["sql"]) for s in plan["steps"]] == [
        ("alter", ALTER_STMT),
        ("rebuild", f"UPDATE STATISTICS [{TABLE}];"),
    ]
    assert plan["warnings"] == []


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
