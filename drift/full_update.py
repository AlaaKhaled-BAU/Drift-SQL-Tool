"""Full Update renderer.

The script is ordered batches, not a transaction, and it does not restore
grants. The app writes files and does not execute them.

T5 calls ``render_full_update(left, right, rules, database=selected)`` for the
one selected database (the default). The checkbox calls
``render_full_update(left, right, rules, all_databases=True)``. ``database``
omitted and ``all_databases`` false scripts every user database present on
both sides, which is the fixture scope. Each ``files`` value uses ``\\n``.
Write them with ``write_sql_file``. Keys are ``{LeftSpelling}_schema.sql``,
``{LeftSpelling}_udtt.sql``, and ``unified_full_update.sql``. ``appendix`` is
the manual list; the same items follow a ``-- MANUAL`` line in the files.

A restored bak is connected under ``drift_left_<id>`` and stored under
``catalog_key_for_restore`` (``RESTORE HEADERONLY`` DatabaseName). ``USE``
and the file name follow that logical name.

Phase order inside one database:

- phase A  ``CREATE SCHEMA [name]`` for every non-dbo schema this script
  writes into. Each call is ``schema_batch``: that statement only, then GO,
  before any type, table, or module in that schema. dbo is omitted.
- phase B  table types whose rendered text differs. Drop non-excluded
  referencers, ``DROP TYPE`` inside ``TYPE_ID``, ``CREATE TYPE`` with at most
  one PRIMARY KEY, then ``CREATE OR ALTER`` of every module this file just
  dropped. An excluded or schema-bound referencer skips that type. Never
  DROP an excluded name. A PRIMARY KEY column is declared NOT NULL. A
  catalog row that marks that column nullable still creates the type and
  adds a manifest warning.
- phase C  sequences: CREATE if missing; a difference is manual.
- phase D  scalar types: CREATE if missing; a change is manual.
- phase E  CREATE TABLE if missing (identity on a new table). ALTER TABLE
  ADD for a nullable column, or one NOT NULL ADD that includes DEFAULT.
  A column of a PRIMARY KEY or UNIQUE constraint is declared NOT NULL in
  that CREATE TABLE or ADD. A nullable catalog row for that column is a
  manifest warning, not a skip. NOT NULL without a default, and identity
  or computed adds on an existing table, are manual.
- phase F  functions and views, one ``order_names`` call. A view is emitted
  when a referenced table gains a column, including an unchanged ``SELECT *``.
  Schema qualification comes from the catalog. Skip modules already emitted
  in phase B. A view, function, or trigger whose target database is absent
  from the right catalog is manual. Procedures stay in the script.
- phase G  procedures not already emitted, name order, excluded names omitted.
- phase H  triggers. Same absent-database rule as views.
- phase I  indexes. Primary key and unique constraints are
  ``ALTER TABLE ... ADD CONSTRAINT``. Other indexes are ``CREATE INDEX``.
  Drop referencing foreign keys first. A view index is emitted immediately
  after that view. Nothing is dropped unless this script recreates it.
- phase J  foreign keys, including every foreign key phase I dropped.
- phase K  manual appendix (comments and PRINT only).

Views and functions share one ``order_names`` graph. ``held_back`` is the
manual appendix: cycles, and every name that depends on a cycle.

Shapes
------
``order_names(names, edges) -> (executable_order, held_back)``
    ``edges`` are ``(dependent, referenced)``. The referenced name is first.
    Ties keep the input order of ``names``. ``held_back`` keeps that same
    input order. An edge with an endpoint outside ``names`` is ignored, so a
    view may depend on a table that is not in this graph.

``order_databases(names, edges) -> (order, warnings)``
    Same edge direction. ``warnings`` is ``[]``, or ``[DATABASE_CYCLE_WARNING]``
    when any database is held back. Databases that Kahn can place stay in
    that order. The held-back remainder is appended in ``casefold`` order.

``same_database(referenced_database_name, database_name) -> bool``
    ``None`` and ``""`` are this database. Otherwise compare with ``casefold``.
    ``olives_BO`` and ``Olives_BO`` match. There is no id column for this.

``schema_batch(schema_name) -> str``
    Exactly ``CREATE SCHEMA [schema_name]\\nGO\\n``.

``split_absent_targets(objects, dependencies, database_name, present_databases)
-> (auto, appendix)``
    ``objects`` items are ``{"name", "type"}`` in input order.
    ``dependencies`` items are ``{"from", "referenced_database_name"}``.
    Other dependency keys are ignored. A view, function, or trigger is
    appendix when any referenced database is not this database and is not
    present (``casefold``). Procedures stay in ``auto``. Both lists keep
    input order. A mapping of database name to payload works as
    ``present_databases`` because iteration yields the names.

``schema_object_order(object_names) -> list[dict]``
    ``object_names`` are ``schema.object`` keys. Each non-``dbo`` schema is
    ``{"kind": "schema", "schema": str, "batch": str}`` using the first-seen
    spelling. Every name is then ``{"kind": "object", "name": str}``.
    Schema batches are one group before every object. ``batch`` is
    ``schema_batch``. ``dbo`` is omitted.

A view whose text is unchanged but whose table gained a column is not flagged
here. T4 includes that view in the ``order_names`` input.
"""

DATABASE_CYCLE_WARNING = "dependency cycle among databases; using casefold name order"

# Views, functions, and triggers fail at create time when the other database
# is missing. Procedures keep deferred name resolution and stay executable.
_ABSENT_TARGET_TYPES = frozenset({
    "view",
    "function",
    "trigger",
    "sqlview",
    "sqlscalarfunction",
    "sqlinlinetablevaluedfunction",
    "sqlmultistatementtablevaluedfunction",
    "sqltrigger",
    "sqldmltrigger",
    "sqldatabaseddltrigger",
})


def order_names(names: list[str], edges: list[tuple[str, str]]) -> tuple[list[str], list[str]]:
    """Kahn order. Referenced name first. Cycles and their dependents are held back."""
    names = _unique(names)
    known = set(names)
    indegree = {name: 0 for name in names}
    dependents: dict[str, list[str]] = {name: [] for name in names}
    kept: list[tuple[str, str]] = []
    seen_edges: set[tuple[str, str]] = set()
    for dependent, referenced in edges:
        if dependent not in known or referenced not in known:
            continue
        key = (dependent, referenced)
        if key in seen_edges:
            continue
        seen_edges.add(key)
        kept.append(key)
        indegree[dependent] += 1
        dependents[referenced].append(dependent)

    remaining = set(names)
    order: list[str] = []
    while True:
        ready = [name for name in names if name in remaining and indegree[name] == 0]
        if not ready:
            break
        node = ready[0]
        remaining.remove(node)
        order.append(node)
        for dependent in dependents[node]:
            indegree[dependent] -= 1

    held_set = set(remaining)
    order_set = set(order)
    changed = True
    while changed:
        changed = False
        for dependent, referenced in kept:
            if dependent in order_set and referenced in held_set:
                order_set.remove(dependent)
                held_set.add(dependent)
                changed = True
    if len(order_set) != len(order):
        order = [name for name in order if name in order_set]
    held = [name for name in names if name in held_set]
    return order, held


def same_database(referenced_database_name: str | None, database_name: str) -> bool:
    """True when the reference does not leave ``database_name``."""
    if referenced_database_name is None or referenced_database_name == "":
        return True
    return referenced_database_name.casefold() == database_name.casefold()


def order_databases(names: list[str], edges: list[tuple[str, str]]) -> tuple[list[str], list[str]]:
    """Referenced database first. A cycle appends that remainder in casefold order."""
    order, held = order_names(names, edges)
    if not held:
        return order, []
    return order + sorted(held, key=str.casefold), [DATABASE_CYCLE_WARNING]


def schema_batch(schema_name: str) -> str:
    """One CREATE SCHEMA batch. The caller skips dbo."""
    return f"CREATE SCHEMA [{schema_name}]\nGO\n"


def split_absent_targets(
    objects: list[dict],
    dependencies: list[dict],
    database_name: str,
    present_databases,
) -> tuple[list[str], list[str]]:
    """Split views, functions, and triggers that reference a missing database."""
    present = {name.casefold() for name in present_databases}
    referenced_by_owner: dict[str, list] = {}
    for dependency in dependencies:
        owner = dependency.get("from")
        if not owner:
            continue
        referenced_by_owner.setdefault(owner, []).append(
            dependency.get("referenced_database_name")
        )

    auto: list[str] = []
    appendix: list[str] = []
    for obj in objects:
        name = obj["name"]
        if _references_absent_database(
            obj.get("type") or "",
            referenced_by_owner.get(name, []),
            database_name,
            present,
        ):
            appendix.append(name)
        else:
            auto.append(name)
    return auto, appendix


def schema_object_order(object_names: list[str]) -> list[dict]:
    """Schema batches first, in first-seen order, then the objects."""
    seen: set[str] = set()
    batches: list[dict] = []
    for name in object_names:
        schema = name.split(".", 1)[0] if "." in name else "dbo"
        key = schema.casefold()
        if not schema or key == "dbo" or key in seen:
            continue
        seen.add(key)
        batches.append({
            "kind": "schema",
            "schema": schema,
            "batch": schema_batch(schema),
        })
    for name in object_names:
        batches.append({"kind": "object", "name": name})
    return batches


def _references_absent_database(
    object_type: str,
    referenced_names: list,
    database_name: str,
    present: set[str],
) -> bool:
    if object_type.casefold() not in _ABSENT_TARGET_TYPES:
        return False
    for referenced in referenced_names:
        if same_database(referenced, database_name):
            continue
        if isinstance(referenced, str) and referenced.casefold() not in present:
            return True
    return False


def _unique(names: list[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for name in names:
        if name in seen:
            continue
        seen.add(name)
        unique.append(name)
    return unique

import pathlib

_PROCEDURE_TYPES = frozenset({"sqlprocedure", "procedure"})
_FUNCTION_TYPES = frozenset({
    "sqlscalarfunction",
    "sqlinlinetablevaluedfunction",
    "sqlmultistatementtablevaluedfunction",
    "sqltablevaluedfunction",
    "function",
})
_VIEW_TYPES = frozenset({"sqlview", "view"})
_TRIGGER_TYPES = frozenset({
    "sqldmltrigger",
    "sqltrigger",
    "trigger",
    "sqldatabaseddltrigger",
})
_TABLE_TYPES = frozenset({"sqltable", "table"})
_TABLE_TYPE_TYPES = frozenset({"sqluserdefinedtabletype", "tabletype"})
_SCALAR_UDT_TYPES = frozenset({"sqluserdefinedtype", "usertype"})
_SEQUENCE_TYPES = frozenset({"sequence", "sqlsequence"})
_MODULE_CODE = {
    "P": "SqlProcedure",
    "V": "SqlView",
    "FN": "SqlScalarFunction",
    "IF": "SqlInlineTableValuedFunction",
    "TF": "SqlMultiStatementTableValuedFunction",
    "TR": "SqlDmlTrigger",
}

_MODULE_SQL = """
SELECT s.name AS schema_name,
       o.name AS object_name,
       o.type AS object_type,
       m.definition AS definition,
       m.uses_ansi_nulls AS ansi_nulls,
       m.uses_quoted_identifier AS quoted_identifier,
       m.is_schema_bound AS schema_bound
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
LEFT JOIN sys.sql_modules AS m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0
  AND o.type IN ('P', 'V', 'FN', 'IF', 'TF', 'TR')
""".strip()

_COLUMN_SQL = """
SELECT s.name AS schema_name,
       t.name AS table_name,
       c.name AS column_name,
       ty.name AS type_name,
       c.max_length AS max_length,
       c.precision AS precision,
       c.scale AS scale,
       c.is_nullable AS nullable,
       ic.seed_value AS identity_seed,
       ic.increment_value AS identity_increment,
       cc.definition AS computed_definition,
       dc.definition AS default_definition
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.identity_columns AS ic
  ON ic.object_id = c.object_id AND ic.column_id = c.column_id
LEFT JOIN sys.computed_columns AS cc
  ON cc.object_id = c.object_id AND cc.column_id = c.column_id
LEFT JOIN sys.default_constraints AS dc
  ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id
""".strip()

_TABLE_TYPE_SQL = """
SELECT s.name AS schema_name,
       tt.name AS type_name,
       tt.is_memory_optimized AS memory_optimized,
       c.name AS column_name,
       ty.name AS data_type,
       c.max_length AS max_length,
       c.precision AS precision,
       c.scale AS scale,
       c.is_nullable AS nullable,
       pk.key_ordinal AS key_ordinal
FROM sys.table_types AS tt
JOIN sys.schemas AS s ON s.schema_id = tt.schema_id
JOIN sys.columns AS c ON c.object_id = tt.type_table_object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
LEFT JOIN (
    SELECT ic.object_id, ic.column_id, ic.key_ordinal
    FROM sys.index_columns AS ic
    JOIN sys.indexes AS i
      ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    WHERE i.is_primary_key = 1 AND ic.key_ordinal > 0
) AS pk ON pk.object_id = c.object_id AND pk.column_id = c.column_id
ORDER BY s.name, tt.name, c.column_id
""".strip()

_DEPENDENCY_SQL = """
SELECT OBJECT_SCHEMA_NAME(d.referencing_id) AS from_schema,
       OBJECT_NAME(d.referencing_id) AS from_name,
       d.referenced_schema_name AS referenced_schema_name,
       d.referenced_entity_name AS referenced_entity_name,
       d.referenced_database_name AS referenced_database_name,
       d.referenced_class_desc AS referenced_class_desc
FROM sys.sql_expression_dependencies AS d
WHERE d.referencing_class = 1
""".strip()

_INDEX_SQL = """
SELECT s.name AS schema_name,
       o.name AS object_name,
       i.name AS index_name,
       i.is_primary_key AS is_primary_key,
       i.is_unique_constraint AS is_unique_constraint,
       i.is_unique AS is_unique,
       i.type_desc AS type_desc,
       i.filter_definition AS filter_definition,
       c.name AS column_name,
       ic.key_ordinal AS key_ordinal,
       ic.is_included_column AS is_included_column,
       ic.is_descending_key AS is_descending_key
FROM sys.indexes AS i
JOIN sys.objects AS o ON o.object_id = i.object_id
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
JOIN sys.index_columns AS ic
  ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c
  ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE o.is_ms_shipped = 0
  AND o.type IN ('U', 'V')
  AND i.index_id > 0
  AND i.is_hypothetical = 0
  AND i.name IS NOT NULL
ORDER BY s.name, o.name, i.name, ic.is_included_column, ic.key_ordinal, ic.index_column_id
""".strip()

_FK_SQL = """
SELECT fk.name AS fk_name,
       SCHEMA_NAME(child.schema_id) AS schema_name,
       child.name AS table_name,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS referenced_schema,
       OBJECT_NAME(fk.referenced_object_id) AS referenced_table,
       refi.name AS referenced_index,
       pc.name AS parent_column,
       rc.name AS referenced_column
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.tables AS child ON child.object_id = fk.parent_object_id
JOIN sys.columns AS pc
  ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
JOIN sys.columns AS rc
  ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
JOIN sys.indexes AS refi
  ON refi.object_id = fk.referenced_object_id AND refi.index_id = fk.key_index_id
ORDER BY fk.name, fkc.constraint_column_id
""".strip()

_CHECK_SQL = """
SELECT s.name AS schema_name,
       t.name AS table_name,
       ck.name AS check_name,
       ck.definition AS definition
FROM sys.check_constraints AS ck
JOIN sys.tables AS t ON t.object_id = ck.parent_object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
""".strip()

_SEQUENCE_SQL = """
SELECT s.name AS schema_name,
       seq.name AS sequence_name,
       ty.name AS type_name,
       seq.start_value AS start_value,
       seq.increment AS increment,
       seq.minimum_value AS minimum_value,
       seq.maximum_value AS maximum_value,
       seq.is_cycling AS is_cycling,
       seq.is_cached AS is_cached,
       seq.cache_size AS cache_size
FROM sys.sequences AS seq
JOIN sys.schemas AS s ON s.schema_id = seq.schema_id
JOIN sys.types AS ty ON ty.user_type_id = seq.user_type_id
""".strip()

_SCALAR_UDT_SQL = """
SELECT s.name AS schema_name,
       ty.name AS type_name,
       base.name AS base_type,
       ty.max_length AS max_length,
       ty.precision AS precision,
       ty.scale AS scale,
       ty.is_nullable AS nullable
FROM sys.types AS ty
JOIN sys.schemas AS s ON s.schema_id = ty.schema_id
JOIN sys.types AS base
  ON ty.system_type_id = base.user_type_id AND base.is_user_defined = 0
WHERE ty.is_user_defined = 1 AND ty.is_table_type = 0
""".strip()


def catalog_key_for_restore(header: dict, physical_name: str) -> str:
    """Logical database name from the backup header.

    ``physical_name`` is the restore target (``drift_left_<id>``). It is not
    the catalog key, the ``USE`` name, or the output file name.
    """
    del physical_name
    logical = (header.get("database_name") or "").strip()
    if not logical:
        raise ValueError("RESTORE HEADERONLY DatabaseName is empty")
    return logical


def write_sql_file(path, text) -> None:
    """UTF-8 BOM plus CRLF, via ``Path.write_bytes`` (not text mode)."""
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
    path.write_bytes(b"\xef\xbb\xbf" + normalized.encode("utf-8"))


def render_add_primary_key(schema, table, constraint, columns, clustered: bool) -> str:
    """One ``ADD CONSTRAINT`` primary key. Not ``CREATE PRIMARY KEY ... INDEX``."""
    kind = "CLUSTERED" if clustered else "NONCLUSTERED"
    cols = ", ".join(f"[{c}]" for c in columns)
    return (
        f"ALTER TABLE [{schema}].[{table}] ADD CONSTRAINT [{constraint}] "
        f"PRIMARY KEY {kind} ({cols})"
    )


def render_table_type(schema: str, name: str, columns: list[dict], memory_optimized: bool) -> str:
    """``CREATE TYPE`` with at most one PRIMARY KEY covering every key column.

    Each key column is ``NOT NULL`` in this batch. Callers record a manifest
    warning when the catalog row for that column is nullable.
    """
    lines = []
    keys = []
    for col in columns or []:
        rendered = _type_text(col)
        nullability = _nullability_sql(col, _key_ordinal(col) is not None)
        lines.append(f"    {_br(col['name'])} {rendered} {nullability}")
        ordinal = _key_ordinal(col)
        if ordinal is not None:
            keys.append((ordinal, col["name"]))
    if keys:
        keys.sort(key=lambda item: (item[0], item[1].casefold()))
        listed = ", ".join(_br(item[1]) for item in keys)
        lines.append(f"    PRIMARY KEY ({listed})")
    suffix = " WITH (MEMORY_OPTIMIZED = ON)" if memory_optimized else ""
    body = ",\n".join(lines)
    return f"CREATE TYPE {_br(schema)}.{_br(name)} AS TABLE (\n{body}\n){suffix}"


def diff_catalogs(left: dict, right: dict) -> dict:
    """Casefold intersection. Script spelling is the left database and object key."""
    left_dbs = (left or {}).get("databases") or {}
    right_dbs = (right or {}).get("databases") or {}
    right_by = {_fold(name): (name, body) for name, body in right_dbs.items()}
    databases = []
    only_left = []
    matched = set()
    for name, body in left_dbs.items():
        hit = right_by.get(_fold(name))
        if hit is None:
            only_left.append(name)
            continue
        matched.add(_fold(name))
        right_name, right_body = hit
        pairs, only_right = _pair_objects(
            body.get("objects") or {},
            right_body.get("objects") or {},
        )
        databases.append({
            "name": name,
            "right_name": right_name,
            "pairs": pairs,
            "only_right": only_right,
            "dependencies": list(body.get("dependencies") or [])
            + list(right_body.get("dependencies") or []),
        })
    only_right = [name for name in right_dbs if _fold(name) not in matched]
    return {"databases": databases, "only_left": only_left, "only_right": only_right}


def render_full_update(
    left: dict,
    right: dict,
    rules: list[dict] | None = None,
    *,
    database: str | None = None,
    all_databases: bool = False,
) -> dict:
    """Render per-database schema and table-type files plus one unified script.

    ``files`` maps ``{db}_schema.sql``, ``{db}_udtt.sql``, and
    ``unified_full_update.sql`` to text that uses ``\\n``. ``appendix`` is the
    manual list (also stored on ``manifest``). Pass ``database`` for the
    default one-database scope. ``all_databases=True`` scripts every user
    database present on both sides and ignores ``database``.
    """
    diff = diff_catalogs(left, right)
    selected = diff["databases"]
    if database and not all_databases:
        wanted = database.casefold()
        selected = [item for item in selected if item["name"].casefold() == wanted]
    present = list(((right or {}).get("databases") or {}))
    names = [item["name"] for item in selected]
    by_name = {item["name"]: item for item in selected}
    edges = _database_edges(selected)
    order, db_warnings = order_databases(names, edges)

    rendered = []
    excluded: list[str] = []
    warnings: list[str] = []
    appendix: list[dict] = []
    only_right_objects: list[str] = []
    seen_excluded: set[str] = set()
    for name in order:
        scripted = _script_database(by_name[name], rules, present)
        rendered.append(scripted)
        appendix.extend(scripted["appendix"])
        warnings.extend(scripted["warnings"])
        only_right_objects.extend(scripted["only_right"])
        for bare in scripted["excluded"]:
            if bare.casefold() in seen_excluded:
                continue
            seen_excluded.add(bare.casefold())
            excluded.append(bare)

    files = {}
    unified_parts = [
        "-- unified_full_update.sql\n"
        "-- Ordered batches. Not a transaction. Grants are not restored.\n"
    ]
    for scripted in rendered:
        files[f"{scripted['name']}_schema.sql"] = scripted["schema_file"]
        files[f"{scripted['name']}_udtt.sql"] = scripted["udtt_file"]
        unified_parts.append(scripted["unified"])
    if appendix:
        unified_parts.append("-- MANUAL\n")
        unified_parts.extend(item["sql"] for item in appendix)
    files["unified_full_update.sql"] = "".join(unified_parts)
    manifest = {
        "excluded": excluded,
        "appendix": [{k: v for k, v in item.items() if k != "sql"} for item in appendix],
        "warnings": warnings,
        "databases_only_on_left": diff["only_left"],
        "databases_only_on_right": diff["only_right"],
        "objects_only_on_right": only_right_objects,
        "database_order": order,
        "database_warnings": db_warnings,
    }
    return {
        "files": files,
        "appendix": manifest["appendix"],
        "manifest": manifest,
    }


def capture_live_catalog(connector, database_name: str) -> dict:
    """Read one database. ``connector`` is called once, with ``database_name``.

    Queries are read-only and one statement each. The catalog key is the
    name passed in. A null module definition is recorded as encrypted.
    """
    conn = connector(database_name)
    try:
        cur = _cursor(conn)
        modules = _fetch(cur, _MODULE_SQL)
        columns = _fetch(cur, _COLUMN_SQL)
        table_types = _fetch(cur, _TABLE_TYPE_SQL)
        dependencies = _fetch(cur, _DEPENDENCY_SQL)
        indexes = _fetch(cur, _INDEX_SQL)
        checks = _fetch(cur, _CHECK_SQL)
        sequences = _fetch(cur, _SEQUENCE_SQL)
        scalar_types = _fetch(cur, _SCALAR_UDT_SQL)
        foreign_keys = _fetch(cur, _FK_SQL)
    finally:
        closer = getattr(conn, "close", None)
        if closer:
            closer()
    objects = _objects_from_capture(
        modules, columns, table_types, indexes, checks, sequences, scalar_types, foreign_keys,
    )
    return {
        "server_label": "live",
        "databases": {
            database_name: {
                "objects": objects,
                "dependencies": _dependencies_from_capture(dependencies),
            }
        },
    }


def _script_database(db: dict, rules, present_databases) -> dict:
    name = db["name"]
    pairs = db["pairs"]
    deps = db["dependencies"]
    appendix: list[dict] = []
    warnings: list[str] = []
    excluded = _excluded_names(pairs, rules)
    by_fold = {_fold(key): (key, left, right) for key, left, right in pairs}

    creates, adds, table_notes, changed, present_cols = _plan_tables(
        pairs, name, appendix, warnings,
    )
    phase_b, recreated, created_types = _plan_types(pairs, deps, rules, by_fold, appendix, warnings)
    view_sql, proc_sql, trigger_sql, emitted = _plan_modules(
        pairs, deps, rules, name, present_databases, changed, recreated, appendix, warnings,
    )
    index_sql, fk_sql, view_indexes = _plan_indexes(pairs, present_cols, appendix)
    view_sql = _attach_view_indexes(view_sql, view_indexes)
    other_sql = _plan_other(pairs, appendix)

    emitted_folds = set(recreated) | set(emitted) | set(created_types)
    for key, _left, _right in pairs:
        if key.casefold() in changed:
            emitted_folds.add(key.casefold())
    schemas = _schemas_for(pairs, emitted_folds, view_indexes)
    schema_sql = "".join(schema_batch(schema) for schema in schemas)
    phase_rest = "".join(creates + adds + view_sql + proc_sql + trigger_sql + other_sql + index_sql + fk_sql)
    manual_sql = "".join(item["sql"] for item in appendix)
    manual = ("-- MANUAL\n" + manual_sql) if appendix else ""
    use = f"USE {_br(name)}\nGO\n"
    schema_banner = (
        f"-- {name}_schema.sql\n"
        "-- Tables, constraints, views, functions, and procedures.\n"
    )
    udtt_banner = (
        f"-- {name}_udtt.sql\n"
        "-- User-defined table types. A module dropped here is created again in this file.\n"
    )
    udtt_body = phase_b or "-- No table-type changes.\n"
    return {
        "name": name,
        "schema_file": schema_banner + use + schema_sql + phase_rest + manual,
        "udtt_file": udtt_banner + use + phase_b_schemas(phase_b, schemas) + udtt_body,
        "unified": use + schema_sql + phase_b + phase_rest,
        "appendix": appendix,
        "excluded": excluded,
        "warnings": warnings,
        "only_right": [key for key, _obj in db["only_right"]],
        "notes": table_notes,
    }


def phase_b_schemas(phase_b: str, schemas: list[str]) -> str:
    """Schema batches belong with table types only when that file creates one."""
    if not phase_b:
        return ""
    needed = []
    for schema in schemas:
        token = f"[{schema}]."
        if token in phase_b and schema.casefold() != "dbo":
            needed.append(schema_batch(schema))
    return "".join(needed)


def _plan_tables(pairs, database, appendix, warnings):
    creates = []
    adds = []
    changed = set()
    present_cols = {}
    notes = []
    for key, left, right in pairs:
        if not _is(left, _TABLE_TYPES):
            continue
        schema, table = _ident(key, left)
        fold = key.casefold()
        key_folds = _key_column_folds(left)
        columns = left.get("columns") or []
        if right is None:
            for col in columns:
                if _column_in_key(col, key_folds):
                    _warn_nullable_key(warnings, schema, table, col)
            creates.append(_batch(_create_table_sql(schema, table, columns, key_folds)))
            changed.add(fold)
            present_cols[fold] = {_fold(col.get("name")) for col in columns}
            _note_schema_object(notes, schema)
            continue
        right_cols = {_fold(col.get("name")): col for col in (right.get("columns") or [])}
        have = set(right_cols)
        for col in columns:
            col_fold = _fold(col.get("name"))
            if col_fold in right_cols:
                if _column_signature(col) != _column_signature(right_cols[col_fold]):
                    _manual(
                        appendix, database,
                        f"{_br(schema)}.{_br(table)}.{_br(col['name'])}",
                        "column change cannot be applied in place",
                    )
                continue
            if col.get("identity"):
                _manual(
                    appendix, database,
                    f"{_br(schema)}.{_br(table)}.{_br(col['name'])}",
                    "identity add on an existing table",
                )
                continue
            if col.get("computed"):
                _manual(
                    appendix, database,
                    f"{_br(schema)}.{_br(table)}.{_br(col['name'])}",
                    "computed add on an existing table",
                )
                continue
            expr = _default_expr(col)
            if not _nullable(col) and not expr:
                rendered = _type_text(col)
                _manual(
                    appendix, database,
                    f"{_br(schema)}.{_br(table)}.{_br(col['name'])} {rendered}",
                    "NOT NULL without a default",
                )
                continue
            is_key = _column_in_key(col, key_folds)
            if is_key:
                _warn_nullable_key(warnings, schema, table, col)
            adds.append(_batch(_add_column_sql(schema, table, col, is_key)))
            have.add(col_fold)
            changed.add(fold)
            _note_schema_object(notes, schema)
        present_cols[fold] = have
    return creates, adds, notes, changed, present_cols


def _plan_types(pairs, deps, rules, by_fold, appendix, warnings):
    chunks = []
    recreated = set()
    created = []
    for key, left, right in pairs:
        if not _is(left, _TABLE_TYPE_TYPES):
            continue
        schema, name = _ident(key, left)
        memory = bool(left.get("memory_optimized") or left.get("is_memory_optimized"))
        left_sql = render_table_type(schema, name, left.get("columns") or [], memory)
        if right is not None:
            right_memory = bool(right.get("memory_optimized") or right.get("is_memory_optimized"))
            right_sql = render_table_type(schema, name, right.get("columns") or [], right_memory)
            if left_sql == right_sql:
                continue
        refs = _type_referencers(key, deps, by_fold)
        blockers = []
        droppable = []
        for ref_key, ref_left, ref_right in refs:
            obj = ref_left or ref_right
            if obj is None or not _is_module(obj):
                blockers.append(f"referencer {ref_key} cannot be rendered")
                continue
            qual = _qual(obj, ref_key)
            if _schema_bound(ref_left) or _schema_bound(ref_right):
                blockers.append(f"schema-bound referencer {qual}")
                continue
            if _name_excluded(ref_key, rules) or _name_excluded(obj.get("name") or "", rules):
                blockers.append(f"excluded referencer {qual}")
                continue
            if ref_left is None or not ref_left.get("definition"):
                blockers.append(f"referencer {qual} cannot be rendered")
                if ref_left and ref_left.get("encrypted"):
                    warnings.append(f"WITH ENCRYPTION {qual}")
                continue
            if ref_right is not None:
                droppable.append((ref_key, ref_left))
        if blockers:
            reason = "; ".join(blockers)
            chunks.append(
                f"PRINT 'SKIP {_br(schema)}.{_br(name)}';\n"
                f"-- SKIP {_br(schema)}.{_br(name)}: {reason}\n"
                "GO\n"
            )
            continue
        ordered = _recreate_order([item[0] for item in droppable], by_fold, deps)
        chosen = {item[0].casefold(): item[1] for item in droppable}
        for ref_key in ordered:
            ref_left = chosen[ref_key.casefold()]
            if _name_excluded(ref_key, rules) or _name_excluded(ref_left.get("name") or "", rules):
                continue
            chunks.append(_batch(f"DROP {_drop_word(ref_left)} {_qual(ref_left, ref_key)}"))
        chunks.append(_batch(
            f"IF TYPE_ID(N'{_br(schema)}.{_br(name)}') IS NOT NULL "
            f"DROP TYPE {_br(schema)}.{_br(name)}"
        ))
        for col in left.get("columns") or []:
            if _key_ordinal(col) is not None:
                _warn_nullable_key(warnings, schema, name, col)
        chunks.append(_batch(left_sql))
        for ref_key in ordered:
            ref_left = chosen[ref_key.casefold()]
            chunks.append(_emit_module(ref_left.get("definition") or "", _settings(ref_left)))
            recreated.add(ref_key.casefold())
        created.append(key.casefold())
    return "".join(chunks), recreated, created


def _plan_modules(pairs, deps, rules, database, present, changed, recreated, appendix, warnings):
    candidates = []
    for key, left, right in pairs:
        if not (_is(left, _VIEW_TYPES) or _is(left, _FUNCTION_TYPES) or _is(left, _TRIGGER_TYPES)):
            continue
        if key.casefold() in recreated:
            continue
        if _is(left, _FUNCTION_TYPES) and (
            _name_excluded(key, rules) or _name_excluded(left.get("name") or "", rules)
        ):
            continue
        if not _module_wanted(key, left, right, changed, deps, database):
            continue
        if not left.get("definition"):
            qual = _qual(left, key)
            warnings.append(f"WITH ENCRYPTION {qual}")
            _manual(appendix, database, qual, "WITH ENCRYPTION")
            continue
        candidates.append({"name": key, "type": left.get("type") or ""})

    auto, absent = split_absent_targets(candidates, deps, database, present)
    absent_set = set(absent)
    auto_set = set(auto)
    by_key = {key: (left, right) for key, left, right in pairs}
    for key in absent:
        ref = _missing_database(key, deps, database, present)
        target = f"[{ref}]" if ref else "another database"
        _manual(appendix, database, key, f"referenced database {target} is absent")

    vf_names = []
    trigger_names = []
    for item in candidates:
        if item["name"] not in auto_set:
            continue
        left, _right = by_key[item["name"]]
        if _is(left, _TRIGGER_TYPES):
            trigger_names.append(item["name"])
        else:
            vf_names.append(item["name"])
    order, held = order_names(vf_names, _module_edges(vf_names, deps))
    for key in held:
        _manual(appendix, database, key, "dependency cycle")
    view_sql = []
    emitted = set()
    for key in order:
        left, _right = by_key[key]
        view_sql.append((key, _emit_module(left.get("definition") or "", _settings(left))))
        emitted.add(key.casefold())
    proc_sql = []
    proc_names = []
    for key, left, right in pairs:
        if not _is(left, _PROCEDURE_TYPES):
            continue
        if key.casefold() in recreated:
            continue
        if _name_excluded(key, rules) or _name_excluded(left.get("name") or "", rules):
            continue
        if not left.get("definition"):
            warnings.append(f"WITH ENCRYPTION {_qual(left, key)}")
            _manual(appendix, database, _qual(left, key), "WITH ENCRYPTION")
            continue
        if right is not None and _text(left) == _text(right) and _settings(left) == _settings(right):
            continue
        proc_names.append(key)
    for key in sorted(proc_names, key=str.casefold):
        left, _right = by_key[key]
        proc_sql.append(_emit_module(left.get("definition") or "", _settings(left)))
        emitted.add(key.casefold())
    trigger_sql = []
    for key in sorted(trigger_names, key=str.casefold):
        if key in absent_set:
            continue
        left, _right = by_key[key]
        trigger_sql.append(_emit_module(left.get("definition") or "", _settings(left)))
        emitted.add(key.casefold())
    return view_sql, proc_sql, trigger_sql, emitted


def _plan_indexes(pairs, present_cols, appendix):
    """Return index batches, foreign-key batches, and per-view index batches."""
    index_sql = []
    fk_sql = []
    view_indexes = {}
    recreated_fks = set()
    dropped_fks = set()
    all_fks = _collect_fks(pairs)
    for key, left, right in pairs:
        if left is None or not (_is(left, _TABLE_TYPES) or _is(left, _VIEW_TYPES)):
            continue
        schema, table = _ident(key, left)
        left_idx = _index_map(left)
        right_idx = _index_map(right)
        batches = []
        for index_name, idx in left_idx.items():
            other = right_idx.get(index_name)
            create_sql = _index_create_sql(schema, table, idx)
            if other is not None and create_sql == _index_create_sql(schema, table, other):
                continue
            if not _index_columns_exist(key, idx, present_cols, right is None):
                _manual(
                    appendix, "",
                    f"{_br(schema)}.{_br(table)}.{_br(idx.get('name') or index_name)}",
                    "constraint cannot be recreated",
                )
                continue
            drop_fk_sql = []
            recreate = []
            if other is not None:
                for fk in all_fks:
                    if fk["side"] != "right":
                        continue
                    if not _fk_targets(fk, idx.get("name") or ""):
                        continue
                    ident = _fk_ident(fk)
                    if ident in dropped_fks:
                        continue
                    dropped_fks.add(ident)
                    drop_fk_sql.append(_batch(
                        f"ALTER TABLE {_br(fk['schema'])}.{_br(fk['table'])} "
                        f"DROP CONSTRAINT {_br(fk['name'])}"
                    ))
                    replacement = _matching_fk(all_fks, fk) or fk
                    recreate.append(_batch(_fk_create_sql(replacement)))
                    recreated_fks.add(_fk_ident(replacement))
                drop_sql = _index_drop_sql(schema, table, other)
                batches.append((drop_fk_sql, drop_sql, create_sql, recreate))
            else:
                batches.append(([], None, create_sql, []))
        if _is(left, _VIEW_TYPES):
            view_indexes[key.casefold()] = [
                (drop_fk_sql, drop_sql, create_sql) for drop_fk_sql, drop_sql, create_sql, _recreate in batches
            ]
            for _drop_fk_sql, _drop_sql, _create_sql, recreate in batches:
                fk_sql.extend(recreate)
            continue
        for drop_fk_sql, drop_sql, create_sql, recreate in batches:
            index_sql.extend(drop_fk_sql)
            if drop_sql:
                index_sql.append(_batch(drop_sql))
            index_sql.append(_batch(create_sql))
            fk_sql.extend(recreate)
    for fk in all_fks:
        if fk["side"] != "left":
            continue
        if _fk_ident(fk) in recreated_fks:
            continue
        twin = None
        for other in all_fks:
            if other["side"] == "right" and _fk_ident(other) == _fk_ident(fk):
                twin = other
                break
        if twin is not None and _fk_create_sql(twin) == _fk_create_sql(fk):
            continue
        fk_sql.append(_batch(_fk_create_sql(fk)))
        recreated_fks.add(_fk_ident(fk))
    return index_sql, fk_sql, view_indexes


def _attach_view_indexes(view_sql, view_indexes):
    merged = []
    for key, sql in view_sql:
        merged.append(sql)
        for drop_fk_sql, drop_sql, create_sql in view_indexes.get(key.casefold(), []):
            merged.extend(drop_fk_sql)
            if drop_sql:
                merged.append(_batch(drop_sql))
            merged.append(_batch(create_sql))
    return merged


def _plan_other(pairs, appendix):
    chunks = []
    for key, left, right in pairs:
        if not (_is(left, _SEQUENCE_TYPES) or _is(left, _SCALAR_UDT_TYPES)):
            continue
        schema, name = _ident(key, left)
        definition = (left.get("definition") or "").strip()
        if right is None:
            if definition:
                chunks.append(_batch(definition))
            else:
                _manual(appendix, "", f"{_br(schema)}.{_br(name)}", "definition was not captured")
            continue
        if _text(left) != _text(right):
            _manual(appendix, "", f"{_br(schema)}.{_br(name)}", "change cannot be applied in place")
    for key, left, right in pairs:
        if not left:
            continue
        schema, table = _ident(key, left)
        right_checks = {
            _fold(item.get("name")): item for item in ((right or {}).get("checks") or [])
        }
        for check in left.get("checks") or []:
            definition = (check.get("definition") or "").strip()
            label = f"{_br(schema)}.{_br(table)}.{_br(check.get('name') or '')}"
            if not definition:
                _manual(appendix, "", label, "check cannot be recreated verbatim")
                continue
            other = right_checks.get(_fold(check.get("name")))
            statement = (
                f"ALTER TABLE {_br(schema)}.{_br(table)} ADD CONSTRAINT {_br(check['name'])} "
                f"CHECK {definition}"
            )
            if other is None:
                chunks.append(_batch(statement))
            elif (other.get("definition") or "").strip() != definition:
                chunks.append(_batch(
                    f"ALTER TABLE {_br(schema)}.{_br(table)} DROP CONSTRAINT {_br(check['name'])}"
                ))
                chunks.append(_batch(statement))
    return chunks


def _database_edges(selected) -> list[tuple[str, str]]:
    scripted = {item["name"].casefold(): item["name"] for item in selected}
    edges = []
    seen = set()
    for item in selected:
        for dep in item["dependencies"]:
            ref = dep.get("referenced_database_name")
            if same_database(ref, item["name"]) or not isinstance(ref, str):
                continue
            target = scripted.get(ref.casefold())
            if not target or target.casefold() == item["name"].casefold():
                continue
            edge = (item["name"], target)
            if edge in seen:
                continue
            seen.add(edge)
            edges.append(edge)
    return edges


def _module_wanted(key, left, right, changed, deps, database) -> bool:
    if right is None:
        return True
    if _text(left) != _text(right) or _settings(left) != _settings(right):
        return True
    if not (_is(left, _VIEW_TYPES) or _is(left, _FUNCTION_TYPES)):
        return False
    fold = key.casefold()
    for dep in deps:
        if _fold(dep.get("from")) != fold:
            continue
        if not same_database(dep.get("referenced_database_name"), database):
            continue
        if _fold(dep.get("to")) in changed:
            return True
    return False


def _missing_database(key, deps, database, present):
    present_fold = {_fold(name) for name in present}
    for dep in deps:
        if _fold(dep.get("from")) != key.casefold():
            continue
        ref = dep.get("referenced_database_name")
        if same_database(ref, database):
            continue
        if isinstance(ref, str) and ref.casefold() not in present_fold:
            return ref
    return None


def _module_edges(names, deps) -> list[tuple[str, str]]:
    fold = {_fold(name): name for name in names}
    edges = []
    seen = set()
    for dep in deps:
        src = fold.get(_fold(dep.get("from")))
        if not src:
            continue
        target = fold.get(_fold(dep.get("to")))
        if target is None:
            target = dep.get("to") or ""
        if not target:
            continue
        edge = (src, target)
        if edge in seen:
            continue
        seen.add(edge)
        edges.append(edge)
    return edges


def _type_referencers(type_key, deps, by_fold):
    found = []
    seen = set()
    want = type_key.casefold()
    for dep in deps:
        if _fold(dep.get("to")) != want:
            continue
        klass = _fold(dep.get("to_class"))
        if klass not in {"", "type"}:
            continue
        src = dep.get("from") or ""
        if not src or src.casefold() in seen:
            continue
        seen.add(src.casefold())
        hit = by_fold.get(src.casefold())
        if hit:
            found.append(hit)
        else:
            found.append((src, None, None))
    return found


def _recreate_order(keys, by_fold, deps) -> list[str]:
    view_funcs = []
    procs = []
    for key in keys:
        hit = by_fold.get(key.casefold())
        obj = hit[1] if hit else None
        if obj is not None and (_is(obj, _VIEW_TYPES) or _is(obj, _FUNCTION_TYPES)):
            view_funcs.append(hit[0])
        else:
            procs.append(key)
    order, held = order_names(view_funcs, _module_edges(view_funcs, deps))
    return order + held + sorted(procs, key=str.casefold)


def _collect_fks(pairs):
    found = []
    for key, left, right in pairs:
        for side, obj in (("left", left), ("right", right)):
            if not obj:
                continue
            schema, table = _ident(key, obj)
            for fk in obj.get("foreign_keys") or []:
                found.append({
                    "side": side,
                    "schema": schema,
                    "table": table,
                    "name": fk.get("name") or "",
                    "columns": list(fk.get("columns") or []),
                    "referenced_schema": fk.get("referenced_schema") or "dbo",
                    "referenced_table": fk.get("referenced_table") or "",
                    "referenced_columns": list(fk.get("referenced_columns") or []),
                    "referenced_index": fk.get("referenced_index") or "",
                })
    return found


def _fk_targets(fk, index_name) -> bool:
    return _fold(fk.get("referenced_index")) == _fold(index_name) and bool(index_name)


def _fk_ident(fk) -> tuple:
    return (_fold(fk.get("schema")), _fold(fk.get("table")), _fold(fk.get("name")))


def _matching_fk(all_fks, fk):
    ident = _fk_ident(fk)
    for other in all_fks:
        if other["side"] == "left" and _fk_ident(other) == ident:
            return other
    return None


def _fk_create_sql(fk) -> str:
    cols = ", ".join(_br(col) for col in fk["columns"])
    refs = ", ".join(_br(col) for col in fk["referenced_columns"])
    return (
        f"ALTER TABLE {_br(fk['schema'])}.{_br(fk['table'])} ADD CONSTRAINT {_br(fk['name'])} "
        f"FOREIGN KEY ({cols}) REFERENCES {_br(fk['referenced_schema'])}.{_br(fk['referenced_table'])} "
        f"({refs})"
    )


def _index_map(obj) -> dict:
    found = {}
    if not obj:
        return found
    for idx in obj.get("indexes") or []:
        found[_fold(idx.get("name"))] = idx
    return found


def _index_create_sql(schema, table, idx) -> str:
    columns = list(idx.get("columns") or [])
    clustered = _clustered(idx)
    if idx.get("is_primary_key"):
        return render_add_primary_key(schema, table, idx.get("name") or "", columns, clustered)
    if idx.get("is_unique_constraint"):
        kind = "CLUSTERED" if clustered else "NONCLUSTERED"
        cols = ", ".join(_br(col) for col in columns)
        return (
            f"ALTER TABLE {_br(schema)}.{_br(table)} ADD CONSTRAINT {_br(idx.get('name') or '')} "
            f"UNIQUE {kind} ({cols})"
        )
    return _plain_index_sql(schema, table, idx)


def _plain_index_sql(schema, table, idx) -> str:
    kind = "CLUSTERED" if _clustered(idx) else "NONCLUSTERED"
    unique = "UNIQUE " if idx.get("is_unique") else ""
    descending = {_fold(col) for col in (idx.get("descending") or [])}
    parts = []
    for col in idx.get("columns") or []:
        piece = _br(col)
        if _fold(col) in descending:
            piece += " DESC"
        parts.append(piece)
    sql = (
        f"CREATE {unique}{kind} INDEX {_br(idx.get('name') or '')} "
        f"ON {_br(schema)}.{_br(table)} ({', '.join(parts)})"
    )
    included = idx.get("included") or []
    if included:
        sql += " INCLUDE (" + ", ".join(_br(col) for col in included) + ")"
    if idx.get("filter"):
        sql += f" WHERE {idx['filter']}"
    return sql


def _index_drop_sql(schema, table, idx) -> str:
    if idx.get("is_primary_key") or idx.get("is_unique_constraint"):
        return f"ALTER TABLE {_br(schema)}.{_br(table)} DROP CONSTRAINT {_br(idx.get('name') or '')}"
    return f"DROP INDEX {_br(idx.get('name') or '')} ON {_br(schema)}.{_br(table)}"


def _index_columns_exist(table_key, idx, present_cols, is_new_table) -> bool:
    if is_new_table:
        return True
    have = present_cols.get(table_key.casefold())
    if have is None:
        return True
    needed = list(idx.get("columns") or []) + list(idx.get("included") or [])
    return all(_fold(col) in have for col in needed)


def _clustered(idx) -> bool:
    if "clustered" in idx:
        return bool(idx.get("clustered"))
    return str(idx.get("type_desc") or "").upper().startswith("CLUSTERED")


def _schemas_for(pairs, emitted_folds, view_indexes) -> list[str]:
    seen = set()
    schemas = []

    def note(schema):
        if not schema or schema.casefold() == "dbo" or schema.casefold() in seen:
            return
        seen.add(schema.casefold())
        schemas.append(schema)

    for key, left, _right in pairs:
        if key.casefold() not in emitted_folds or left is None:
            continue
        note(_ident(key, left)[0])
    for batches in view_indexes.values():
        if batches:
            pass
    return schemas


def _note_schema_object(notes, schema):
    notes.append(schema)


def _excluded_names(pairs, rules) -> list[str]:
    found = []
    seen = set()
    for key, left, right in pairs:
        for obj, label in ((left, key), (right, key)):
            if not obj or not (_is(obj, _PROCEDURE_TYPES) or _is(obj, _FUNCTION_TYPES)):
                continue
            bare = obj.get("name") or label
            if not (_name_excluded(bare, rules) or _name_excluded(label, rules)):
                continue
            if bare.casefold() in seen:
                continue
            seen.add(bare.casefold())
            found.append(bare)
    return found


def _pair_objects(left_objects, right_objects):
    right_by = {_fold(key): value for key, value in right_objects.items()}
    pairs = []
    seen = set()
    for key, obj in left_objects.items():
        seen.add(_fold(key))
        pairs.append((key, obj, right_by.get(_fold(key))))
    only_right = [(key, obj) for key, obj in right_objects.items() if _fold(key) not in seen]
    return pairs, only_right


def _emit_module(definition: str, settings: dict | None) -> str:
    """Keep the batch when client scoping does not apply, then CREATE OR ALTER."""
    text = definition or ""
    try:
        from . import trimmer
    except ImportError:
        import trimmer
    trimmed = trimmer.trim_procedure(text, None)
    if trimmed.get("ok") and trimmed.get("trimmed_sql"):
        text = trimmed["trimmed_sql"]
    try:
        from .scriptgen import _as_create_or_alter
    except ImportError:
        from scriptgen import _as_create_or_alter
    return _as_create_or_alter(text, settings)


def _create_table_sql(schema, table, columns, key_folds=None) -> str:
    body = ",\n".join(
        "    " + _column_ddl(col, table, key_folds) for col in columns
    )
    return (
        f"IF OBJECT_ID(N'{_br(schema)}.{_br(table)}', N'U') IS NULL\n"
        f"CREATE TABLE {_br(schema)}.{_br(table)} (\n{body}\n)"
    )


def _add_column_sql(schema, table, col, key: bool = False) -> str:
    rendered = _type_text(col)
    expr = _default_expr(col)
    nullability = _nullability_sql(col, key)
    extra = ""
    if expr:
        extra = f" CONSTRAINT {_br('DF_' + table + '_' + col['name'])} DEFAULT {expr}"
    return (
        f"ALTER TABLE {_br(schema)}.{_br(table)} ADD {_br(col['name'])} "
        f"{rendered} {nullability}{extra}"
    )


def _column_ddl(col, table, key_folds=None) -> str:
    if col.get("computed"):
        expr = str(col["computed"]).strip()
        if not expr.startswith("("):
            expr = f"({expr})"
        return f"{_br(col['name'])} AS {expr}"
    rendered = _type_text(col)
    identity = ""
    if col.get("identity"):
        seed = _num(col["identity"].get("seed", 1))
        increment = _num(col["identity"].get("increment", 1))
        identity = f" IDENTITY({seed},{increment})"
    nullability = _nullability_sql(col, _column_in_key(col, key_folds))
    extra = ""
    expr = _default_expr(col)
    if expr:
        extra = f" CONSTRAINT {_br('DF_' + table + '_' + col['name'])} DEFAULT {expr}"
    return f"{_br(col['name'])} {rendered}{identity} {nullability}{extra}"


def _column_signature(col):
    identity = col.get("identity") or None
    if identity:
        identity_t = (_num(identity.get("seed", 1)), _num(identity.get("increment", 1)))
    else:
        identity_t = None
    return (_type_text(col), _nullable(col), identity_t, col.get("computed"), _default_expr(col))


def _manual(appendix, database, name, reason) -> None:
    safe = reason.replace("'", "''")
    label = name.replace("'", "''")
    appendix.append({
        "database": database,
        "name": name,
        "reason": reason,
        "sql": f"-- {name}: {reason}\nPRINT '{label}: {safe}';\nGO\n",
    })


def _batch(statement: str) -> str:
    text = statement.strip()
    if not text.endswith(";"):
        text += ";"
    return text + "\nGO\n"


def _settings(obj):
    if not obj:
        return None
    if "ansi_nulls" not in obj and "quoted_identifier" not in obj:
        return None
    return {
        "ansi_nulls": bool(obj.get("ansi_nulls")),
        "quoted_identifier": bool(obj.get("quoted_identifier")),
    }


def _text(obj):
    if not obj:
        return None
    value = obj.get("definition")
    if value is None:
        return None
    return value.replace("\r\n", "\n").replace("\r", "\n").strip()


def _schema_bound(obj) -> bool:
    return bool(obj and obj.get("schema_bound"))


def _name_excluded(name, rules) -> bool:
    try:
        from .proc_filter import procedure_excluded
    except ImportError:
        from proc_filter import procedure_excluded
    return procedure_excluded(name, rules)


def _type_text(col) -> str:
    try:
        from .inspect_objects import _rendered_type_ext
    except ImportError:
        from inspect_objects import _rendered_type_ext
    return _rendered_type_ext(
        col.get("type") or col.get("data_type"),
        col.get("max_length"),
        col.get("precision"),
        col.get("scale"),
    )


def _nullable(col) -> bool:
    if "nullable" in col:
        return bool(col["nullable"])
    if "nullability" in col:
        return bool(col["nullability"])
    if "is_nullable" in col:
        return bool(col["is_nullable"])
    return True


def _nullability_sql(col, key: bool) -> str:
    """Key columns are NOT NULL. SQL Server rejects a primary key on NULL."""
    if key or not _nullable(col):
        return "NOT NULL"
    return "NULL"


def _key_column_folds(obj) -> set[str]:
    folds = set()
    for idx in (obj or {}).get("indexes") or []:
        if not (idx.get("is_primary_key") or idx.get("is_unique_constraint")):
            continue
        for column in idx.get("columns") or []:
            folds.add(_fold(column))
    return folds


def _column_in_key(col, key_folds) -> bool:
    if _key_ordinal(col) is not None:
        return True
    return _fold(col.get("name")) in (key_folds or set())


def _warn_nullable_key(warnings, schema, owner, col) -> None:
    if not _nullable(col):
        return
    warnings.append(
        f"key column {_br(schema)}.{_br(owner)}.{_br(col.get('name') or '')} "
        "is nullable in the catalog; declared NOT NULL"
    )


def _key_ordinal(col):
    if "key_ordinal" not in col or col.get("key_ordinal") is None:
        return None
    try:
        number = int(col["key_ordinal"])
    except (TypeError, ValueError):
        return None
    if number <= 0:
        return None
    return number


def _default_expr(col):
    value = col.get("default")
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _num(value):
    if isinstance(value, bool):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return value


def _is(obj, kinds) -> bool:
    if not obj:
        return False
    return _fold(obj.get("type")) in kinds


def _is_module(obj) -> bool:
    return _is(obj, _PROCEDURE_TYPES | _FUNCTION_TYPES | _VIEW_TYPES | _TRIGGER_TYPES)


def _drop_word(obj) -> str:
    if _is(obj, _VIEW_TYPES):
        return "VIEW"
    if _is(obj, _FUNCTION_TYPES):
        return "FUNCTION"
    if _is(obj, _TRIGGER_TYPES):
        return "TRIGGER"
    return "PROCEDURE"


def _ident(key, obj):
    schema = (obj or {}).get("schema")
    name = (obj or {}).get("name")
    if schema and name:
        return schema, name
    if key and "." in key:
        schema, name = key.split(".", 1)
        return schema, name
    return "dbo", key or ""


def _qual(obj, key) -> str:
    schema, name = _ident(key, obj)
    return f"{_br(schema)}.{_br(name)}"


def _br(name) -> str:
    return "[" + str(name).replace("]", "]]") + "]"


def _fold(value) -> str:
    return str(value or "").casefold()


def _cursor(conn):
    try:
        return conn.cursor(as_dict=True)
    except TypeError:
        return conn.cursor()


def _fetch(cur, sql):
    cur.execute(sql)
    return list(cur.fetchall() or [])


def _cell(row, key):
    if not isinstance(row, dict):
        return None
    if key in row:
        return row[key]
    for have, value in row.items():
        if str(have).casefold() == key.casefold():
            return value
    return None


def _bit(value) -> bool:
    return bool(value) if value is not None else False


def _objects_from_capture(modules, columns, table_types, indexes, checks, sequences, scalar_types, foreign_keys):
    objects = {}
    for row in modules:
        schema = _cell(row, "schema_name") or "dbo"
        name = _cell(row, "object_name")
        if not name:
            continue
        code = str(_cell(row, "object_type") or "").strip()
        definition = _cell(row, "definition")
        obj = {
            "schema": schema,
            "name": name,
            "type": _MODULE_CODE.get(code, code),
            "definition": definition,
            "schema_bound": _bit(_cell(row, "schema_bound")),
            "ansi_nulls": _bit(_cell(row, "ansi_nulls")),
            "quoted_identifier": _bit(_cell(row, "quoted_identifier")),
        }
        if definition is None:
            obj["encrypted"] = True
        objects[f"{schema}.{name}"] = obj
    _capture_columns(objects, columns)
    _capture_table_types(objects, table_types)
    _capture_indexes(objects, indexes)
    _capture_checks(objects, checks)
    _capture_sequences(objects, sequences)
    _capture_scalar_types(objects, scalar_types)
    _capture_foreign_keys(objects, foreign_keys)
    return objects


def _capture_columns(objects, rows):
    grouped = {}
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        table = _cell(row, "table_name")
        if not table:
            continue
        key = f"{schema}.{table}"
        if key not in grouped:
            grouped[key] = []
            objects[key] = {
                "schema": schema,
                "name": table,
                "type": "SqlTable",
                "columns": grouped[key],
                "indexes": [],
                "foreign_keys": [],
                "checks": [],
            }
        seed = _cell(row, "identity_seed")
        identity = None
        if seed is not None:
            identity = {
                "seed": _num(seed),
                "increment": _num(_cell(row, "identity_increment") or 1),
            }
        grouped[key].append({
            "name": _cell(row, "column_name"),
            "type": _cell(row, "type_name"),
            "max_length": _cell(row, "max_length"),
            "precision": _cell(row, "precision"),
            "scale": _cell(row, "scale"),
            "nullable": _bit(_cell(row, "nullable")),
            "identity": identity,
            "computed": _cell(row, "computed_definition"),
            "default": _cell(row, "default_definition"),
        })


def _capture_table_types(objects, rows):
    grouped = {}
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        name = _cell(row, "type_name")
        if not name:
            continue
        key = f"{schema}.{name}"
        if key not in grouped:
            grouped[key] = []
            objects[key] = {
                "schema": schema,
                "name": name,
                "type": "SqlUserDefinedTableType",
                "memory_optimized": _bit(_cell(row, "memory_optimized")),
                "columns": grouped[key],
            }
        grouped[key].append({
            "name": _cell(row, "column_name"),
            "type": _cell(row, "data_type"),
            "max_length": _cell(row, "max_length"),
            "precision": _cell(row, "precision"),
            "scale": _cell(row, "scale"),
            "nullable": _bit(_cell(row, "nullable")),
            "key_ordinal": _cell(row, "key_ordinal"),
        })


def _capture_indexes(objects, rows):
    bucket = {}
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        table = _cell(row, "object_name")
        index_name = _cell(row, "index_name")
        if not table or not index_name:
            continue
        ident = (schema, table, index_name)
        entry = bucket.get(ident)
        if entry is None:
            entry = {
                "name": index_name,
                "is_primary_key": _bit(_cell(row, "is_primary_key")),
                "is_unique_constraint": _bit(_cell(row, "is_unique_constraint")),
                "is_unique": _bit(_cell(row, "is_unique")),
                "clustered": str(_cell(row, "type_desc") or "").upper().startswith("CLUSTERED"),
                "columns": [],
                "included": [],
                "descending": [],
                "filter": _cell(row, "filter_definition"),
            }
            bucket[ident] = entry
            key = f"{schema}.{table}"
            obj = objects.get(key)
            if obj is None:
                obj = {
                    "schema": schema,
                    "name": table,
                    "type": "SqlTable",
                    "columns": [],
                    "indexes": [],
                    "foreign_keys": [],
                }
                objects[key] = obj
            obj.setdefault("indexes", []).append(entry)
        column = _cell(row, "column_name")
        if _bit(_cell(row, "is_included_column")):
            entry["included"].append(column)
        else:
            entry["columns"].append(column)
            if _bit(_cell(row, "is_descending_key")):
                entry["descending"].append(column)


def _capture_checks(objects, rows):
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        table = _cell(row, "table_name")
        if not table:
            continue
        key = f"{schema}.{table}"
        obj = objects.get(key)
        if obj is None:
            continue
        obj.setdefault("checks", []).append({
            "name": _cell(row, "check_name"),
            "definition": _cell(row, "definition"),
        })


def _capture_sequences(objects, rows):
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        name = _cell(row, "sequence_name")
        if not name:
            continue
        cycling = _bit(_cell(row, "is_cycling"))
        cached = _bit(_cell(row, "is_cached"))
        cache_size = _cell(row, "cache_size")
        if cached and cache_size:
            cache = f"CACHE {_num(cache_size)}"
        elif cached:
            cache = "CACHE"
        else:
            cache = "NO CACHE"
        definition = (
            f"CREATE SEQUENCE {_br(schema)}.{_br(name)} AS {_cell(row, 'type_name')} "
            f"START WITH {_cell(row, 'start_value')} INCREMENT BY {_cell(row, 'increment')} "
            f"MINVALUE {_cell(row, 'minimum_value')} MAXVALUE {_cell(row, 'maximum_value')} "
            f"{'CYCLE' if cycling else 'NO CYCLE'} {cache}"
        )
        objects[f"{schema}.{name}"] = {
            "schema": schema,
            "name": name,
            "type": "Sequence",
            "definition": definition,
        }


def _capture_scalar_types(objects, rows):
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        name = _cell(row, "type_name")
        if not name:
            continue
        rendered = _type_text({
            "type": _cell(row, "base_type"),
            "max_length": _cell(row, "max_length"),
            "precision": _cell(row, "precision"),
            "scale": _cell(row, "scale"),
        })
        nullability = "NULL" if _bit(_cell(row, "nullable")) else "NOT NULL"
        objects[f"{schema}.{name}"] = {
            "schema": schema,
            "name": name,
            "type": "SqlUserDefinedType",
            "definition": f"CREATE TYPE {_br(schema)}.{_br(name)} FROM {rendered} {nullability}",
        }


def _capture_foreign_keys(objects, rows):
    bucket = {}
    for row in rows:
        schema = _cell(row, "schema_name") or "dbo"
        table = _cell(row, "table_name")
        fk_name = _cell(row, "fk_name")
        if not table or not fk_name:
            continue
        ident = (schema, table, fk_name)
        entry = bucket.get(ident)
        if entry is None:
            entry = {
                "name": fk_name,
                "columns": [],
                "referenced_schema": _cell(row, "referenced_schema") or "dbo",
                "referenced_table": _cell(row, "referenced_table"),
                "referenced_columns": [],
                "referenced_index": _cell(row, "referenced_index"),
            }
            bucket[ident] = entry
            obj = objects.get(f"{schema}.{table}")
            if obj is not None:
                obj.setdefault("foreign_keys", []).append(entry)
        entry["columns"].append(_cell(row, "parent_column"))
        entry["referenced_columns"].append(_cell(row, "referenced_column"))


def _dependencies_from_capture(rows) -> list[dict]:
    found = []
    for row in rows:
        from_name = _cell(row, "from_name")
        if not from_name:
            continue
        from_schema = _cell(row, "from_schema") or "dbo"
        to_name = _cell(row, "referenced_entity_name")
        to_schema = _cell(row, "referenced_schema_name") or "dbo"
        klass = _cell(row, "referenced_class_desc") or ""
        to_class = "TYPE" if str(klass).upper() == "TYPE" else klass
        found.append({
            "from": f"{from_schema}.{from_name}",
            "to": f"{to_schema}.{to_name}" if to_name else None,
            "to_class": to_class,
            "referenced_database_name": _cell(row, "referenced_database_name"),
        })
    return found
