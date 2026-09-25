"""Self-check for datacopy.py (PLAN-V5 Lane A, blueprint C2) -- fake-cursor
harness, no live DB.

The three regression targets are the old Copy Data tool's unforgivable bugs:
  1. apostrophes: "Al'Malak" must round-trip as 'Al''Malak' and NEVER land
     quote-stripped ("AlMalak") in any emitted script;
  2. composite keys: a two-column key emits WHERE ([K1] = v1) AND ([K2] = v2)
     with BOTH predicates (the old builder kept only the last one);
  3. identity: IDENTITY_INSERT ON/OFF pairs balanced around wrapped inserts,
     never in UPDATE SET lists.

Discovery functions script dict-row fetchall() sequences exactly like
test_preflight's harness; apply_plan is verified against an _ExecCursor that
records every execute(sql, params) so values can be proven to travel as %s
bind params, never interpolated into SQL text.
Run: python3.13 test_datacopy.py
"""
import re
import sys
from copy import deepcopy
from datetime import datetime
from decimal import Decimal
from pathlib import Path

# Same sys.path/package pattern as test_preflight.py: runs identically from
# any working directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import datacopy  # noqa: E402

COLS3 = ["MenuId", "Code", "Label"]


class _DictRowsCursor:
    """Records every execute(sql, params); each fetchall() consumes the next
    scripted sequence of dict rows (inspect_objects convention)."""

    def __init__(self, sequences):
        self.sequences = list(sequences)
        self.calls = []  # list of (sql, params)

    def execute(self, sql, params=None):
        self.calls.append((sql, params))

    def fetchall(self):
        return self.sequences.pop(0) if self.sequences else []


class _FakeMssqlError(Exception):
    """pymssql MSSQLDatabaseException shape: args = (msgno:int, message:bytes)."""


class _ExecCursor:
    """Records successful execute(sql, params) calls in order; raises a
    pymssql-shaped error on the call numbers listed in fail_calls; carries a
    rowcount attribute like a real DB-API cursor."""

    def __init__(self, fail_calls=(), rowcount=1):
        self.calls = []
        self.fail_calls = set(fail_calls)
        self.rowcount = rowcount
        self._n = 0

    def execute(self, sql, params=None):
        self._n += 1
        if self._n in self.fail_calls:
            raise _FakeMssqlError(2601, b"Violation of PRIMARY KEY constraint 'PK_T'.")
        self.calls.append((sql, params))


def _rd(menu_id, code, label):
    return {"cols": ["MenuId", "Code", "Label"],
            "values": {"MenuId": menu_id, "Code": code, "Label": label}}


def _plan(insert=(), update=(), delete=()):
    return {"insert": list(insert), "update": list(update), "delete": list(delete)}


# --------------------------------------------------------------------------
# discovery
# --------------------------------------------------------------------------

def test_whitelist_filtering_case_insensitive_and_editable():
    cur = _DictRowsCursor([[{"name": n} for n in [
        "MESSAGES", "Menu_Main", "Customer", "sysdiagrams", "dtproperties",
        "webpage_cache", "myPrograms2"]]])
    got = datacopy.list_config_tables(cur)
    # case-insensitive substring match (MESSAGES ~ messag, myPrograms2 ~
    # programs, webpage_cache ~ page); non-config names excluded; sorted out.
    assert got == ["MESSAGES", "Menu_Main", "myPrograms2", "webpage_cache"], got
    sql, _ = cur.calls[0]
    assert "is_ms_shipped = 0" in sql.replace("is_ms_shipped=0", "is_ms_shipped = 0")
    # whitelist is editable at the call site without touching the module
    cur2 = _DictRowsCursor([[{"name": "Customer"}, {"name": "sysdiagrams"}]])
    assert datacopy.list_config_tables(cur2, whitelist=re.compile(r"^cust", re.I)) == ["Customer"]
    assert datacopy.WHITELIST_RE.search("MASSAGE_Types") is not None


def test_get_key_columns_prefers_pk_orders_by_ordinal_and_falls_back():
    # PK index (index_id=3) beats the separate clustered index (index_id=1)
    cur = _DictRowsCursor([[
        {"is_primary_key": 0, "index_id": 1, "col_name": "X", "key_ordinal": 1},
        {"is_primary_key": 1, "index_id": 3, "col_name": "B", "key_ordinal": 1},
        {"is_primary_key": 1, "index_id": 3, "col_name": "A", "key_ordinal": 2},
    ]])
    assert datacopy.get_key_columns(cur, "SysMenu") == ["B", "A"]
    sql, params = cur.calls[0]
    assert "%s" in sql and params == ("SysMenu",), "table name must bind as %s"
    # no PK -> clustered (indid=1 equivalent) fallback, ordinal order
    cur2 = _DictRowsCursor([[
        {"is_primary_key": 0, "index_id": 1, "col_name": "X", "key_ordinal": 2},
        {"is_primary_key": 0, "index_id": 1, "col_name": "W", "key_ordinal": 1},
    ]])
    assert datacopy.get_key_columns(cur2, "T") == ["W", "X"]
    # neither PK nor clustered key -> empty list, not a crash
    assert datacopy.get_key_columns(_DictRowsCursor([[]]), "HeapTable") == []


def test_fetch_rows_hashed_builds_keytuple_map_preserving_columns():
    cur = _DictRowsCursor([[
        {"MenuId": 1, "Code": "AA", "Label": "First"},
        {"MenuId": 2, "Code": "BB", "Label": "Al'Malak"},
    ]])
    rows = datacopy.fetch_rows_hashed(cur, "[dbo].[SysMenu]", ["MenuId", "Code"])
    assert cur.calls[0][0] == "SELECT * FROM [dbo].[SysMenu]"
    assert set(rows) == {(1, "AA"), (2, "BB")}
    assert rows[(1, "AA")]["cols"] == ["MenuId", "Code", "Label"]
    assert rows[(2, "BB")]["values"] == {"MenuId": 2, "Code": "BB", "Label": "Al'Malak"}


def test_fetch_rows_hashed_refuses_duplicate_keys():
    # a duplicated key would make the key-targeted UPDATE/DELETE ambiguous --
    # the exact mass-update hazard bug #2 enabled. Refuse loudly.
    cur = _DictRowsCursor([[{"Id": 1, "V": "x"}, {"Id": 1, "V": "y"}]])
    try:
        datacopy.fetch_rows_hashed(cur, "[T]", ["Id"])
        assert False, "expected ValueError on duplicate key"
    except ValueError:
        pass


# --------------------------------------------------------------------------
# diff
# --------------------------------------------------------------------------

def test_diff_tables_classification_exact():
    same = _rd(1, "AA", "unchanged")
    new_row = _rd(3, "CC", "brand new")
    src = {("m", 1): same, ("m", 2): _rd("m", 2, "src text"), ("m", 3): new_row}
    dst = {("m", 1): same, ("m", 2): _rd("m", 2, "dst text"),
           ("m", 4): _rd("m", 4, "obsolete")}
    plan = datacopy.diff_tables(src, dst)
    assert set(plan) == {"insert", "update", "delete"}
    assert plan["insert"] == [new_row], plan["insert"]
    assert [r["values"]["Label"] for r in plan["update"]] == ["src text"]  # src wins
    assert plan["delete"] == [("m", 4)], "deletes carry KEYTUPLES, not rowdicts"
    # identical maps -> fully empty plan (feeds the no-op script case)
    empty = datacopy.diff_tables(src, deepcopy(src))
    assert empty == {"insert": [], "update": [], "delete": []}


def test_row_hash_distinguishes_bool_int_str():
    # type-tagged hashing: bit semantics differ from int/string even when reprs collide
    assert datacopy.row_hash({"a": 1}) != datacopy.row_hash({"a": True})
    assert datacopy.row_hash({"a": 1}) != datacopy.row_hash({"a": "1"})
    assert datacopy.row_hash({"a": 1, "b": None}) == datacopy.row_hash({"b": None, "a": 1})


# --------------------------------------------------------------------------
# emission
# --------------------------------------------------------------------------

def test_composite_key_emits_every_predicate_regression():
    """THE regression: old tool's WHERE builder overwrote accumulated
    predicates, leaving ONLY the last key column -- mass-update hazard."""
    rd = _rd(3, "AB", "Al'Malak")
    script = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"],
        _plan(update=[rd], delete=[(9, "ZZ")]))
    assert "WHERE ([MenuId] = 3) AND ([Code] = 'AB');" in script, script
    assert "DELETE FROM [dbo].[SysMenu] WHERE ([MenuId] = 9) AND ([Code] = 'ZZ');" in script


def test_apostrophes_roundtrip_and_are_never_stripped():
    names = ["Al'Malak", "O'Brien", "it''s already doubled",
             "100% pure", "quote ' inside"]
    for name in names:
        script = datacopy.emit_merge_script(
            "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"],
            _plan(update=[_rd(1, "K", name)]))
        doubled = "'" + name.replace("'", "''") + "'"
        assert doubled in script, f"escaped literal missing for {name!r}"
        # round-trip: unescaping exactly what was emitted yields the original
        assert doubled[1:-1].replace("''", "'") == name, name
    # the old tool's fatal fingerprint: the STRIPPED form must never appear
    script = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"],
        _plan(update=[_rd(1, "K", "Al'Malak")]))
    assert "AlMalak" not in script, "quote-stripping bug reproduced!"


def test_literal_rendering_null_bit_datetime_numeric_binary():
    rd = {"cols": ["Id", "BitF", "DecF", "DtF", "BinF", "TxtF"],
          "values": {"Id": 5, "BitF": True, "DecF": Decimal("10.50"),
                     "DtF": datetime(2026, 1, 2, 3, 4, 5),
                     "BinF": b"\xab\x01", "TxtF": None}}
    script = datacopy.emit_merge_script("[T]", rd["cols"], ["Id"], _plan(insert=[rd]))
    expected = ("INSERT INTO [T] ([Id], [BitF], [DecF], [DtF], [BinF], [TxtF]) "
                "VALUES (5, 1, 10.50, '2026-01-02 03:04:05', 0xab01, NULL);")
    assert expected in script, script
    # bool checked BEFORE int (True IS an int subclass); False renders 0
    false_row = {"cols": ["BitF"], "values": {"BitF": False}}
    s2 = datacopy.emit_merge_script("[T]", ["BitF"], [], _plan(insert=[false_row]))
    assert "VALUES (0);" in s2, s2


def test_identity_wrap_balanced_pairs_and_plain_when_unknown():
    ins = [_rd(7, "I7", "one"), _rd(8, "I8", "two")]
    script = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"], _plan(insert=ins),
        identity_cols=["MenuId"])
    lines = script.splitlines()
    ons = [i for i, l in enumerate(lines) if l == "SET IDENTITY_INSERT [dbo].[SysMenu] ON;"]
    offs = [i for i, l in enumerate(lines) if l == "SET IDENTITY_INSERT [dbo].[SysMenu] OFF;"]
    assert len(ons) == len(offs) == 2, lines
    assert ons[0] < offs[0] < ons[1] < offs[1], "each ON/OFF pair must bracket its insert"
    first_ins = next(i for i, l in enumerate(lines) if l.startswith("INSERT INTO"))
    assert ons[0] < first_ins < offs[0]
    # identity columns never enter an UPDATE SET list (illegal in T-SQL)
    upd = _rd(7, "I7", "changed")
    s2 = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"], _plan(update=[upd]),
        identity_cols=["MenuId"])
    assert "UPDATE [dbo].[SysMenu] SET [Label] = 'changed'" \
           " WHERE ([MenuId] = 7) AND ([Code] = 'I7');" in s2, s2
    # identity_cols=None: nothing identified -> nothing wrapped, nothing omitted
    s3 = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"], _plan(insert=[_rd(7, "I7", "x")]))
    assert "IDENTITY_INSERT" not in s3 and "[MenuId]" in s3


def test_deletes_come_last_and_carry_full_key():
    script = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"],
        _plan(insert=[_rd(1, "A1", "n"), _rd(2, "B2", "n")],
              update=[_rd(3, "C3", "changed")],
              delete=[(8, "X8"), (9, "Y9")]))
    lines = script.splitlines()
    del_idx = [i for i, l in enumerate(lines) if l.startswith("DELETE FROM")]
    other_idx = [i for i, l in enumerate(lines)
                 if l.startswith(("INSERT INTO", "UPDATE ", "IF ", "SET IDENTITY"))]
    assert del_idx and max(other_idx) < min(del_idx), "deletes must be LAST"
    joined = "\n".join(lines)
    assert joined.count("DELETE FROM") == 2
    for mid in ("([MenuId] = 8) AND ([Code] = 'X8')",
                "([MenuId] = 9) AND ([Code] = 'Y9')"):
        assert f"DELETE FROM [dbo].[SysMenu] WHERE {mid};" in joined


def test_empty_diff_is_noop_script_with_counts_header():
    script = datacopy.emit_merge_script("[dbo].[SysMenu]", COLS3, ["MenuId", "Code"],
                                        _plan())
    assert "-- nothing to apply" in script
    body = "\n".join(l for l in script.splitlines() if not l.startswith("--"))
    assert "INSERT" not in body and "UPDATE" not in body and "DELETE" not in body


def test_header_comment_carries_counts_table_and_utc_ts():
    script = datacopy.emit_merge_script(
        "[dbo].[SysMenu]", COLS3, ["MenuId", "Code"],
        _plan(insert=[_rd(1, "A", "x"), _rd(2, "B", "y")], update=[_rd(3, "C", "z")],
              delete=[(9, "Z")]))
    head = script.splitlines()[0]
    assert head.startswith("-- drift.datacopy merge plan for [dbo].[SysMenu]: "
                          "2 ins / 1 upd / 1 del -- generated UTC "), head
    assert re.search(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", head), head


# --------------------------------------------------------------------------
# execution (parameterized path)
# --------------------------------------------------------------------------

HOSTILE = "x'); DROP TABLE SysMenu; --"


def test_apply_plan_binds_params_never_interpolates_values():
    upd = {"cols": ["MenuId", "Code", "Label"],
           "values": {"MenuId": 3, "Code": "AB", "Label": HOSTILE}}
    ins = {"cols": ["MenuId", "Code", "Label"],
           "values": {"MenuId": 4, "Code": "CD", "Label": HOSTILE}}
    cur = _ExecCursor()
    res = datacopy.apply_plan(cur, "[dbo].[SysMenu]", ["MenuId", "Code"],
                              _plan(insert=[ins], update=[upd], delete=[(9, "ZZ")]))
    assert res == {"inserted": 1, "updated": 1, "deleted": 1, "errors": []}, res
    for sql, params in cur.calls:
        assert HOSTILE not in sql, f"value interpolated into SQL text: {sql}"
        assert "%s" in sql or sql.startswith(("SET IDENTITY_INSERT",)), sql
    # hostile value travels ONLY inside the params tuples
    bound = [p for _, ps in cur.calls if ps for p in ps]
    assert bound.count(HOSTILE) == 2, bound
    upd_sql = next(s for s, _ in cur.calls if s.startswith("UPDATE"))
    assert "SET [Label] = %s WHERE ([MenuId] = %s) AND ([Code] = %s)" in upd_sql, upd_sql
    del_sql, del_params = next((s, p) for s, p in cur.calls if s.startswith("DELETE"))
    assert del_sql.endswith("WHERE ([MenuId] = %s) AND ([Code] = %s)")
    assert del_params == (9, "ZZ")


def test_apply_plan_continues_past_per_row_errors():
    ins = [{"cols": ["MenuId"], "values": {"MenuId": i}} for i in range(1, 4)]
    cur = _ExecCursor(fail_calls={2, 5})  # 2nd insert + the delete blow up
    res = datacopy.apply_plan(cur, "[dbo].[SysMenu]", ["MenuId"],
                              _plan(insert=ins,
                                    update=[{"cols": ["MenuId", "Label"],
                                             "values": {"MenuId": 30, "Label": "v"}}],
                                    delete=[(99,)]))
    assert res["inserted"] == 2 and res["updated"] == 1 and res["deleted"] == 0, res
    assert [e["op"] for e in res["errors"]] == ["insert", "delete"], res["errors"]
    assert all("2601" in e["error"] or "PRIMARY KEY" in e["error"] for e in res["errors"])
    # execution genuinely continued past both failures: 3 successful calls ran
    assert len(cur.calls) == 3


def test_apply_plan_zero_rowcount_falls_back_to_insert():
    # mirrors the artifact's IF @@ROWCOUNT = 0 BEGIN INSERT ... END block:
    # row vanished between diff and apply -> INSERT instead of silent no-op
    cur = _ExecCursor(rowcount=0)
    upd = {"cols": ["MenuId", "Code", "Label"],
           "values": {"MenuId": 3, "Code": "AB", "Label": "late"}}
    res = datacopy.apply_plan(cur, "[dbo].[SysMenu]", ["MenuId", "Code"],
                              _plan(update=[upd]))
    assert res == {"inserted": 1, "updated": 0, "deleted": 0, "errors": []}, res
    kinds = [s.split()[0] for s, _ in cur.calls]
    assert kinds == ["UPDATE", "INSERT"], cur.calls


def test_apply_plan_identity_wraps_parameterized_and_stays_balanced_on_error():
    ident = ["MenuId"]
    ins = {"cols": ["MenuId", "Code", "Label"],
           "values": {"MenuId": 7, "Code": "I7", "Label": "seed repair"}}
    cur = _ExecCursor()
    res = datacopy.apply_plan(cur, "[dbo].[SysMenu]", ["MenuId", "Code"],
                              _plan(insert=[ins]), identity_cols=ident)
    assert res["inserted"] == 1
    seq = [(s.split(";")[0].strip(), p) for s, p in cur.calls]
    assert seq[0][0] == "SET IDENTITY_INSERT [dbo].[SysMenu] ON" and seq[0][1] is None
    assert seq[1][0].startswith("INSERT INTO") and seq[1][1] == (7, "I7", "seed repair")
    assert seq[2][0] == "SET IDENTITY_INSERT [dbo].[SysMenu] OFF" and seq[2][1] is None
    # failed insert still closes the pair (finally-clause OFF)
    cur2 = _ExecCursor(fail_calls={2})
    res2 = datacopy.apply_plan(cur2, "[dbo].[SysMenu]", ["MenuId", "Code"],
                               _plan(insert=[ins]), identity_cols=ident)
    assert res2["errors"] and res2["inserted"] == 0
    texts = [s for s, _ in cur2.calls]
    assert texts.count("SET IDENTITY_INSERT [dbo].[SysMenu] ON") == \
        texts.count("SET IDENTITY_INSERT [dbo].[SysMenu] OFF") == 1


def test_inputs_never_mutated():
    src = {("m", 1): _rd("m", 1, "a"), ("m", 2): _rd("m", 2, "old")}
    dst = {("m", 1): _rd("m", 1, "a"), ("m", 3): _rd("m", 3, "gone")}
    src_snap, dst_snap = deepcopy(src), deepcopy(dst)
    plan = datacopy.diff_tables(src, dst)
    plan_snap = deepcopy(plan)
    datacopy.emit_merge_script("[dbo].[SysMenu]", COLS3, ["MenuId", "Code"], plan,
                               identity_cols=None)
    cur = _ExecCursor()
    datacopy.apply_plan(cur, "[dbo].[SysMenu]", ["MenuId", "Code"], plan)
    assert src == src_snap and dst == dst_snap and plan == plan_snap


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
