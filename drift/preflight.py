"""PLAN-V4 B.3 -- preflight column-dependency teardown/rebuild plans.

Most ALTER COLUMN failures are predictable from catalogs we already know how
to query (same family of catalog views inspect_objects.py uses). This module
turns error-*skipping* (executor.py's benign classes) into error-*avoidance*
for the deterministic majority:

    for each retyped/dropped column:
        find dependent objects (indexes, default/check constraints, FKs,
                                statistics, computed-column references)
        emit ordered script: DROP dependent -> ALTER COLUMN -> recreate
                             verbatim from captured definitions

What genuinely remains unfixable at generate time lands in `warnings`, never
as guessed SQL -- same honesty posture as scriptgen.py's manual_review
("definition not captured" beats a plausible-looking fabrication).

SECURITY RULE (house): table/column names reach these catalog queries ONLY as
%s scalar bind parameters, never interpolated into SQL text. Object names are
server-controlled so this was never externally exploitable, but parameters
make an embedded-quote name a non-issue by construction rather than by
trusting the input shape -- identical reasoning to inspect_objects.fetch_by_names.
"""
# No sibling imports needed: this module is pure (takes an open cursor, returns
# dicts), which keeps it unit-testable with a fake cursor and free of pymssql
# at import time.

# Fixed execution order of the six catalog queries issued per call to
# find_column_dependencies(). Documented because test_preflight.py scripts a
# fake cursor whose fetchall() sequences are consumed in exactly this order:
#   1. defaults   (sys.default_constraints)
#   2. checks     (sys.check_constraints)
#   3. fks        (sys.foreign_keys + foreign_key_columns)
#   4. stats      (sys.stats + stats_columns)
#   5. computed   (sys.computed_columns)
#   6. indexes    (sys.indexes + index_columns + tables + columns)


def _q(name) -> str:
    """Bracket-quote one identifier for embedding in emitted DDL. Doubling an
    embedded ']' is SQL Server's documented escape -- cheap correctness for
    the pathological-but-legal object name."""
    return "[" + str(name).replace("]", "]]") + "]"


def find_column_dependencies(cur, table: str, column: str) -> dict:
    """Catalog sweep for everything that can block an ALTER COLUMN on
    [table].[column]. `cur` must be a dict-row cursor (inspect_objects
    convention: conn.cursor(as_dict=True)).

    Returns {"indexes": [{"name","is_unique","is_primary_key", ...captured
    detail...}], "defaults": [{"name","definition"}],
    "checks": [{"name","definition"}], "fks": [{"name"}], "stats":[{"name"}],
    "computed": bool}.

    Query order matches _QUERY_ORDER above; each execute() passes
    params=(table, column) as scalars only.

    Index entries carry MORE than the three contract fields: key/include
    columns, direction, type_desc and filter_definition are captured too --
    without them build_column_alter_plan could only ever warn on every indexed
    column and the module would be dead weight. Defaults/checks carry the
    engine's own exact expression text (catalog `definition`), which is what
    makes byte-equal recreation possible instead of guessed.
    """
    # 1. defaults bound to this column. sys.default_constraints.definition IS
    #    the exact DEFAULT expression (e.g. "((0))") -- no reconstruction.
    cur.execute(
        "SELECT dc.name, dc.definition FROM sys.default_constraints dc "
        "JOIN sys.tables t ON t.object_id = dc.parent_object_id "
        "JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id "
        "WHERE t.name = %s AND c.name = %s ORDER BY dc.name",
        (table, column),
    )
    defaults = [{"name": r["name"], "definition": r["definition"]} for r in cur.fetchall()]

    # 2. check constraints on this column -- definition IS the exact predicate.
    cur.execute(
        "SELECT cc.name, cc.definition FROM sys.check_constraints cc "
        "JOIN sys.tables t ON t.object_id = cc.parent_object_id "
        "JOIN sys.columns c ON c.object_id = cc.parent_object_id AND c.column_id = cc.parent_column_id "
        "WHERE t.name = %s AND c.name = %s ORDER BY cc.name",
        (table, column),
    )
    checks = [{"name": r["name"], "definition": r["definition"]} for r in cur.fetchall()]

    # 3. FKs touching this column from EITHER side: altering a column that a
    #    foreign key points AT fails just as hard as one it references
    #    (3726 fires on the referenced side). UNION of both roles.
    cur.execute(
        "SELECT fk.name FROM sys.foreign_keys fk "
        "JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id "
        "JOIN sys.tables t ON t.object_id = fkc.parent_object_id "
        "JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id "
        "WHERE t.name = %s AND c.name = %s "
        "UNION "
        "SELECT fk.name FROM sys.foreign_keys fk "
        "JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id "
        "JOIN sys.tables rt ON rt.object_id = fkc.referenced_object_id "
        "JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id "
        "WHERE rt.name = %s AND rc.name = %s",
        (table, column, table, column),
    )
    fks = [{"name": r["name"]} for r in cur.fetchall()]

    # 4. statistics objects over this column (auto-created _WA_Sys_* ones are
    #    the common blocker). Dropped before ALTER, regenerated afterwards via
    #    UPDATE STATISTICS -- no explicit recreation text exists or is needed.
    cur.execute(
        "SELECT s.name FROM sys.stats s "
        "JOIN sys.tables t ON t.object_id = s.object_id "
        "WHERE t.name = %s AND EXISTS ("
        "  SELECT 1 FROM sys.stats_columns sc "
        "  JOIN sys.columns c ON c.object_id = sc.object_id AND c.column_id = sc.column_id "
        "  WHERE sc.object_id = s.object_id AND sc.stats_id = s.stats_id AND c.name = %s) "
        "ORDER BY s.name",
        (table, column),
    )
    stats = [{"name": r["name"]} for r in cur.fetchall()]

    # 5. is THIS column itself a computed column? An ALTER COLUMN on one can't
    #    succeed at all -- surfaced as a warning, never worked around silently.
    cur.execute(
        "SELECT cc.name FROM sys.computed_columns cc "
        "JOIN sys.tables t ON t.object_id = cc.object_id "
        "WHERE t.name = %s AND cc.name = %s",
        (table, column),
    )
    computed = len(cur.fetchall()) > 0

    # 6. every index over this column, one row per index-column; grouped in
    #    Python preserving server-side ORDER BY (name, key_ordinal). LEFT JOINs
    #    so a zero-key index shape (e.g. columnstore placeholder rows) still
    #    yields its meta row and gets an honest warning downstream rather than
    #    silently vanishing from the plan.
    cur.execute(
        "SELECT i.name, i.is_unique, i.is_primary_key, i.type_desc, i.filter_definition, "
        "       c.name AS col_name, ic.is_descending_key, ic.is_included_column "
        "FROM sys.indexes i "
        "JOIN sys.tables t ON t.object_id = i.object_id "
        "LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id "
        "LEFT JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id "
        "WHERE t.name = %s AND EXISTS ("
        "  SELECT 1 FROM sys.index_columns dep "
        "  JOIN sys.columns dc ON dc.object_id = dep.object_id AND dc.column_id = dep.column_id "
        "  WHERE dep.object_id = i.object_id AND dep.index_id = i.index_id AND dc.name = %s) "
        "ORDER BY i.name, ic.key_ordinal",
        (table, column),
    )
    by_name = {}
    for r in cur.fetchall():
        e = by_name.setdefault(r["name"], {
            "name": r["name"],
            "is_unique": bool(r["is_unique"]),
            "is_primary_key": bool(r["is_primary_key"]),
            "type_desc": r["type_desc"],
            "filter": r["filter_definition"],
            "key_cols": [],       # [(col_name, "ASC"|"DESC"), ...] in key order
            "include_cols": [],   # [col_name, ...]
        })
        if r["col_name"] is None:
            continue
        if r["is_included_column"]:
            e["include_cols"].append(r["col_name"])
        else:
            e["key_cols"].append((r["col_name"], "DESC" if r["is_descending_key"] else "ASC"))

    return {
        "defaults": defaults,
        "checks": checks,
        "fks": fks,
        "stats": stats,
        "computed": computed,
        "indexes": list(by_name.values()),
    }


def build_column_alter_plan(table: str, column: str, alter_stmt: str, deps: dict) -> dict:
    """Ordered teardown -> alter -> rebuild plan for one column alter.

    {"steps": [{"phase": "teardown"|"alter"|"rebuild", "sql": str}],
     "warnings": [str]}

    Phase discipline is strict: every teardown step precedes the single alter
    step, every rebuild step follows it. Rebuild SQL is rendered ONLY from
    definitions captured in `deps` -- anything lacking captured detail becomes
    a warnings entry instead of fabricated SQL.

    Safety policy for incomplete captures (rationale, keep with the code):
      - FKs: we capture only the NAME (per contract), yet teardown must still
        drop them or the ALTER dies with 3726. A missing FK fails LOUDLY later
        (next bad insert), unlike a missing default which silently changes
        data-fill behavior -- so FK drop proceeds with a loud must-re-add
        warning, while silent-loss objects below refuse to drop at all.
      - default/check constraint with no captured definition, or an index with
        no usable name / no key columns: SKIPPED ENTIRELY (no DROP either).
        Dropping what we cannot verbatim-recreate converts a failed ALTER into
        permanent silent schema damage -- strictly worse than letting the
        executor's benign `dependent` class catch it at run time (B.3's
        closing paragraph routes data-dependent residue there on purpose).
      - stats are always safe to drop: UPDATE STATISTICS regenerates them.
    """
    qt = _q(table)
    steps = []
    warnings = []

    def add(phase, sql):
        steps.append({"phase": phase, "sql": sql})

    # ---- teardown -----------------------------------------------------------
    for d in deps.get("defaults", []):
        if d.get("name") and d.get("definition"):
            add("teardown", f"ALTER TABLE {qt} DROP CONSTRAINT {_q(d['name'])};")
        else:
            warnings.append(
                f"default constraint {d.get('name')!r} has no captured definition -- "
                f"not dropped (cannot be recreated verbatim); expect a dependent error at run time"
            )

    for c in deps.get("checks", []):
        if c.get("name") and c.get("definition"):
            add("teardown", f"ALTER TABLE {qt} DROP CONSTRAINT {_q(c['name'])};")
        else:
            warnings.append(
                f"check constraint {c.get('name')!r} has no captured definition -- "
                f"not dropped (cannot be recreated verbatim); expect a dependent error at run time"
            )

    for s in deps.get("stats", []):
        # Stats need no recreation text -- UPDATE STATISTICS rebuilds them.
        add("teardown", f"DROP STATISTICS {qt}.{_q(s['name'])};")

    for fk in deps.get("fks", []):
        add("teardown", f"ALTER TABLE {qt} DROP CONSTRAINT {_q(fk['name'])};")
        warnings.append(
            f"foreign key {fk['name']} was dropped and will NOT be recreated automatically "
            f"(only its name was captured) -- re-add it after the alter from the master-side DDL"
        )

    for ix in deps.get("indexes", []):
        if not ix.get("name"):
            warnings.append("an unnamed index depends on this column -- left untouched")
            continue
        if ix.get("is_primary_key"):
            if not ix.get("key_cols"):
                warnings.append(
                    f"primary key {ix['name']!r} has no captured key columns -- left untouched"
                )
                continue
            add("teardown", f"ALTER TABLE {qt} DROP CONSTRAINT {_q(ix['name'])};")
        else:
            if not ix.get("key_cols"):
                warnings.append(
                    f"index {ix['name']!r} has no captured key columns -- left untouched"
                )
                continue
            add("teardown", f"DROP INDEX {_q(ix['name'])} ON {qt};")

    if deps.get("computed"):
        warnings.append(
            f"column {column!r} is COMPUTED -- the ALTER COLUMN will fail outright; "
            f"this needs a manual rewrite of the computed expression"
        )

    # ---- the alter itself, verbatim as given --------------------------------
    add("alter", alter_stmt)

    # ---- rebuild, verbatim from captured definitions ------------------------
    for ix in deps.get("indexes", []):
        if not ix.get("name") or not ix.get("key_cols"):
            continue  # already warned during teardown; nothing recreatable here
        cols = ", ".join(f"{_q(name)} {direction}" for name, direction in ix["key_cols"])
        if ix.get("is_primary_key"):
            sql = (
                f"ALTER TABLE {qt} ADD CONSTRAINT {_q(ix['name'])} "
                f"PRIMARY KEY {ix['type_desc']} ({cols});"
            )
        else:
            unique = "UNIQUE " if ix.get("is_unique") else ""
            sql = f"CREATE {unique}{ix['type_desc']} INDEX {_q(ix['name'])} ON {qt} ({cols})"
            if ix.get("include_cols"):
                sql += f" INCLUDE ({', '.join(_q(c) for c in ix['include_cols'])})"
            if ix.get("filter"):
                sql += f" WHERE {ix['filter']}"
            sql += ";"
        add("rebuild", sql)

    for d in deps.get("defaults", []):
        if d.get("name") and d.get("definition"):
            add("rebuild", f"ALTER TABLE {qt} ADD CONSTRAINT {_q(d['name'])} "
                           f"DEFAULT {d['definition']} FOR {_q(column)};")

    for c in deps.get("checks", []):
        if c.get("name") and c.get("definition"):
            add("rebuild", f"ALTER TABLE {qt} ADD CONSTRAINT {_q(c['name'])} CHECK {c['definition']};")

    # Final refresh: regenerates the stats dropped above (and any auto-stats
    # invalidated by the type change) -- the last phase, always.
    add("rebuild", f"UPDATE STATISTICS {qt};")

    return {"steps": steps, "warnings": warnings}
