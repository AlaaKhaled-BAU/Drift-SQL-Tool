"""PLAN-V4 B.4 -- the tolerant statement runner: one engine, two targets.

Rehearsal mode (default) restores a client .bak into a scratch container and
runs the assembled script there first -- result = measured facts, not
predictions. Live mode reuses the exact same runner pointed at the real
target behind a rehearsal gate + explicit confirm (caller's job, mirroring
the assemble-confirm guard).

Error classification is a CONFIG TABLE seeded from the field (B.4), not
message-text pattern matching: SQL Server error numbers are stable, message
text is not, and msgno arrives for free on every pymssql database exception.

House rule honored here too: skipped items appear in the final report with
their messages -- visible, never silent. Noise is bucketed, never buried.
"""
import os
import time
from pathlib import Path

try:
    from . import docker_mgmt
    from . import restore
except ImportError:
    # Bare `import executor` (no package parent) can't resolve these siblings'
    # own package-relative imports either -- classify/run_statement/run_script
    # stay fully usable; rehearse() refuses loudly rather than half-working.
    docker_mgmt = None
    restore = None

# The four known-benign classes (PLAN-V4 B.4). Anything in this set is
# skip-and-log; anything else aborts the run at that statement.
BENIGN_CLASSES = {"dependent", "truncation", "duplicate_key", "unique_index"}

# msgno -> class. Seeded from the field-observed failures of column alters:
#   5074 object depends on column / 3725+3726+3729..3732 constraint/index/FK
#   dependency family            -> dependent  (preflight should have caught most)
#   8152/2628 string-or-binary truncation       -> truncation (data-dependent)
#   2601/2627 duplicate key                     -> duplicate_key
#   1505/1507/1913 unique index creation/dup    -> unique_index
ERROR_BY_MSGNO = {
    5074: "dependent", 3725: "dependent", 3726: "dependent", 3729: "dependent",
    3730: "dependent", 3731: "dependent", 3732: "dependent",
    8152: "truncation", 2628: "truncation",
    2601: "duplicate_key", 2627: "duplicate_key",
    1505: "unique_index", 1507: "unique_index", 1913: "unique_index",
}

_PREVIEW_CHARS = 120


def _to_text(v) -> str:
    """pymssql hands back raw bytes messages (FreeTDS); decode defensively --
    a weird byte sequence must never crash the reporter."""
    if isinstance(v, bytes):
        return v.decode("utf-8", errors="replace")
    return str(v)


def _extract(exc) -> tuple[int, str, bool]:
    """(msgno, message, had_sql_shape) from any exception.

    pymssql's MSSQLDatabaseException carries args[0] = msgno (int) and
    args[1] = bytes message. We deliberately do NOT isinstance-check against
    pymssql types: generic Exception.args handling keeps this decoupled from
    the driver version AND makes fake-cursor tests work with a plain
    Exception subclass carrying .args=(msgno, b"msg"). Anything without that
    shape (TypeError from our own code, KeyboardInterrupt-ish oddities,
    empty args) reports had_sql_shape=False -> python_error.
    """
    args = getattr(exc, "args", ()) or ()
    if args and isinstance(args[0], int) and not isinstance(args[0], bool):
        return args[0], " ".join(_to_text(a) for a in args[1:]).strip(), True
    msg = " ".join(_to_text(a) for a in args).strip() or str(exc) or exc.__class__.__name__
    return 0, msg, False


def classify_error(exc) -> tuple[str, int]:
    """-> (class, msgno). Known benign msgno -> its config-table class;
    any other SQL-shaped error -> ("fatal", msgno); non-SQL errors ->
    ("python_error", 0)."""
    msgno, _, shaped = _extract(exc)
    if not shaped:
        return ("python_error", 0)
    return (ERROR_BY_MSGNO.get(msgno, "fatal"), msgno)


def _preview(sql_text: str) -> str:
    """Collapse ALL whitespace to single spaces (reports stay line-oriented)
    then hard-truncate -- a 200KB proc body must never end up verbatim in an
    execution report."""
    flat = " ".join(sql_text.split())
    if len(flat) <= _PREVIEW_CHARS:
        return flat
    return flat[:_PREVIEW_CHARS] + "..."


def run_statement(cur, sql_text: str) -> dict:
    """Execute ONE statement under a cursor. -> {"status": "ok"|"benign"|"fatal",
    "class", "msgno", "msg"}. Benign = known-skippable per ERROR_BY_MSGNO;
    fatal = SQL-shaped but unclassifiable OR any non-SQL Python error."""
    try:
        cur.execute(sql_text)
    except Exception as exc:  # noqa: BLE001 - classification IS this function's job
        msgno, msg, shaped = _extract(exc)
        if shaped and msgno in ERROR_BY_MSGNO:
            return {"status": "benign", "class": ERROR_BY_MSGNO[msgno], "msgno": msgno, "msg": msg}
        if shaped:
            return {"status": "fatal", "class": "fatal", "msgno": msgno, "msg": msg}
        return {"status": "fatal", "class": "python_error", "msgno": 0, "msg": msg}
    return {"status": "ok", "class": "ok", "msgno": 0, "msg": ""}


def run_script(cur, statements: list[str]) -> dict:
    """Run every statement individually; CONTINUE past benign failures, STOP
    at the first fatal one (later statements are never attempted -- running
    half a teardown/rebuild pair blind could compound damage).

    -> {"report": [{"sql_preview","status","class","msgno","msg"}, ...],
        "summary": {"total","ok","benign","fatal"}}
    total counts EXECUTED statements only; a stopped batch honestly shows a
    short report rather than pretending the tail ran."""
    report = []
    ok = benign = fatal = 0
    for sql_text in statements:
        r = run_statement(cur, sql_text)
        report.append({"sql_preview": _preview(sql_text), **r})
        if r["status"] == "ok":
            ok += 1
        elif r["status"] == "benign":
            benign += 1
        else:
            fatal += 1
            break
    return {"report": report, "summary": {"total": len(report), "ok": ok, "benign": benign, "fatal": fatal}}


def rehearse(bak_host_path, statements: list[str], log) -> dict:
    """SAFETY CONTRACT (read before touching): .bak IN, scratch DB OUT, always.

    Restores bak_host_path into a fresh zz_rehearsal_<epoch> scratch database
    inside the drift-tool container, runs `statements` there via run_script,
    and DROPS the scratch database in a finally block -- client data is never
    left resident. There is no parameter by which this function can target a
    live server: it only ever talks to the local scratch container through
    restore._connect(), so 'rehearsal hit production' is unrepresentable by
    construction.

    Hermetic default: with RUN_LIVE_DB unset this returns {"skipped": ...}
    BEFORE any docker call -- the unit suite must never spin up containers or
    touch real .baks. Set RUN_LIVE_DB=1 (rehearsal still scratches-only) to
    actually execute.
    """
    if not os.environ.get("RUN_LIVE_DB"):
        return {
            "skipped": True,
            "reason": "RUN_LIVE_DB not set -- rehearsal would start the scratch container "
                      "and restore a real .bak; set RUN_LIVE_DB=1 to allow (still "
                      "scratch-only, never a live target)",
        }
    if docker_mgmt is None or restore is None:
        raise RuntimeError(
            "executor imported standalone (no package context); rehearse() needs "
            "`from drift import executor` so docker_mgmt/restore can load"
        )

    # Deferred until past the env gate on purpose: importing restore pulls
    # pymssql/config side effects, which the hermetic path above must never pay.
    docker_mgmt.ensure_running(log)

    db = f"zz_rehearsal_{int(time.time())}"
    try:
        # Path() coercion: restore_backup calls .resolve()/.name on it, and
        # callers naturally hand back whatever the file browser gave them.
        restore.restore_backup(Path(bak_host_path), db, log)
        cur = restore._connect(db).cursor()
        result = run_script(cur, statements)
    finally:
        # drop_database is itself best-effort (logs, never raises), so a
        # failed restore mid-flight still tears down whatever partial DB exists.
        restore.drop_database(db, log)
    log(f"rehearsal complete in scratch [{db}] (database dropped)")
    return {**result, "db": db, "dropped": True}
