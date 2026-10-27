"""Order Full Update objects. No capture, no script files.

T4 calls the functions below. Views and functions share one ``order_names``
graph. ``held_back`` is the manual appendix: cycles, and every name that
depends on a cycle. This module does not emit statements that remove objects.

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
