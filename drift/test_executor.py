"""Self-check for executor.py (PLAN-V4 B.4) -- fake-cursor harness, no docker,
no live DB. Run: python3.13 test_executor.py

The harness exploits a deliberate design choice: run_statement classifies via
GENERIC Exception.args handling (pymssql's MSSQLDatabaseException carries
args[0]=msgno int, args[1]=bytes msg), so a plain Exception subclass carrying
that same .args shape exercises the full classification path without pymssql.
Covered here:
  - every benign class skips + the run CONTINUES past it
  - a fatal stops the batch mid-flight (tail never attempted)
  - summary counts are exact on a mixed batch; empty batch zeroes cleanly
  - benign-then-fatal ordering; sql previews truncated safely (no newlines)
  - rehearse(): hermetic skip gate fires BEFORE any docker call; when enabled
    (against an injected fake restore stack) the scratch DB is restored, run,
    and ALWAYS dropped -- including when the restore itself fails.
"""
import os
import sys
import types
from pathlib import Path

# executor.py's siblings (docker_mgmt/restore) need package context for their
# own relative imports -- same sys.path/package trick as test_inspect_objects.py.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import executor  # noqa: E402


class _FakeDbError(Exception):
    """Mimics pymssql MSSQLDatabaseException's arg shape exactly:
    args[0] = msgno (int), args[1] = raw bytes message."""


class _FakeCursor:
    """Records every executed statement; raises a configured exception when a
    needle substring appears in the statement text."""

    def __init__(self, raise_when=None):
        self.executed = []
        self.raise_when = dict(raise_when or {})

    def execute(self, sql):
        self.executed.append(sql)
        for needle, exc in self.raise_when.items():
            if needle in sql:
                raise exc


S1 = "ALTER TABLE [dbo].[T1] ADD [C1] int NULL;"
S2 = "stmt-two-marker ALTER TABLE [dbo].[T2];"
S3 = "ALTER TABLE [dbo].[T3] DROP COLUMN [C3];"
S4 = "stmt-four-marker ALTER TABLE [dbo].[T4];"
S5 = "stmt-five-marker ALTER TABLE [dbo].[T5];"


def test_classify_error_maps_every_benign_class():
    cases = [
        (5074, "dependent"), (3729, "dependent"),
        (8152, "truncation"), (2628, "truncation"),
        (2601, "duplicate_key"), (2627, "duplicate_key"),
        (1505, "unique_index"), (1913, "unique_index"),
    ]
    for msgno, cls in cases:
        assert executor.classify_error(_FakeDbError(msgno, b"msg")) == (cls, msgno)


def test_classify_error_unknown_and_nonsql():
    # SQL-shaped but untabled -> fatal carrying the real msgno
    assert executor.classify_error(_FakeDbError(3602, b"severe")) == ("fatal", 3602)
    # non-SQL errors -> python_error/msgno 0 (never misread as engine messages)
    assert executor.classify_error(ValueError("boom")) == ("python_error", 0)
    assert executor.classify_error(Exception()) == ("python_error", 0)
    assert executor.classify_error(Exception("not", b"ints")) == ("python_error", 0)


def test_run_statement_status_shapes():
    cur = _FakeCursor()
    r = executor.run_statement(cur, "SELECT 1;")
    assert r == {"status": "ok", "class": "ok", "msgno": 0, "msg": ""}

    cur = _FakeCursor({"B": _FakeDbError(5074, b"The object 'DF_x' is dependent on column 'A'.")})
    r = executor.run_statement(cur, "B-alter")
    assert r["status"] == "benign" and r["class"] == "dependent"
    assert r["msgno"] == 5074 and "dependent" in r["msg"], "bytes message must be decoded"

    cur = _FakeCursor({"F": _FakeDbError(99999, b"kaboom")})
    r = executor.run_statement(cur, "F-alter")
    assert r["status"] == "fatal" and r["class"] == "fatal" and r["msgno"] == 99999

    cur = _FakeCursor({"P": TypeError("boom")})
    r = executor.run_statement(cur, "P-alter")
    assert r["status"] == "fatal" and r["class"] == "python_error" and r["msgno"] == 0


def test_each_benign_class_skips_and_run_continues():
    benign = [("dependent", 5074), ("truncation", 8152),
              ("duplicate_key", 2601), ("unique_index", 1505)]
    for cls, msgno in benign:
        cur = _FakeCursor({S2: _FakeDbError(msgno, b"benign failure mid-batch")})
        r = executor.run_script(cur, [S1, S2, S3])
        assert len(cur.executed) == 3, f"{cls}: run must CONTINUE past a benign failure"
        assert r["summary"] == {"total": 3, "ok": 2, "benign": 1, "fatal": 0}
        statuses = [e["status"] for e in r["report"]]
        classes = [e["class"] for e in r["report"]]
        assert statuses == ["ok", "benign", "ok"]
        assert classes == ["ok", cls, "ok"]


def test_fatal_stops_mid_batch():
    cur = _FakeCursor({S2: _FakeDbError(3602, b"severe, unclassifiable")})
    r = executor.run_script(cur, [S1, S2, S3])
    # S3 must NEVER be attempted: running blind past a fatal could compound
    # damage (e.g. executing the rebuild half of a teardown/rebuild pair).
    assert cur.executed == [S1, S2]
    assert len(r["report"]) == 2
    assert r["summary"] == {"total": 2, "ok": 1, "benign": 0, "fatal": 1}
    assert r["report"][1]["msgno"] == 3602


def test_mixed_batch_summary_counts_exact():
    cur = _FakeCursor({
        S2: _FakeDbError(8152, b"string or binary data would be truncated"),
        S4: _FakeDbError(2627, b"Violation of PRIMARY KEY constraint"),
        S5: _FakeDbError(99999, b"catastrophic"),
    })
    r = executor.run_script(cur, [S1, S2, S3, S4, S5])
    assert [e["status"] for e in r["report"]] == ["ok", "benign", "ok", "benign", "fatal"]
    assert r["summary"] == {"total": 5, "ok": 2, "benign": 2, "fatal": 1}


def test_empty_statements_list():
    cur = _FakeCursor()
    r = executor.run_script(cur, [])
    assert r["report"] == []
    assert r["summary"] == {"total": 0, "ok": 0, "benign": 0, "fatal": 0}
    assert cur.executed == []


def test_benign_then_fatal_ordering():
    cur = _FakeCursor({
        S1: _FakeDbError(3729, b"dependent on column"),   # benign first...
        S2: _FakeDbError(99999, b"then fatal"),           # ...fatal second
    })
    r = executor.run_script(cur, [S1, S2, S3])
    assert r["report"][0]["status"] == "benign" and r["report"][1]["status"] == "fatal"
    assert len(cur.executed) == 2 and S3 not in cur.executed


def test_sql_preview_truncated_safely():
    long_stmt = "-- a very chatty comment\nSELECT '" + "X" * 300 + "';"
    r = executor.run_script(_FakeCursor(), [long_stmt, "short stmt;"])
    p = r["report"][0]["sql_preview"]
    assert "\n" not in p, "previews must stay line-oriented (newlines collapsed)"
    assert p.endswith("...") and len(p) <= 120 + 3
    assert r["report"][1]["sql_preview"] == "short stmt;", "short statements pass through intact"


# --- rehearse() safety contract -------------------------------------------
# The real docker/restore modules are REPLACED on the executor module object
# (rehearse looks them up at call time), so the whole scratch lifecycle is
# exercised hermetically: nothing here can touch docker or pymssql.


def _install_fake_stack(events, cursor, restore_error=None):
    def ensure_running(log):
        events.append("ensure_running")

    def restore_backup(path, db, log):
        if restore_error is not None:
            raise restore_error
        events.append(("restore_backup", str(path), db))

    def connect(db=None, autocommit=True):
        events.append(("connect", db))
        return types.SimpleNamespace(cursor=lambda: cursor)

    def drop_database(db, log):
        events.append(("drop_database", db))

    saved = (executor.docker_mgmt, executor.restore)
    executor.docker_mgmt = types.SimpleNamespace(ensure_running=ensure_running)
    executor.restore = types.SimpleNamespace(
        restore_backup=restore_backup, _connect=connect, drop_database=drop_database)
    return saved


def _with_env(enabled):
    """Set/clear RUN_LIVE_DB, returning the prior value for restoration."""
    prior = os.environ.pop("RUN_LIVE_DB", None)
    if enabled:
        os.environ["RUN_LIVE_DB"] = "1"
    return prior


def test_rehearse_skipped_before_any_docker_call():
    # Poison the stack: if the env gate failed to fire first, these explode
    # loudly instead of quietly starting a container from the test suite.
    def poison(log):
        raise AssertionError("docker must not be touched while RUN_LIVE_DB is unset")

    saved_modules = (executor.docker_mgmt, executor.restore)
    executor.docker_mgmt = types.SimpleNamespace(ensure_running=poison)
    executor.restore = types.SimpleNamespace(
        restore_backup=poison, _connect=poison, drop_database=poison)
    prior = _with_env(enabled=False)
    try:
        r = executor.rehearse("/tmp/opencode/client.bak", ["SELECT 1;"], log=lambda m: None)
    finally:
        executor.docker_mgmt, executor.restore = saved_modules
        if prior is not None:
            os.environ["RUN_LIVE_DB"] = prior
    assert r.get("skipped") is True, r
    assert r.get("reason"), "skip must explain itself"


def test_rehearse_scratch_lifecycle_restore_run_drop():
    prior = _with_env(enabled=True)
    events = []
    cur = _FakeCursor()
    saved_modules = _install_fake_stack(events, cur)
    logs = []
    try:
        r = executor.rehearse("/tmp/opencode/client.bak", ["S1", "S2"], log=logs.append)
    finally:
        executor.docker_mgmt, executor.restore = saved_modules
        if prior is not None:
            os.environ["RUN_LIVE_DB"] = prior

    db_names = [db for e in events if isinstance(e, tuple) and e[0] == "restore_backup" for db in e[2:]]
    assert len(db_names) == 1
    db = db_names[0]
    assert db.startswith("zz_rehearsal_"), f"scratch naming contract broken: {db}"
    # exact lifecycle order: container up -> restore -> connect -> drop
    assert events[:3] == ["ensure_running", ("restore_backup", "/tmp/opencode/client.bak", db),
                          ("connect", db)]
    assert events[-1] == ("drop_database", db)
    assert cur.executed == ["S1", "S2"], "statements ran against the scratch cursor"
    assert r["dropped"] is True and r["db"] == db
    assert r["summary"] == {"total": 2, "ok": 2, "benign": 0, "fatal": 0}
    assert any("dropped" in m for m in logs)


def test_rehearse_drops_scratch_even_when_restore_fails():
    prior = _with_env(enabled=True)
    events = []
    saved_modules = _install_fake_stack(events, _FakeCursor(),
                                        restore_error=RuntimeError("restore blew up"))
    raised = False
    try:
        try:
            executor.rehearse("/tmp/opencode/client.bak", ["S1"], log=lambda m: None)
        except RuntimeError as e:
            raised = str(e) == "restore blew up"
    finally:
        executor.docker_mgmt, executor.restore = saved_modules
        if prior is not None:
            os.environ["RUN_LIVE_DB"] = prior
    assert raised, "the restore error must propagate to the caller"
    # finally-block guarantee: even a half-restored scratch DB gets dropped
    drops = [e for e in events if isinstance(e, tuple) and e[0] == "drop_database"]
    assert len(drops) == 1 and drops[0][1].startswith("zz_rehearsal_")


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
