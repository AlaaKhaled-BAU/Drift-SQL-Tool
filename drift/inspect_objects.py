"""Pull object definitions + column sets from a restored DB before it's dropped.
Two jobs:
  1. Targeted capture for the changed-set only (~1k objects, not all ~1500) --
     used to build the per-finding diff (diffing.py).
  2. A cheap hash sweep over EVERY programmable object -- used to catch
     formatting-only differences that sqlpackage's ignore-options make
     invisible to the structural compare (they never show up as "Alter" at
     all, so there's nothing to capture there; this is the only way to see
     them). HASHBYTES over OBJECT_DEFINITION is exactly PLAN-03 §7's "raw
     hash tripwire" option, repurposed here for a concrete job instead of
     being a vague fallback.

ponytail: each module in this codebase (restore.py, changelog.py, convert.py)
already keeps its own local _connect() rather than sharing one -- following
that existing convention here rather than introducing a shared dbconn module
under time pressure. Real DRY debt, not urgent: 4 near-identical ~8-line
connect functions. Upgrade path: drift/dbconn.py, swap all four call sites.

D1a flag-rendering convention (2026-07-26): FK/index/check-constraint state
flags (DISABLED, NOT TRUSTED, etc) are appended as `[FLAGS: ...]`, NEVER as
a `-- comment` or `/* block */`. This is load-bearing, not cosmetic:
diffing.normalize_sql() deliberately STRIPS both comment styles before
comparing two definitions (so a real body edit isn't lost in comment
noise) -- verified live, a `-- DISABLED` suffix on otherwise-identical text
made diff_programmable() classify a genuinely disabled FK as
change_kind="formatting_only" (invisible, cosmetic-only) instead of
"structural" (real drift), which is the exact opposite of what D1a exists
to fix. `[...]` survives because code_spans() treats bracketed text as a
byte-exact-preserved identifier span, never comment-stripped or casefolded.
Do not "clean up" these into SQL comments.
"""
import re

import pymssql

from . import config, diffing

_EXTRA_ALTER_TABLE_RE = re.compile(r"ALTER\s+TABLE\s+\[([^\]]+)\]", re.IGNORECASE)
_EXTRA_INDEX_ON_RE = re.compile(r"\bON\s+\[([^\]]+)\]", re.IGNORECASE)
_EXTRA_FK_REF_RE = re.compile(r"REFERENCES\s+\[([^\]]+)\]", re.IGNORECASE)

_PROGRAMMABLE_TYPES = ("P", "V", "FN", "IF", "TF", "TR")


def _connect(db_name):
    return pymssql.connect(
        server="127.0.0.1", port=config.HOST_PORT,
        user=config.SA_USER, password=config.SA_PASSWORD,
        database=db_name, timeout=60, login_timeout=10,
    )


def fetch_by_names(cur, query_template: str, names) -> list:
    """D3: runs `query_template` (containing exactly one `{ph}` spot for an
    IN-clause value list) once per <=1000-name batch, with names passed as
    real pymssql parameters -- never f-string-interpolated into the SQL
    text. Object names come from sys.objects (server-controlled, not
    user input), so this was never externally exploitable, but an object
    legitimately named with an embedded quote would have produced a
    malformed query; parameters make that a non-issue by construction
    rather than by trusting the input shape.

    pymssql substitutes %s CLIENT-side (not a server-side prepared
    statement), so SQL Server's 2100-parameter ceiling does not apply here
    -- the 1000-batch is for query-TEXT-size sanity, not that limit.
    Shared by inspect_objects.py/dependencies.py/changelog.py (the three
    files with this exact shape) rather than duplicated three times: unlike
    _connect() above (trivial, low-risk either way), a batching+
    parameterization loop is exactly the kind of logic where two hand-
    copied versions drift out of sync -- measured real cost of that pattern
    elsewhere this session (drift/statements.py's _is_begin_tran bug)."""
    names = list(names)
    rows = []
    for i in range(0, len(names), 1000):
        batch = names[i : i + 1000]
        ph = ",".join(["%s"] * len(batch))
        cur.execute(query_template.format(ph=ph), tuple(batch))
        rows.extend(cur.fetchall())
    return rows


def get_definitions(db_name: str, bare_names: set) -> dict:
    """bare object name -> exact CREATE ... source text, for the given names only."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT o.name, m.definition FROM sys.sql_modules m "
        "JOIN sys.objects o ON m.object_id = o.object_id "
        "WHERE o.name IN ({ph})",
        bare_names,
    )
    out = {row["name"]: row["definition"] for row in rows}
    conn.close()
    return out


def get_columns(db_name: str, bare_table_names: set) -> dict:
    """bare table name -> [{name, type, max_length, precision, scale, nullable,
    is_pk}, ...], for the given tables only. max_length/precision/scale matter:
    a bare type-name compare would miss nvarchar(50) -> nvarchar(4000) or
    decimal(10,2) -> decimal(18,4) entirely -- a real structural change with
    no width/precision info to catch it."""
    if not bare_table_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    out = {name: [] for name in bare_table_names}
    rows = fetch_by_names(
        cur,
        "SELECT t.name AS table_name, c.name, ty.name AS type_name, "
        "       c.max_length, c.precision, c.scale, c.is_nullable, "
        "       COALESCE(ic.is_primary_key, 0) AS is_pk "
        "FROM sys.tables t "
        "JOIN sys.columns c ON c.object_id = t.object_id "
        "JOIN sys.types ty ON c.user_type_id = ty.user_type_id "
        "LEFT JOIN ( "
        "    SELECT ic.object_id, ic.column_id, i.is_primary_key FROM sys.index_columns ic "
        "    JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id "
        "    WHERE i.is_primary_key = 1 "
        ") ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id "
        "WHERE t.name IN ({ph}) ORDER BY t.name, c.column_id",
        bare_table_names,
    )
    for row in rows:
        out[row["table_name"]].append({
            "name": row["name"], "type": row["type_name"],
            "max_length": row["max_length"], "precision": row["precision"], "scale": row["scale"],
            "nullable": bool(row["is_nullable"]), "is_pk": bool(row["is_pk"]),
        })
    conn.close()
    return out


def get_all_table_names(db_name: str) -> set[str]:
    """Bare table names on the given database (user tables only)."""
    conn = _connect(db_name)
    cur = conn.cursor()
    cur.execute("SELECT name FROM sys.tables WHERE is_ms_shipped = 0")
    out = {row[0] for row in cur.fetchall()}
    conn.close()
    return out


def schema_from_qualified_name(object_name: str) -> str:
    parts = object_name.strip("[]").split("].[")
    return parts[0] if len(parts) >= 2 else "dbo"


def _extra_parent_table(sql: str) -> str | None:
    m = _EXTRA_ALTER_TABLE_RE.search(sql)
    if m:
        return m.group(1)
    m = _EXTRA_INDEX_ON_RE.search(sql)
    return m.group(1) if m else None


def _extra_referenced_table(sql: str) -> str | None:
    m = _EXTRA_FK_REF_RE.search(sql)
    return m.group(1) if m else None


def collect_extras_for_table(defs: dict, bare_table_name: str) -> list[str]:
    """Canonical DDL strings in defs whose parent table is bare_table_name."""
    out = []
    for sql in defs.values():
        if not isinstance(sql, str):
            continue
        if _extra_parent_table(sql) == bare_table_name:
            out.append(sql)
    return out


def build_table_bundle(
    bare_name: str,
    schema: str,
    columns: list[dict],
    extras_sql: list,
    existing_tables: set[str],
) -> dict | None:
    """CREATE TABLE + attachable extras for an added SqlTable finding.

    extras_sql entries are SQL strings or dicts with sql/table_name/referenced_table.
    FK extras are omitted when referenced_table is not in existing_tables."""
    if not columns:
        return None

    pk_cols = [c["name"] for c in columns if c.get("is_pk")]
    col_parts = [diffing.column_ddl(c) for c in columns]
    if pk_cols:
        col_parts.append(f"PRIMARY KEY ({', '.join(f'[{n}]' for n in pk_cols)})")

    qualified = f"[{schema}].[{bare_name}]"
    create_sql = f"CREATE TABLE {qualified}({', '.join(col_parts)});"

    extras: list[str] = []
    omitted_fks: list[dict] = []
    for item in extras_sql:
        if isinstance(item, str):
            sql = item
            parent = _extra_parent_table(sql) or bare_name
            ref = _extra_referenced_table(sql)
        else:
            sql = item.get("sql") or ""
            parent = item.get("table_name") or _extra_parent_table(sql) or bare_name
            ref = item.get("referenced_table") or _extra_referenced_table(sql)

        if parent != bare_name or not sql:
            continue
        if ref and ref not in existing_tables:
            omitted_fks.append({"sql": sql, "referenced_table": ref})
            continue
        extras.append(sql)

    bundle: dict = {"create_sql": create_sql, "extras": extras}
    if omitted_fks:
        bundle["omitted_fks"] = omitted_fks
    return bundle


_SQLPACKAGE_TYPE_BY_OBJTYPE = {
    "P": "SqlProcedure", "V": "SqlView", "TR": "SqlDmlTrigger",
    "FN": "SqlScalarFunction", "IF": "SqlInlineTableValuedFunction",
    "TF": "SqlMultiStatementTableValuedFunction",
}


def get_definition_hashes(db_name: str) -> dict:
    """bare name -> (SqlPackage-style type label, raw-text SHA256) for every
    programmable object. Cheap: a 32-byte hash per object, not the full text.
    Used only to detect that two definitions differ at all -- structural or
    formatting-only is decided afterward by the caller."""
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    cur.execute(
        "SELECT o.name, o.type, HASHBYTES('SHA2_256', OBJECT_DEFINITION(o.object_id)) AS h "
        "FROM sys.objects o WHERE o.type IN ('P','V','FN','IF','TF','TR') "
        "AND OBJECT_DEFINITION(o.object_id) IS NOT NULL"
    )
    out = {}
    for row in cur.fetchall():
        obj_type = _SQLPACKAGE_TYPE_BY_OBJTYPE.get(row["type"].strip(), row["type"].strip())
        out[row["name"]] = (obj_type, row["h"])
    conn.close()
    return out


def get_encrypted_names(db_name: str) -> set:
    """Objects whose definition is NULL despite sys.sql_modules having a row --
    WITH ENCRYPTION. These must be flagged 'uncomparable', never silently
    treated as 'same' (PLAN-03 §6 guard)."""
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    cur.execute(
        "SELECT o.name FROM sys.objects o JOIN sys.sql_modules m ON o.object_id = m.object_id "
        "WHERE m.definition IS NULL"
    )
    out = {row["name"] for row in cur.fetchall()}
    conn.close()
    return out


# --- Extended object types (qwen-review L-3): none of these are
# sys.sql_modules objects, so OBJECT_DEFINITION can't see them. Each
# reconstructs a canonical, deterministic text form from catalog views --
# same idea as convert.py's table-column reconstruction, just applied more
# broadly. Returned in the SAME {bare_name: text} shape as get_definitions(),
# so pipeline.py can merge them straight into master_defs/client_defs and
# reuse diffing.py's existing text-diff/richdiff path unchanged: a body
# difference is a body difference whether the text came from real SQL
# Server source or a catalog reconstruction, as long as both sides used the
# identical reconstruction. This is what closes the "correct role/name but
# no body-level capture" gap noted in metrics.py's coverage note.

_SIZED_TYPES_EXT = {"varchar", "nvarchar", "char", "nchar", "varbinary", "binary"}
_PRECISION_TYPES_EXT = {"decimal", "numeric"}


def _rendered_type_ext(type_name, max_length, precision, scale) -> str:
    if type_name in _SIZED_TYPES_EXT:
        length = "max" if max_length == -1 else (
            max_length // 2 if type_name in ("nvarchar", "nchar") else max_length
        )
        return f"{type_name}({length})"
    if type_name in _PRECISION_TYPES_EXT:
        return f"{type_name}({precision},{scale})"
    return type_name


def get_index_definitions(db_name: str, bare_names: set) -> dict:
    """"table.index" (qualified) name -> canonical CREATE INDEX text.

    D3 Change B (2026-07-27): keyed by table+index, NOT bare index name alone.
    Unlike every other type in this file, a SQL Server index name is unique
    only WITHIN its table, not schema-wide -- two different tables can
    legally reuse the same index name. Grouping/keying by bare index name
    alone would silently merge two unrelated indexes' rows into one dict
    entry (wrong column list on whichever sorted-second). The WHERE-clause
    filter below still matches on bare name (that's what compare.bare_name()
    puts in bare_names, and what a colliding pair both need to match to be
    fetched at all) -- only the grouping/output key is qualified. Caller
    (pipeline.py's _enrich) looks up via compare.qualified_name(), which
    produces this exact "table.index" format from the raw DeployReport name.

    D1a (2026-07-26): is_disabled/fill_factor/is_padded/ignore_dup_key added
    -- a disabled index changes query plans and fill factor changes
    behavior under write load, neither visible in the base CREATE INDEX
    shape alone. Filegroup deliberately NOT tracked: measured live against
    the real restored DB, 730/730 indexes live on PRIMARY and the database
    has exactly 1 filegroup -- there is no real signal to lose here, and
    adding it would be unused complexity. Revisit if a client DB is ever
    seen using more than one filegroup."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT i.name AS index_name, t.name AS table_name, i.type_desc, "
        "       i.is_unique, i.is_primary_key, i.is_unique_constraint, i.filter_definition, "
        "       i.is_disabled, i.fill_factor, i.is_padded, i.ignore_dup_key, "
        "       c.name AS col_name, ic.is_descending_key, ic.is_included_column, ic.key_ordinal "
        "FROM sys.indexes i "
        "JOIN sys.tables t ON i.object_id = t.object_id "
        "JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id "
        "JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id "
        "WHERE i.name IN ({ph}) "
        "ORDER BY i.name, ic.is_included_column, ic.key_ordinal, ic.index_column_id",
        bare_names,
    )
    by_index = {}
    for row in rows:
        key = (row["table_name"], row["index_name"])
        e = by_index.setdefault(key, {"meta": row, "key_cols": [], "inc_cols": []})
        if row["is_included_column"]:
            e["inc_cols"].append(row["col_name"])
        else:
            e["key_cols"].append(f"{row['col_name']} {'DESC' if row['is_descending_key'] else 'ASC'}")
    conn.close()

    out = {}
    for (table_name, name), e in by_index.items():
        m = e["meta"]
        kind = m["type_desc"].replace("_", " ")
        unique = "UNIQUE " if (m["is_unique"] or m["is_unique_constraint"]) and not m["is_primary_key"] else ""
        pk = "PRIMARY KEY " if m["is_primary_key"] else ""
        head = f"CREATE {pk}{unique}{kind} INDEX [{name}] ON [{table_name}] ({', '.join(e['key_cols'])})"
        if e["inc_cols"]:
            head += f" INCLUDE ({', '.join(e['inc_cols'])})"
        if m["filter_definition"]:
            head += f" WHERE {m['filter_definition']}"
        flags = []
        if m["is_disabled"]:
            flags.append("DISABLED")
        if m["fill_factor"]:  # 0 means "server default", not a real fill factor -- not worth flagging
            flags.append(f"FILLFACTOR={m['fill_factor']}")
        if m["is_padded"]:
            flags.append("PAD_INDEX")
        if m["ignore_dup_key"]:
            flags.append("IGNORE_DUP_KEY")
        out[f"{table_name}.{name}"] = head + ";" + (f"  [FLAGS: {', '.join(flags)}]" if flags else "")
    return out


def get_fk_definitions(db_name: str, bare_names: set) -> dict:
    """bare FK name -> canonical ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY text.

    D1a (2026-07-26): is_disabled/is_not_trusted/is_not_for_replication added
    -- a NOCHECK-disabled or untrusted FK enforces nothing at the engine
    level even though its CREATE-time column/table shape is unchanged.
    Without these, a client that ran `ALTER TABLE ... NOCHECK CONSTRAINT`
    against a real, enforced FK would reconstruct to byte-identical text
    on both sides -- a genuine, dangerous drift that this capture would
    otherwise be structurally unable to see (this is the exact gap D1's
    no_difference reclassification depends on closing first)."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT fk.name, tp.name AS parent_table, tr.name AS ref_table, "
        "       fk.delete_referential_action_desc, fk.update_referential_action_desc, "
        "       fk.is_disabled, fk.is_not_trusted, fk.is_not_for_replication, "
        "       cp.name AS parent_col, cr.name AS ref_col, fkc.constraint_column_id "
        "FROM sys.foreign_keys fk "
        "JOIN sys.tables tp ON fk.parent_object_id = tp.object_id "
        "JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id "
        "JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id "
        "JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id AND cp.column_id = fkc.parent_column_id "
        "JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id "
        "WHERE fk.name IN ({ph}) "
        "ORDER BY fk.name, fkc.constraint_column_id",
        bare_names,
    )
    by_fk = {}
    for row in rows:
        e = by_fk.setdefault(row["name"], {"meta": row, "pcols": [], "rcols": []})
        e["pcols"].append(row["parent_col"])
        e["rcols"].append(row["ref_col"])
    conn.close()

    out = {}
    for name, e in by_fk.items():
        m = e["meta"]
        flags = []
        if m["is_disabled"]:
            flags.append("DISABLED")
        if m["is_not_trusted"]:
            flags.append("NOT TRUSTED")
        if m["is_not_for_replication"]:
            flags.append("NOT FOR REPLICATION")
        out[name] = (
            f"ALTER TABLE [{m['parent_table']}] ADD CONSTRAINT [{name}] FOREIGN KEY "
            f"({', '.join(e['pcols'])}) REFERENCES [{m['ref_table']}] ({', '.join(e['rcols'])}) "
            f"ON DELETE {m['delete_referential_action_desc']} ON UPDATE {m['update_referential_action_desc']};"
            + (f"  [FLAGS: {', '.join(flags)}]" if flags else "")
        )
    return out


def get_check_constraint_definitions(db_name: str, bare_names: set) -> dict:
    """bare check-constraint name -> canonical text. sys.check_constraints
    already exposes the exact predicate text (like OBJECT_DEFINITION does
    for programmable objects), so this needs no reconstruction.

    D1a (2026-07-26): is_disabled/is_not_trusted added -- same reasoning as
    the FK getter above: a NOCHECK-disabled or untrusted CHECK constraint
    validates nothing even though its predicate text is unchanged."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT cc.name, OBJECT_NAME(cc.parent_object_id) AS table_name, cc.definition, "
        "       cc.is_disabled, cc.is_not_trusted "
        "FROM sys.check_constraints cc WHERE cc.name IN ({ph})",
        bare_names,
    )
    out = {}
    for row in rows:
        flags = []
        if row["is_disabled"]:
            flags.append("DISABLED")
        if row["is_not_trusted"]:
            flags.append("NOT TRUSTED")
        out[row["name"]] = (
            f"ALTER TABLE [{row['table_name']}] ADD CONSTRAINT [{row['name']}] CHECK {row['definition']};"
            + (f"  [FLAGS: {', '.join(flags)}]" if flags else "")
        )
    conn.close()
    return out


def get_default_constraint_definitions(db_name: str, bare_names: set) -> dict:
    """bare default-constraint name -> canonical text (sys.default_constraints
    exposes the exact expression text directly, same as check constraints)."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT dc.name, OBJECT_NAME(dc.parent_object_id) AS table_name, c.name AS column_name, dc.definition "
        "FROM sys.default_constraints dc "
        "JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id "
        "WHERE dc.name IN ({ph})",
        bare_names,
    )
    out = {row["name"]: f"ALTER TABLE [{row['table_name']}] ADD CONSTRAINT [{row['name']}] "
                         f"DEFAULT {row['definition']} FOR [{row['column_name']}];"
           for row in rows}
    conn.close()
    return out


def get_sequence_definitions(db_name: str, bare_names: set) -> dict:
    """bare sequence name -> canonical CREATE SEQUENCE text.
    start_value/increment/minimum_value/maximum_value are typed sql_variant
    in sys.sequences -- pymssql/FreeTDS doesn't decode that, it comes back as
    raw bytes (str()'d into the DDL as e.g. b'\\x01\\x00\\x00\\x00' instead of
    1). CAST to bigint makes it a real integer -- covers every real-world
    sequence (tinyint through bigint); a decimal/numeric-typed sequence
    (rare) would still misrender, a disclosed narrower limitation.

    D1a (2026-07-26): is_cached/cache_size added -- affects gap behavior on
    a server restart (cached values not yet consumed are lost), a real
    operational difference invisible in start/increment/min/max alone."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT name, TYPE_NAME(system_type_id) AS type_name, "
        "       CAST(start_value AS bigint) AS start_value, CAST(increment AS bigint) AS increment, "
        "       CAST(minimum_value AS bigint) AS minimum_value, CAST(maximum_value AS bigint) AS maximum_value, "
        "       is_cycling, is_cached, cache_size "
        "FROM sys.sequences WHERE name IN ({ph})",
        bare_names,
    )
    out = {}
    for row in rows:
        if row["is_cached"]:
            cache_clause = f"CACHE {row['cache_size']}" if row["cache_size"] else "CACHE"
        else:
            cache_clause = "NO CACHE"
        out[row["name"]] = (
            f"CREATE SEQUENCE [{row['name']}] AS {row['type_name']} "
            f"START WITH {row['start_value']} INCREMENT BY {row['increment']} "
            f"MINVALUE {row['minimum_value']} MAXVALUE {row['maximum_value']} "
            f"{'CYCLE' if row['is_cycling'] else 'NO CYCLE'} {cache_clause};"
        )
    conn.close()
    return out


def get_synonym_definitions(db_name: str, bare_names: set) -> dict:
    """bare synonym name -> canonical CREATE SYNONYM text (base_object_name
    IS the definition -- no reconstruction needed)."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(cur, "SELECT name, base_object_name FROM sys.synonyms WHERE name IN ({ph})", bare_names)
    out = {row["name"]: f"CREATE SYNONYM [{row['name']}] FOR {row['base_object_name']};" for row in rows}
    conn.close()
    return out


def get_table_type_definitions(db_name: str, bare_names: set) -> dict:
    """bare table-type (TVP) name -> canonical CREATE TYPE ... AS TABLE text.
    Same column reconstruction as get_columns(), against
    sys.table_types.type_table_object_id instead of sys.tables.object_id.

    D1a (2026-07-26): is_memory_optimized added -- a memory-optimized table
    type uses a different storage engine entirely (In-Memory OLTP), a
    difference the column-shape-only reconstruction can't see on its own.
    Rendered as real WITH (MEMORY_OPTIMIZED = ON) syntax, not a comment --
    unlike the other D1a additions (FK/index/check/sequence flags, which
    have no single-statement CREATE syntax slot to sit in), this one is
    valid CREATE TYPE syntax."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT tt.name AS type_name, tt.is_memory_optimized, c.name, ty.name AS col_type, "
        "       c.max_length, c.precision, c.scale, "
        "       c.is_nullable, COALESCE(ic.is_primary_key, 0) AS is_pk "
        "FROM sys.table_types tt "
        "JOIN sys.columns c ON c.object_id = tt.type_table_object_id "
        "JOIN sys.types ty ON c.user_type_id = ty.user_type_id "
        "LEFT JOIN ( "
        "    SELECT ic.object_id, ic.column_id, i.is_primary_key FROM sys.index_columns ic "
        "    JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id "
        "    WHERE i.is_primary_key = 1 "
        ") ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id "
        "WHERE tt.name IN ({ph}) ORDER BY tt.name, c.column_id",
        bare_names,
    )
    by_type = {}
    for row in rows:
        by_type.setdefault(row["type_name"], []).append(row)
    conn.close()

    out = {}
    for name, cols in by_type.items():
        col_lines = []
        for c in cols:
            t = _rendered_type_ext(c["col_type"], c["max_length"], c["precision"], c["scale"])
            nullability = "NULL" if c["is_nullable"] else "NOT NULL"
            pk = " PRIMARY KEY" if c["is_pk"] else ""
            col_lines.append(f"    [{c['name']}] {t} {nullability}{pk}")
        suffix = " WITH (MEMORY_OPTIMIZED = ON)" if cols[0]["is_memory_optimized"] else ""
        out[name] = f"CREATE TYPE [{name}] AS TABLE (\n" + ",\n".join(col_lines) + f"\n){suffix};"
    return out


def get_udt_definitions(db_name: str, bare_names: set) -> dict:
    """bare user-defined scalar type name -> canonical CREATE TYPE ... FROM text."""
    if not bare_names:
        return {}
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    rows = fetch_by_names(
        cur,
        "SELECT ty.name, base.name AS base_type, ty.max_length, ty.precision, ty.scale, ty.is_nullable "
        "FROM sys.types ty JOIN sys.types base ON ty.system_type_id = base.user_type_id AND base.is_user_defined = 0 "
        "WHERE ty.is_user_defined = 1 AND ty.is_table_type = 0 AND ty.name IN ({ph})",
        bare_names,
    )
    out = {}
    for row in rows:
        t = _rendered_type_ext(row["base_type"], row["max_length"], row["precision"], row["scale"])
        out[row["name"]] = f"CREATE TYPE [{row['name']}] FROM {t} {'NULL' if row['is_nullable'] else 'NOT NULL'};"
    conn.close()
    return out


def get_database_options(db_name: str) -> dict:
    """DB-level collation + compatibility level. A difference here changes
    runtime semantics even when every object's own text is identical
    (qwen-review L-11) -- captured unconditionally, cheap (single row)."""
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    cur.execute("SELECT collation_name, compatibility_level FROM sys.databases WHERE database_id = DB_ID()")
    row = cur.fetchone()
    conn.close()
    return {"collation": row["collation_name"], "compatibility_level": row["compatibility_level"]}


def get_all_module_settings(db_name: str) -> dict:
    """bare name -> (SqlPackage-style type label, {"ansi_nulls": bool,
    "quoted_identifier": bool}) for EVERY programmable object -- a full
    sweep, same shape/reasoning as get_definition_hashes(), NOT scoped to an
    already-known changed set. Required because a pure settings-only
    difference (byte-identical OBJECT_DEFINITION on both sides, only the
    session settings baked in at CREATE time differ) produces zero signal
    from sqlpackage's DeployReport AND zero signal from the hash-sweep --
    such an object would never even enter the changed-object set to be
    checked otherwise. Confirmed live via the qwen-review follow-up
    surgical battery: without this sweep, an ANSI_NULLS-only flip on an
    otherwise-identical real procedure produced literally zero findings in
    either direction (L-11's actual failure mode, not a hypothetical one)."""
    conn = _connect(db_name)
    cur = conn.cursor(as_dict=True)
    cur.execute(
        "SELECT o.name, o.type, m.uses_ansi_nulls, m.uses_quoted_identifier "
        "FROM sys.sql_modules m JOIN sys.objects o ON m.object_id = o.object_id"
    )
    out = {}
    for row in cur.fetchall():
        obj_type = _SQLPACKAGE_TYPE_BY_OBJTYPE.get(row["type"].strip(), row["type"].strip())
        out[row["name"]] = (obj_type, {"ansi_nulls": bool(row["uses_ansi_nulls"]),
                                        "quoted_identifier": bool(row["uses_quoted_identifier"])})
    conn.close()
    return out
