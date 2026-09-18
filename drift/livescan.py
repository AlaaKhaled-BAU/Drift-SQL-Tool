"""PLAN-V5 Lane B (blueprint C1) -- live quick-scan: seconds-fast triage over
two LIVE connections.

What this module does: runs two cheap catalog queries against each live
server -- object presence + module definition text from sys.objects/sys.sql_modules,
and column shape from sys.columns/sys.tables -- then quick_compare() diffs the
two snapshots with pure deterministic set logic. Definition text catches modified
procs the old tool never saw (it compared names only); the column diff catches
shape drift without restoring anything.

THE SAFETY RULE (blueprint C1, carried forward verbatim): scan is TRIAGE ONLY.
It routes you into the verified .bak pipeline (sqlpackage evidence-on-disk,
rehearsal, human gate). This module deliberately exposes NO script generation
whatsoever -- there is no emit/generate/script function anywhere in here, and
that absence IS the safety feature: a triage result cannot be misused as an
apply script because no apply script can be built from it. SCAN_ONLY is the
machine-checkable sentinel of that refusal (asserted by test_livescan.py).

Connection policy: live targets get their real server address -- config.HOST_PORT
is deliberately NOT used here (that port belongs to the scratch .bak container;
a live client server rarely listens there). SQL auth only: Windows auth is
unavailable from this Linux host, documented in the blueprint. Credentials come
from the caller (env/prompted upstream), never stored plaintext (C1).
"""
import pymssql

# Machine-checkable statement of the C1 safety rule: this flag exists so the
# UI/CLI can assert "triage mode" and so the test battery can pin the module's
# refusal to grow generation entry points.
SCAN_ONLY = True
MODULE_TEXT_WARN_BYTES = 2_097_152


def _objects_sql() -> str:
    """One row per user object: name, type_desc, and its module definition
    text (NULL for anything module-less -- tables, and any legacy object
    sys.sql_modules never recorded).

    LEFT JOIN (not inner) keeps module-less objects visible: dropping them
    would make the presence diff lie about tables. is_ms_shipped = 0 excludes
    system plumbing so both sides diff on USER objects only.
    """
    return """
    SELECT o.name,
           o.type_desc,
           m.definition AS definition
    FROM sys.objects o
    LEFT JOIN sys.sql_modules m ON m.object_id = o.object_id
    WHERE o.is_ms_shipped = 0
    ORDER BY o.name
    """


def _columns_sql() -> str:
    """One row per column of every user table: the full shape tuple
    (type name + max_length/precision/scale) that quick_compare needs to call
    a column 'altered'. sys.types join resolves the concrete type name
    ('varchar', not a type_id). User TABLES only -- views inherit their base
    table's columns and would double-report every drift."""
    return """
    SELECT t.name AS table_name,
           c.name AS column_name,
           ty.name AS type_name,
           c.max_length,
           c.precision,
           c.scale
    FROM sys.columns c
    JOIN sys.tables t ON t.object_id = c.object_id
    JOIN sys.types ty ON ty.user_type_id = c.user_type_id
    ORDER BY t.name, c.column_id
    """


def scan(cur) -> dict:
    """One connection's catalog snapshot, via a dict-row cursor
    (conn.cursor(as_dict=True) -- house convention, see datacopy docstring):

    {"objects": {bare_name: {"type": type_desc, "definition": text-or-None}},
     "columns": {"table.column": {"type": t, "max_length": n,
                                  "precision": p, "scale": s}}}

    Query order is fixed and documented (_objects_sql first, _columns_sql
    second) -- test_livescan.py scripts fake fetchalls against exactly that
    order. definition is T-SQL module text (or None for tables) passed through
    untouched for downstream string comparison.
    """
    # --- result set 1: objects + module definitions ---
    cur.execute(_objects_sql())
    objects = {}
    oversized = []
    for row in cur.fetchall():
        definition = row["definition"]
        objects[row["name"]] = {
            "type": row["type_desc"],
            "definition": definition,
        }
        if isinstance(definition, str) and len(definition) > MODULE_TEXT_WARN_BYTES:
            oversized.append(row["name"])

    # --- result set 2: column shapes of user tables ---
    cur.execute(_columns_sql())
    columns = {}
    for row in cur.fetchall():
        key = f"{row['table_name']}.{row['column_name']}"
        columns[key] = {
            "type": row["type_name"],
            "max_length": row["max_length"],
            "precision": row["precision"],
            "scale": row["scale"],
        }

    return {"objects": objects, "columns": columns, "oversized_modules": oversized}


def quick_compare(a: dict, b: dict) -> dict:
    """TRIAGE findings: a=source scan, b=target scan. Pure set logic over the
    snapshot dicts -- no SQL, no cursor, fully deterministic (sorted lists,
    stable even when input dicts were built in arbitrary order).

    {"missing_in_b": [names],   # in source, absent on target
     "extra_in_b": [names],     # on target, absent in source
     "body_changed": [names],   # same name both sides, definition differs --
                                # includes None-vs-text (module-less flipped
                                # to module-bearing or vice versa), because
                                # that flip IS a real catalog change
     "columns": {"added": ["t.c", ...], "removed": [...], "altered": [...]},
     "summary": counts}         # every bucket length + snapshot sizes

    Deliberately returns NO DDL and NO remediation text: these findings are a
    routing decision ("go run the verified pipeline"), nothing more.
    """
    a_obj, b_obj = a.get("objects", {}), b.get("objects", {})
    a_col, b_col = a.get("columns", {}), b.get("columns", {})

    missing_in_b = sorted(set(a_obj) - set(b_obj))
    extra_in_b = sorted(set(b_obj) - set(a_obj))

    # Same-name objects only; differing definition (including one side None) = changed.
    body_changed = sorted(
        name for name in set(a_obj) & set(b_obj)
        if a_obj[name].get("definition") != b_obj[name].get("definition")
    )

    cols_added = sorted(set(b_col) - set(a_col))
    cols_removed = sorted(set(a_col) - set(b_col))
    # Altered = present both sides but ANY shape component moved (type,
    # max_length, precision, scale). Name alone proves nothing: varchar(10)
    # -> varchar(50) shares a type string but changes storage behavior.
    cols_altered = sorted(
        key for key in set(a_col) & set(b_col)
        if a_col[key] != b_col[key]
    )

    return {
        "missing_in_b": missing_in_b,
        "extra_in_b": extra_in_b,
        "body_changed": body_changed,
        "columns": {
            "added": cols_added,
            "removed": cols_removed,
            "altered": cols_altered,
        },
        "summary": {
            "objects_a": len(a_obj),
            "objects_b": len(b_obj),
            "missing_in_b": len(missing_in_b),
            "extra_in_b": len(extra_in_b),
            "body_changed": len(body_changed),
            "columns_a": len(a_col),
            "columns_b": len(b_col),
            "columns_added": len(cols_added),
            "columns_removed": len(cols_removed),
            "columns_altered": len(cols_altered),
        },
    }


def connect(server: str, database: str, user: str | None, password: str | None):
    """Open ONE live-target connection (SQL auth only).

    No port kwarg ON PURPOSE: live targets use their real server address;
    config.HOST_PORT belongs to the scratch .bak container and must not leak
    into live connections. Windows auth is unavailable from this Linux host
    (documented limitation, blueprint C1) -- hence explicit user/password,
    supplied by the caller, never stored plaintext here. login_timeout=10
    mirrors restore._connect so a dead host fails in seconds, not minutes.
    timeout=60 matches the other catalog-querying siblings
    (inspect_objects/convert/changelog): big catalogs take a moment.
    """
    return pymssql.connect(
        server=server,
        database=database,
        user=user,
        password=password,
        timeout=60,
        login_timeout=10,
    )
