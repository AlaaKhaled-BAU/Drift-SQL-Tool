"""ponytail: minimal self-check for Lane B livescan -- scan() must build its
snapshot from the DOCUMENTED query order (objects+hashes first, columns
second), quick_compare must classify with exact deterministic set logic, and
-- the C1 safety rule -- the module must expose NO script-generation surface
at all. No live DB needed: fake cursors return scripted fetchalls, and
connect()'s kwargs are captured via a patched-out pymssql.
Run: python3.13 test_livescan.py

livescan.py needs no sibling imports (connect deliberately ignores
config.HOST_PORT), so unlike test_inspect_objects.py this file could bare-
import -- but the sys.path/package-import header costs nothing and keeps the
runner identical to the rest of the battery.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import livescan  # noqa: E402


class _ScriptedCursor:
    """Dict-row fake cursor: each fetchall() pops the next queued result set,
    so tests script the two-result-set order scan() is contracted to use."""

    def __init__(self, *result_sets):
        self.result_sets = list(result_sets)
        self.sql_calls = []  # every execute()d SQL text, in order

    def execute(self, sql):
        self.sql_calls.append(sql)

    def fetchall(self):
        return self.result_sets.pop(0)


def _scan_a():
    """Source-side snapshot as scan() would build it (hand-built, order-free)."""
    return {
        "objects": {
            "Pro_X": {"type": "SQL_STORED_PROCEDURE", "body_hash": "aa11"},
            "Tbl_Menu": {"type": "USER_TABLE", "body_hash": None},
            "Fn_Calc": {"type": "SQL_SCALAR_FUNCTION", "body_hash": "bb22"},
        },
        "columns": {
            "Tbl_Menu.Id": {"type": "int", "max_length": 4, "precision": 10, "scale": 0},
            "Tbl_Menu.Name": {"type": "varchar", "max_length": 50, "precision": 0, "scale": 0},
        },
    }


def test_scan_populates_objects_hash_passthrough_and_none_for_tables():
    cur = _ScriptedCursor(
        [  # result set 1: objects (proc has hex hash, table has NULL)
            {"name": "Pro_X", "type_desc": "SQL_STORED_PROCEDURE", "body_hash": "aa11"},
            {"name": "Tbl_Menu", "type_desc": "USER_TABLE", "body_hash": None},
        ],
        [  # result set 2: columns
            {"table_name": "Tbl_Menu", "column_name": "Id",
             "type_name": "int", "max_length": 4, "precision": 10, "scale": 0},
        ],
    )
    snap = livescan.scan(cur)
    assert snap["objects"]["Pro_X"] == {"type": "SQL_STORED_PROCEDURE", "body_hash": "aa11"}
    # tables are module-less -> LEFT JOIN yields NULL -> None, never a hash
    assert snap["objects"]["Tbl_Menu"]["body_hash"] is None
    assert snap["objects"]["Tbl_Menu"]["type"] == "USER_TABLE"
    assert snap["columns"] == {
        "Tbl_Menu.Id": {"type": "int", "max_length": 4, "precision": 10, "scale": 0},
    }


def test_scan_decodes_bytes_body_hash_defensively():
    """If a driver hands varbinary back as raw bytes instead of CONVERT-ed hex
    text, scan() normalizes to hex so comparison stays string-vs-string."""
    cur = _ScriptedCursor(
        [{"name": "P", "type_desc": "SQL_STORED_PROCEDURE", "body_hash": b"\xde\xad"}],
        [],
    )
    snap = livescan.scan(cur)
    assert snap["objects"]["P"]["body_hash"] == "dead"


def test_scan_runs_queries_in_documented_order():
    """Result-set order IS the contract (fake fetchalls depend on it): first
    execute = objects+HASHBYTES over sys.objects/sys.sql_modules, second =
    column shapes over sys.columns joined to sys.tables (user tables only)."""
    cur = _ScriptedCursor([{"name": "X", "type_desc": "USER_TABLE", "body_hash": None}], [])
    livescan.scan(cur)
    assert len(cur.sql_calls) == 2
    first, second = cur.sql_calls
    assert "sys.objects" in first and "sys.sql_modules" in first
    assert "HASHBYTES('SHA2_256'" in first
    assert "sys.columns" in second and "sys.tables" in second


def test_quick_compare_missing_and_extra():
    a = _scan_a()
    b = {"objects": {"Pro_X": {"type": "SQL_STORED_PROCEDURE", "body_hash": "aa11"},
                     "Only_On_B": {"type": "USER_TABLE", "body_hash": None}},
         "columns": {}}
    r = livescan.quick_compare(a, b)
    assert r["missing_in_b"] == ["Fn_Calc", "Tbl_Menu"]  # on source only, sorted
    assert r["extra_in_b"] == ["Only_On_B"]
    assert "Pro_X" not in r["body_changed"]  # same hash both sides -> untouched


def test_quick_compare_body_changed_flags_diff_hashes_only():
    same = {"type": "SQL_STORED_PROCEDURE", "body_hash": "aa11"}
    diff = {"type": "SQL_STORED_PROCEDURE", "body_hash": "ff99"}
    a = {"objects": {"Keep": same, "Mod": same, "FlipA": same}, "columns": {}}
    b = {"objects": {"Keep": same, "Mod": diff, "FlipA":
                     {"type": "SQL_SCALAR_FUNCTION", "body_hash": None}},
         "columns": {}}
    r = livescan.quick_compare(a, b)
    assert r["body_changed"] == ["FlipA", "Mod"]  # sorted, identical hash skipped


def test_quick_compare_none_vs_hash_counts_as_changed():
    """None-vs-hex is a real catalog change (object gained/lost its module) --
    silently treating it as equal would hide exactly the drift triage exists
    to catch. Type-desc-only changes do NOT flag: bodies hash the definition,
    and presence/type buckets cover the rest."""
    a = {"objects": {"Grew": {"type": "USER_TABLE", "body_hash": None}}, "columns": {}}
    b = {"objects": {"Grew": {"type": "SQL_STORED_PROCEDURE", "body_hash": "ab"}}, "columns": {}}
    assert livescan.quick_compare(a, b)["body_changed"] == ["Grew"]
    # but type flip with SAME hash (impossible live, legal input) stays quiet:
    b2 = {"objects": {"Grew": {"type": "VIEW", "body_hash": None}}, "columns": {}}
    assert livescan.quick_compare(a, b2)["body_changed"] == []


def test_quick_compare_columns_added_removed_altered():
    base = {"type": "int", "max_length": 4, "precision": 10, "scale": 0}
    a = {"objects": {},
         "columns": {"T.Gone": base, "T.Same": base,
                     "T.Wide": {"type": "varchar", "max_length": 10, "precision": 0, "scale": 0}}}
    b = {"objects": {},
         "columns": {"T.New": base, "T.Same": base,
                     "T.Wide": {"type": "varchar", "max_length": 50, "precision": 0, "scale": 0},
                     "T.Prec": {"type": "decimal", "max_length": 9, "precision": 18, "scale": 2}}}
    r = livescan.quick_compare(a, b)["columns"]
    assert r["added"] == ["T.New", "T.Prec"]
    assert r["removed"] == ["T.Gone"]
    assert r["altered"] == ["T.Wide"]  # max_length 10 -> 50 is shape drift
    assert "T.Same" not in r["altered"] + r["added"] + r["removed"]


def test_quick_compare_sorted_deterministic_output():
    """Insertion order of the input dicts must not leak into findings: feed
    deliberately unsorted data twice in different orders, get byte-equal,
    sorted output both times."""
    names = ["zeta", "alpha", "Mid", "beta"]
    mk = lambda ns: {"objects": {n: {"type": "USER_TABLE", "body_hash": None} for n in ns},
                     "columns": {}}
    r1 = livescan.quick_compare(mk(names), mk(list(reversed(names))))
    r2 = livescan.quick_compare(mk(list(reversed(names))), mk(names))
    for bucket in ("missing_in_b", "extra_in_b", "body_changed"):
        assert r1[bucket] == sorted(r1[bucket])
        assert r1[bucket] == r2[bucket]  # symmetric set ops, stable under swap
    assert r1["summary"] == r2["summary"]


def test_quick_compare_empty_scans_summary_zeros():
    empty = {"objects": {}, "columns": {}}
    r = livescan.quick_compare(empty, empty)
    assert r == {
        "missing_in_b": [], "extra_in_b": [], "body_changed": [],
        "columns": {"added": [], "removed": [], "altered": []},
        "summary": {"objects_a": 0, "objects_b": 0, "missing_in_b": 0, "extra_in_b": 0,
                    "body_changed": 0, "columns_a": 0, "columns_b": 0,
                    "columns_added": 0, "columns_removed": 0, "columns_altered": 0},
    }


def test_summary_counts_consistent_with_lists():
    a = _scan_a()
    b = {"objects": {"Pro_X": {"type": "SQL_STORED_PROCEDURE", "body_hash": "zz"},
                     "Extra_B": {"type": "USER_TABLE", "body_hash": None}},
         "columns": {"Tbl_Menu.Id": {"type": "int", "max_length": 8, "precision": 10, "scale": 0},
                     "Tbl_Menu.New": {"type": "bit", "max_length": 1, "precision": 1, "scale": 0}}}
    r = livescan.quick_compare(a, b)
    s = r["summary"]
    assert s["objects_a"] == len(a["objects"]) and s["objects_b"] == len(b["objects"])
    assert s["missing_in_b"] == len(r["missing_in_b"])
    assert s["extra_in_b"] == len(r["extra_in_b"])
    assert s["body_changed"] == len(r["body_changed"]) == 1  # Pro_X hash zz
    assert s["columns_added"] == len(r["columns"]["added"])
    assert s["columns_removed"] == len(r["columns"]["removed"])
    assert s["columns_altered"] == len(r["columns"]["altered"]) == 1


def test_connect_param_contract_no_port_login_timeout_10():
    """connect() passes server/database/user/password straight through with
    login_timeout=10 (restore._connect parity), and -- the live-target rule --
    NEVER sends config.HOST_PORT / a port kwarg at all."""

    class _FakePymssql:
        def __init__(self):
            self.kwargs = None

        def connect(self, **kwargs):
            self.kwargs = kwargs
            return "sentinel-conn"

    fake = _FakePymssql()
    original = livescan.pymssql
    livescan.pymssql = fake  # monkeypatch: capture kwargs, open no socket
    try:
        conn = livescan.connect("live.host.example", "ClientDB", "sa_user", "secret")
        assert conn == "sentinel-conn"
        assert fake.kwargs == {
            "server": "live.host.example",
            "database": "ClientDB",
            "user": "sa_user",
            "password": "secret",
            "timeout": 60,
            "login_timeout": 10,
        }
        assert "port" not in fake.kwargs, "live targets must not inherit the scratch container's HOST_PORT"
    finally:
        livescan.pymssql = original


def test_module_guard_no_script_generation_callables():
    """THE C1 safety rule, machine-checked: no callable in this module's
    namespace may be named script*/generate*/emit* -- the absence of any
    generation entry point IS the feature. Also pin the SCAN_ONLY sentinel."""
    assert livescan.SCAN_ONLY is True
    assert not any(
        callable(getattr(livescan, n))
        and ("script" in n.lower() or "generate" in n.lower() or "emit" in n.lower())
        for n in dir(livescan)
    )


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
