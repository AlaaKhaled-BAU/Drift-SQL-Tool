"""Blast-radius / caller lookup, sourced from SQL Server's own compile-time
dependency catalog -- not the repo's db/vault_graph.json, which is regex-
parsed from proc bodies and confirmed dirty (called_by field actually holds
callees, only ~15% of procs have any caller edge at all, junk tokens in
reads_from -- verified directly against the file, not from memory).

sys.sql_expression_dependencies is populated by the engine at object-create/
compile time by actually parsing the T-SQL, so it's exact where it resolves
at all. Two real limits, stated up front rather than discovered later:
  - it cannot see through dynamic SQL (sp_executesql, EXEC(@sql)) -- a caller
    that only reaches an object via a string-built query is invisible here.
  - cross-database or otherwise unresolved references come back with
    is_ambiguous=1 and/or a NULL referencing/referenced id; reported as
    "unresolved", never silently folded into the confident caller list.

The database is already live in the scratch container at capture time (right
before teardown), so this is one more query on a connection that's already
open -- no new restore, no new infrastructure.
"""
import pymssql

from . import config
from .inspect_objects import fetch_by_names


def _connect(db_name):
    return pymssql.connect(
        server="127.0.0.1", port=config.HOST_PORT,
        user=config.SA_USER, password=config.SA_PASSWORD,
        database=db_name, timeout=60, login_timeout=10,
    )


def get_callers(db_name: str, bare_names: set) -> dict:
    """bare object name -> {"callers": [distinct caller names], "unresolved": n}
    for every name in bare_names that something in this database references."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT referencing.name AS caller_name, "
        "       d.referenced_entity_name AS callee_name, "
        "       d.is_ambiguous, d.referenced_id "
        "FROM sys.sql_expression_dependencies d "
        "JOIN sys.objects referencing ON d.referencing_id = referencing.object_id "
        "WHERE d.referenced_entity_name IN ({ph})",
        bare_names,
    )
    out = {}
    for row in rows:
        entry = out.setdefault(row["callee_name"], {"callers": set(), "unresolved": 0})
        if row["is_ambiguous"] or row["referenced_id"] is None:
            entry["unresolved"] += 1
        else:
            entry["callers"].add(row["caller_name"])
    conn.close()
    return {name: {"callers": sorted(v["callers"]), "unresolved": v["unresolved"]} for name, v in out.items()}


def get_dynamic_sql_users(db_name: str) -> set:
    """Procs that use EXEC(@sql)/sp_executesql -- a coarse but honest flag:
    dependency edges FROM these objects are unreliable (dynamic SQL is
    invisible to sys.sql_expression_dependencies), so a "0 callers" result
    for an object referenced only from inside one of these should be read as
    "0 callers found", not "confirmed 0 callers"."""
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    cur.execute(
        "SELECT o.name FROM sys.sql_modules m JOIN sys.objects o ON m.object_id = o.object_id "
        "WHERE m.definition LIKE '%sp_executesql%' OR m.definition LIKE '%EXEC(%' OR m.definition LIKE '%EXECUTE(%'"
    )
    out = {row["name"] for row in cur.fetchall()}
    conn.close()
    return out
