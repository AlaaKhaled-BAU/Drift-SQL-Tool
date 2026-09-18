"""ponytail: minimal self-check for D3 -- fetch_by_names must batch at 1000
names, substitute exactly one %s per name into {ph}, and pass names as real
pymssql parameters (never f-string-interpolated into the SQL text). No live
DB needed: a fake cursor records what execute() was called with.
Run: python3.13 test_inspect_objects.py

inspect_objects.py uses `from . import config` (package-relative), same
reason test_changelog.py needs this sys.path/package-import trick rather
than a bare `import inspect_objects`.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import inspect_objects  # noqa: E402


class _FakeCursor:
    def __init__(self):
        self.calls = []  # list of (sql_text, params)

    def execute(self, sql, params):
        self.calls.append((sql, params))

    def fetchall(self):
        return [{"name": p} for p in self.calls[-1][1]]


def test_names_passed_as_real_parameters_not_interpolated():
    cur = _FakeCursor()
    names = ["a'; DROP TABLE x; --", "b", "c"]
    rows = inspect_objects.fetch_by_names(cur, "SELECT name FROM t WHERE name IN ({ph})", names)
    sql, params = cur.calls[0]
    assert "DROP TABLE" not in sql, "a name must never be interpolated into the SQL text"
    assert sql == "SELECT name FROM t WHERE name IN (%s,%s,%s)"
    assert params == tuple(names)
    assert len(rows) == 3


def test_batches_split_at_1000_names_per_execute():
    cur = _FakeCursor()
    names = [f"n{i}" for i in range(2500)]
    rows = inspect_objects.fetch_by_names(cur, "SELECT name FROM t WHERE name IN ({ph})", names)
    assert [len(p) for _, p in cur.calls] == [1000, 1000, 500]
    assert len(rows) == 2500


def test_empty_names_makes_no_query_and_returns_empty():
    cur = _FakeCursor()
    rows = inspect_objects.fetch_by_names(cur, "SELECT name FROM t WHERE name IN ({ph})", [])
    assert cur.calls == []
    assert rows == []


def test_accepts_a_set_not_just_a_list():
    cur = _FakeCursor()
    rows = inspect_objects.fetch_by_names(cur, "SELECT name FROM t WHERE name IN ({ph})", {"x", "y"})
    assert len(cur.calls[0][1]) == 2
    assert len(rows) == 2


def _col(name, type_name="int", nullable=False, is_pk=False):
    return {
        "name": name, "type": type_name, "max_length": 4, "precision": 0, "scale": 0,
        "nullable": nullable, "is_pk": is_pk,
    }


def test_build_table_bundle_empty_columns_returns_none():
    assert inspect_objects.build_table_bundle("T", "sales", [], [], set()) is None


def test_build_table_bundle_schema_qualified_create_and_pk():
    cols = [_col("ID", is_pk=True), _col("Note", "nvarchar", nullable=True)]
    cols[1]["max_length"] = 100  # nvarchar(50)
    bundle = inspect_objects.build_table_bundle("Items", "sales", cols, [], {"Items"})
    assert bundle is not None
    assert bundle["create_sql"] == (
        "CREATE TABLE [sales].[Items]([ID] int NOT NULL, [Note] nvarchar(50) NULL, PRIMARY KEY ([ID]));"
    )
    assert bundle["extras"] == []


def test_build_table_bundle_attaches_matching_extras():
    idx = "CREATE NONCLUSTERED INDEX [IX_T] ON [T]([ID]);"
    other = "CREATE INDEX [IX_O] ON [Other]([ID]);"
    bundle = inspect_objects.build_table_bundle(
        "T", "dbo", [_col("ID", is_pk=True)], [idx, other], {"T"})
    assert bundle["extras"] == [idx]


def test_build_table_bundle_omits_dangling_fk():
    fk = (
        "ALTER TABLE [T] ADD CONSTRAINT [FK_T_R] FOREIGN KEY ([RID]) "
        "REFERENCES [Ref]([ID]) ON DELETE NO ACTION ON UPDATE NO ACTION;"
    )
    bundle = inspect_objects.build_table_bundle(
        "T", "dbo", [_col("RID")], [fk], existing_tables={"T"})
    assert bundle["extras"] == []
    assert bundle["omitted_fks"] == [{"sql": fk, "referenced_table": "Ref"}]


def test_build_table_bundle_keeps_fk_when_ref_exists():
    fk = (
        "ALTER TABLE [T] ADD CONSTRAINT [FK_T_R] FOREIGN KEY ([RID]) "
        "REFERENCES [Ref]([ID]) ON DELETE NO ACTION ON UPDATE NO ACTION;"
    )
    bundle = inspect_objects.build_table_bundle(
        "T", "dbo", [_col("RID")], [fk], existing_tables={"T", "Ref"})
    assert bundle["extras"] == [fk]
    assert "omitted_fks" not in bundle


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
