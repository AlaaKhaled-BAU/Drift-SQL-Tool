"""ProcedureChangeLog is the one signal a schema diff can never produce on its own:
WHO changed an object and WHEN (attribution), and whether a fix that was once made
is now silently gone -- e.g. reverted by a later re-image (the "lost fix" tripwire,
PLAN-03 §6). Both come straight out of a trigger-populated table that already ships
in Olives_BO; this module just reads it.

S1 (2026-07-26): this file used to carry its own naive normalize_sql (bare
regex comment-stripping, no string-literal/bracketed-identifier awareness)
-- the literal-aware code_spans()-based hardening in diffing.py was never
propagated here. A definition containing something like N'-- not a
comment' inside a string literal would have its content wrongly treated
as a real comment and stripped, which could flip the lost-fix tripwire's
verdict either way (a real reverted fix missed, or a genuinely-applied
fix falsely flagged as lost) -- exactly the "crown jewel" feature this
tool has that nothing else can replace, so its normalization needs the
same rigor diffing.py's does. Now imports diffing.normalize_sql directly
instead of maintaining a second, weaker copy.
"""
import pymssql

from . import config, diffing
from .inspect_objects import fetch_by_names


def _connect(db_name):
    return pymssql.connect(
        server="127.0.0.1", port=config.HOST_PORT,
        user=config.SA_USER, password=config.SA_PASSWORD,
        database=db_name, timeout=30, login_timeout=10,
    )


def _has_change_log(cur) -> bool:
    cur.execute(
        "SELECT COUNT(*) AS n FROM sys.tables WHERE name = 'ProcedureChangeLog'"
    )
    return cur.fetchone()["n"] > 0


def inspect(db_name: str, side_label: str, drifted_bare_names: set, log) -> dict:
    """Returns attribution rows for drifted objects, and lost-fix candidates for
    objects that currently look clean but whose logged history disagrees."""
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)

    if not _has_change_log(cur):
        log(f"  [{side_label}] no ProcedureChangeLog table -- attribution unavailable for this side")
        conn.close()
        return {"attribution": [], "lost_fixes": [], "trigger_present": False}

    cur.execute("SELECT COUNT(*) AS n FROM dbo.ProcedureChangeLog")
    total_rows = cur.fetchone()["n"]
    log(f"  [{side_label}] ProcedureChangeLog present, {total_rows} row(s) logged")

    attribution = []
    if drifted_bare_names:
        rows = fetch_by_names(
            cur,
            "SELECT ObjectName, EventType, LoginName, HostName, IPAddress, ChangeTime "
            "FROM dbo.ProcedureChangeLog "
            "WHERE ObjectName IN ({ph}) "
            "ORDER BY ObjectName, ChangeTime DESC",
            drifted_bare_names,
        )
        for row in rows:
            attribution.append({
                "side": side_label,
                "object": row["ObjectName"],
                "event": row["EventType"],
                "login": row["LoginName"],
                "host": row["HostName"],
                "ip": row["IPAddress"],
                "when": str(row["ChangeTime"]),
            })

    # lost-fix tripwire: objects the diff called CLEAN (not in drifted_bare_names)
    # but whose most recent logged NewDefinition disagrees with what's live now.
    cur.execute(
        "SELECT ObjectName, ObjectSchema, MAX(ChangeTime) AS last_change "
        "FROM dbo.ProcedureChangeLog GROUP BY ObjectName, ObjectSchema"
    )
    latest_per_object = cur.fetchall()

    lost_fixes = []
    for row in latest_per_object:
        name, schema = row["ObjectName"], row["ObjectSchema"] or "dbo"
        if name in drifted_bare_names:
            continue  # already surfaced as active drift, not "lost"
        cur.execute(
            "SELECT TOP 1 NewDefinition, LoginName, ChangeTime FROM dbo.ProcedureChangeLog "
            "WHERE ObjectName = %s AND ObjectSchema = %s ORDER BY ChangeTime DESC",
            (name, schema),
        )
        logged = cur.fetchone()
        if not logged or not logged["NewDefinition"]:
            continue
        cur.execute(
            "SELECT OBJECT_DEFINITION(OBJECT_ID(QUOTENAME(%s) + '.' + QUOTENAME(%s))) AS def",
            (schema, name),
        )
        current = cur.fetchone()
        current_def = current["def"] if current else None
        if current_def is None:
            continue  # object no longer exists at all -- different, out-of-scope case
        if diffing.normalize_sql(logged["NewDefinition"]) != diffing.normalize_sql(current_def):
            lost_fixes.append({
                "side": side_label,
                "object": f"[{schema}].[{name}]",
                "logged_by": logged["LoginName"],
                "logged_at": str(logged["ChangeTime"]),
            })

    if lost_fixes:
        log(f"  [{side_label}] {len(lost_fixes)} possible LOST FIX(ES) -- logged change no longer live")
    conn.close()
    return {"attribution": attribution, "lost_fixes": lost_fixes, "trigger_present": True}
