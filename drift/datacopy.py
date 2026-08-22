"""PLAN-V5 Lane A (blueprint C2) -- config-table data copy: the old tool's
beloved Copy Data feature rebuilt WITHOUT its three unforgivable bugs.

What this module does: whitelist-driven sync of Olives' config tables
(menu / Programs / Messag(e) / Massag(e) / Page -- these ARE the deployment),
via row-hash diff so only changed rows move (the old tool copied EVERYTHING),
then either

  - emit_merge_script(): a portable .sql artifact in the old tool's
    idempotent style, done RIGHT (email-able, replayable customer-side with
    no tool installed -- the old artifact's best idea), or
  - apply_plan(): the same plan executed directly through a parameterized
    cursor (house security rule: values bind as %s scalars, NEVER
    interpolated into SQL text).

The three old bugs, and where each is buried here:
  1. `value.Replace("'","")` destroyed text ("Al'Malak" -> "AlMalak").
     Here single quotes are DOUBLED ('') in _lit() and NEVER stripped;
     the apostrophe property-test in test_datacopy.py keeps it that way.
  2. the composite-key WHERE builder overwrote accumulated predicates, so
     multi-column-key tables mass-updated on the LAST key column alone.
     _key_where() emits EVERY key predicate: WHERE ([K1] = v1) AND ([K2] = v2).
  3. identity seeds diverged (identity columns silently skipped, no repair).
     Identity columns are handled explicitly: pass identity_cols and any
     insert carrying one is wrapped in a SET IDENTITY_INSERT [T] ON/OFF
     pair; known identity columns never enter an UPDATE SET list (illegal
     in T-SQL). With identity_cols=None nothing is identified as identity,
     so nothing is wrapped or omitted -- inserts go out verbatim.

Conventions (matching inspect_objects/preflight): `cur` is a dict-row
cursor (conn.cursor(as_dict=True)). Table names reach SQL only through
_q()/_q_table() bracket-quoting with ']]' doubling -- T-SQL cannot bind an
identifier to %s, so bracket-quoting is the strongest available defense for
FROM/TABLE targets, identical reasoning to preflight's emitted DDL. VALUES
never touch SQL text in apply_plan: every one is a %s parameter.

Direction safety (risk register R10): this module copies src -> dst exactly
as handed to it. Profile pinning + direction banner + row-count preview are
the CALLER's entry tickets, non-negotiable per PLAN-V5.

Pure stdlib; importable both as package member (`from drift import
datacopy`) and standalone (`python3.13 test_datacopy.py`) -- it needs no
sibling imports, hence no try-relative/except-plain header (preflight.py
precedent).
"""
import hashlib
import re
from datetime import date, datetime, time as dtime, timezone
from decimal import Decimal

# The old tool's table whitelist, kept editable via the `whitelist` param of
# list_config_tables(). Case-insensitive substring match on sys.tables.name.
WHITELIST_RE = re.compile(r"menu|programs|messag|massag|page", re.IGNORECASE)


# --------------------------------------------------------------------------
# identifier quoting / literal rendering
# --------------------------------------------------------------------------

def _q(name) -> str:
    """Bracket-quote one identifier. Doubling an embedded ']' is SQL Server's
    documented escape -- same helper contract as preflight._q."""
    return "[" + str(name).replace("]", "]]") + "]"


def _q_table(name) -> str:
    """Quote a table reference. Already-bracketed names pass through untouched;
    dotted names are quoted per part ("dbo.SysMenu" -> "[dbo].[SysMenu]")."""
    s = str(name)
    if "[" in s:
        return s
    return ".".join(_q(part) for part in s.split("."))


def _esc(text) -> str:
    """Single-quote a string literal, DOUBLING embedded quotes. The doubling
    is the whole point of this module -- the old tool's .Replace("'","")
    destroyed data; stripping is forbidden here by construction."""
    return "'" + str(text).replace("'", "''") + "'"


def _lit(v) -> str:
    """Render one Python value as a T-SQL literal for the portable script.

    Matrix (ported from the old tool's correct §8.3 matrix, minus its fatal
    quote-stripping): NULL -> NULL; bit -> 1/0 (checked BEFORE int --
    bool IS an int subclass); numeric -> raw; datetime/date/time -> quoted
    ISO string; binary -> unquoted 0x hex; everything else -> quoted string
    with '' doubling."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float, Decimal)):
        return str(v)
    if isinstance(v, datetime):
        return _esc(v.isoformat(sep=" "))
    if isinstance(v, (date, dtime)):
        return _esc(v.isoformat())
    if isinstance(v, (bytes, bytearray)):
        return "0x" + bytes(v).hex()
    return _esc(v)


# --------------------------------------------------------------------------
# discovery: which tables, which keys
# --------------------------------------------------------------------------

def list_config_tables(cur, whitelist=WHITELIST_RE) -> list[str]:
    """User tables matching the whitelist regex, sorted.

    is_ms_shipped = 0 filters out system objects server-side; the regex does
    the config-table routing client-side so callers can pass their own
    (editable) pattern without touching this module."""
    cur.execute("SELECT name FROM sys.tables WHERE is_ms_shipped = 0 ORDER BY name")
    return sorted(r["name"] for r in cur.fetchall() if r["name"] and whitelist.search(r["name"]))


def get_key_columns(cur, table: str) -> list[str]:
    """Key columns for upsert targeting: the PRIMARY KEY index's key columns,
    falling back to the clustered index (index_id = 1, the indid=1 of old)
    when no PK exists. Ordered by key_ordinal; [] when the table has neither.

    The OR condition can match TWO indexes at once (a nonclustered PK plus a
    separate clustered index), so rows are grouped per index client-side and
    the PK group wins -- interleaving two indexes' ordinals would scramble
    column order. Table name binds as %s (house rule)."""
    cur.execute(
        "SELECT i.is_primary_key, i.index_id, c.name AS col_name, ic.key_ordinal "
        "FROM sys.indexes i "
        "JOIN sys.tables t ON t.object_id = i.object_id "
        "JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id "
        "JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id "
        "WHERE t.name = %s AND (i.is_primary_key = 1 OR i.index_id = 1) "
        "ORDER BY i.index_id, ic.key_ordinal",
        (table,),
    )
    pk_cols, clustered_cols = [], []
    for r in cur.fetchall():
        target = pk_cols if r["is_primary_key"] else clustered_cols
        target.append((r["key_ordinal"], r["col_name"]))
    chosen = pk_cols or clustered_cols
    return [name for _, name in sorted(chosen)]


# --------------------------------------------------------------------------
# capture + diff
# --------------------------------------------------------------------------

def fetch_rows_hashed(cur, table: str, key_cols: list[str]) -> dict[tuple, dict]:
    """SELECT * the whole table into {keytuple: {"cols": [...], "values": {...}}}.

    Column names are preserved from the dict-row cursor (SELECT * order);
    the key tuple follows key_cols order. A duplicate key means the WHERE-
    based UPDATE/DELETE would be ambiguous -- the exact mass-update hazard
    bug #2 enabled -- so it refuses loudly instead of guessing.
    """
    qt = _q_table(table)
    cur.execute(f"SELECT * FROM {qt}")
    rows: dict[tuple, dict] = {}
    for r in cur.fetchall():
        cols = list(r.keys())
        kt = tuple(r[k] for k in key_cols)
        if kt in rows:
            raise ValueError(
                f"duplicate key {kt!r} in {qt}: keys must be unique or the "
                f"key-targeted UPDATE/DELETE plan is ambiguous"
            )
        rows[kt] = {"cols": cols, "values": {c: r[c] for c in cols}}
    return rows


def row_hash(values: dict) -> str:
    """Stable content hash of one row's values, type-tagged so 1 != True != "1".

    This is what makes the diff minimal: only rows whose hash differs move
    (old tool shipped every row, every time)."""
    h = hashlib.sha256()
    for k in sorted(values):
        h.update(k.encode("utf-8"))
        h.update(b"\x00")
        v = values[k]
        h.update(f"{type(v).__module__}.{type(v).__qualname__}:{v!r}".encode("utf-8"))
        h.update(b"\x00")
    return h.hexdigest()


def diff_tables(src_rows: dict, dst_rows: dict) -> dict:
    """Classify src vs dst into {"insert", "update", "delete"}.

    insert : rowdicts present only in src   (dst lacks the key)
    update : rowdicts whose value hash differs on shared keys
    delete : dst-only KEYTUPLES (not rowdicts -- deletes carry keys only)

    Inputs are never mutated; result lists are freshly built in each map's
    insertion order (= server order from fetch_rows_hashed)."""
    src_keys = set(src_rows)
    dst_keys = set(dst_rows)
    inserts = [src_rows[k] for k in src_rows if k not in dst_keys]
    updates = [
        src_rows[k] for k in src_rows
        if k in dst_keys and row_hash(src_rows[k]["values"]) != row_hash(dst_rows[k]["values"])
    ]
    deletes = [k for k in dst_rows if k not in src_keys]
    return {"insert": inserts, "update": updates, "delete": deletes}


# --------------------------------------------------------------------------
# emission: portable .sql artifact
# --------------------------------------------------------------------------

def _key_where(key_cols, key_vals) -> str:
    """BUG #2's headstone: EVERY key predicate present, parenthesized,
    ANDed. zip() over the tuple so a short key tuple cannot silently drop
    trailing columns either."""
    return " AND ".join(
        f"({_q(k)} = {_lit(v)})" for k, v in zip(key_cols, key_vals)
    )


def _param_key_where(key_cols) -> str:
    """Same shape as _key_where but %s-bound, for apply_plan."""
    return " AND ".join(f"({_q(k)} = %s)" for k in key_cols)


def _insert_stmt(qt: str, rd: dict) -> str:
    cols = list(rd["cols"])
    collist = ", ".join(_q(c) for c in cols)
    vallist = ", ".join(_lit(rd["values"][c]) for c in cols)
    return f"INSERT INTO {qt} ({collist}) VALUES ({vallist});"


def _identity_wrapped(qt: str, stmt_lines: list[str], rd: dict, ident: set) -> list[str]:
    """BUG #3's fix, emission side: wrap the insert block in ONE balanced
    ON/OFF pair iff any known identity column rides in this row's columns."""
    if ident and any(c in ident for c in rd["cols"]):
        return [f"SET IDENTITY_INSERT {qt} ON;", *stmt_lines, f"SET IDENTITY_INSERT {qt} OFF;"]
    return stmt_lines


def emit_merge_script(table, cols, key_cols, plan, identity_cols=None) -> str:
    """Portable idempotent merge script for `plan` against destination `table`.

    Per CHANGED row (update): UPDATE ... WHERE <full composite key>, then
    IF @@ROWCOUNT = 0 BEGIN INSERT ... END -- the old tool's idempotent
    preamble style, corrected (bug #2: both key predicates survive).
    NEW rows (insert): INSERT-first variant, IDENTITY_INSERT-wrapped when a
    known identity column is present (bug #3).
    DELETEs come LAST (they are the dangerous tail; earlier failures must
    never be followed by deletions), each guarded by the FULL key.

    `cols` documents the table's column order for readers; row content is
    taken from the plan's own rowdicts. identity_cols=None means unknown ->
    nothing wrapped, nothing omitted. Header carries counts + table + UTC
    timestamp so a customer-side run is self-describing."""
    qt = _q_table(table)
    ident = set(identity_cols or [])
    key_set = set(key_cols)
    inserts = list(plan.get("insert", []))
    updates = list(plan.get("update", []))
    deletes = list(plan.get("delete", []))

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        f"-- drift.datacopy merge plan for {qt}: "
        f"{len(inserts)} ins / {len(updates)} upd / {len(deletes)} del "
        f"-- generated UTC {ts}",
        "-- idempotent style: update-then-insert-if-missing for changed rows,",
        "-- insert-first for new rows, guarded deletes last. Quotes doubled, never stripped.",
    ]

    if not (inserts or updates or deletes):
        lines.append("-- nothing to apply: source and destination already match.")
        return "\n".join(lines) + "\n"

    # --- inserts first (new rows), identity-wrapped where needed ------------
    for rd in inserts:
        lines.extend(_identity_wrapped(qt, [_insert_stmt(qt, rd)], rd, ident))

    # --- changed rows: UPDATE by full key, fall back to INSERT --------------
    for rd in updates:
        vals = rd["values"]
        where = _key_where(key_cols, tuple(vals[k] for k in key_cols))
        # identity columns can never sit in a SET list (T-SQL forbids it);
        # key columns belong in the WHERE, not the SET.
        set_cols = [c for c in rd["cols"] if c not in ident and c not in key_set]
        block = _identity_wrapped(qt, [_insert_stmt(qt, rd)], rd, ident)
        if set_cols:
            sets = ", ".join(f"{_q(c)} = {_lit(vals[c])}" for c in set_cols)
            lines.append(f"UPDATE {qt} SET {sets} WHERE {where};")
            lines.append("IF @@ROWCOUNT = 0 BEGIN")
            lines.extend(block)
            lines.append("END;")
        else:
            # every column is key/identity: nothing to SET -- keep the
            # idempotent guarantee with an existence-guarded insert instead.
            lines.append(f"IF NOT EXISTS (SELECT 1 FROM {qt} WHERE {where}) BEGIN")
            lines.extend(block)
            lines.append("END;")

    # --- deletes LAST, full-key guarded -------------------------------------
    for kt in deletes:
        lines.append(f"DELETE FROM {qt} WHERE {_key_where(key_cols, kt)};")

    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# execution: parameterized path
# --------------------------------------------------------------------------

def _exec_insert(cur_dst, qt: str, rd: dict, ident: set) -> None:
    """One INSERT with %s-bound values; ON/OFF pair stays balanced even when
    the insert fails (finally-clause OFF), so the session can't be left
    holding IDENTITY_INSERT open for the table."""
    cols = list(rd["cols"])
    sql = (
        f"INSERT INTO {qt} ({', '.join(_q(c) for c in cols)}) "
        f"VALUES ({', '.join(['%s'] * len(cols))})"
    )
    params = tuple(rd["values"][c] for c in cols)
    wrapped = bool(ident) and any(c in ident for c in cols)
    if wrapped:
        cur_dst.execute(f"SET IDENTITY_INSERT {qt} ON")
        try:
            cur_dst.execute(sql, params)
        finally:
            try:
                cur_dst.execute(f"SET IDENTITY_INSERT {qt} OFF")
            except Exception:  # noqa: BLE001 - the OFF must never mask the real error
                pass
    else:
        cur_dst.execute(sql, params)


def apply_plan(cur_dst, table, key_cols, plan, identity_cols=None) -> dict:
    """Execute `plan` against the destination through a PARAMETERIZED cursor
    (NOT the string-built artifact -- that is emit_merge_script's job).

    Semantics mirror the script exactly: update rows go out as UPDATE by
    full key, and when @@ROWCOUNT == 0 (row vanished between diff and
    apply) they fall back to INSERT -- same outcome as the artifact's
    IF @@ROWCOUNT = 0 BEGIN ... END block.

    Per-row failures are recorded in errors[] and execution CONTINUES --
    one bad row must not strand the rest of a config sync (each error is
    visible, never silent, mirroring executor.py's reporting posture).
    Returns {"inserted": n, "updated": n, "deleted": n, "errors": []}.
    """
    qt = _q_table(table)
    ident = set(identity_cols or [])
    key_set = set(key_cols)
    res = {"inserted": 0, "updated": 0, "deleted": 0, "errors": []}

    def record(op: str, key, exc: Exception) -> None:
        res["errors"].append({"op": op, "key": repr(key), "error": str(exc)})

    for rd in plan.get("insert", []):
        kt = tuple(rd["values"].get(k) for k in key_cols)
        try:
            _exec_insert(cur_dst, qt, rd, ident)
            res["inserted"] += 1
        except Exception as exc:  # noqa: BLE001 - continuation IS the feature
            record("insert", kt, exc)

    for rd in plan.get("update", []):
        vals = rd["values"]
        kt = tuple(vals.get(k) for k in key_cols)
        try:
            set_cols = [c for c in rd["cols"] if c not in ident and c not in key_set]
            key_params = tuple(vals[k] for k in key_cols)
            if not set_cols:
                # every column is key/identity: nothing to SET -- insert instead
                _exec_insert(cur_dst, qt, rd, ident)
                res["inserted"] += 1
                continue
            sql = (
                f"UPDATE {qt} SET "
                f"{', '.join(f'{_q(c)} = %s' for c in set_cols)} "
                f"WHERE {_param_key_where(key_cols)}"
            )
            params = tuple(vals[c] for c in set_cols) + key_params
            cur_dst.execute(sql, params)
            if getattr(cur_dst, "rowcount", 1) == 0:
                _exec_insert(cur_dst, qt, rd, ident)  # @@ROWCOUNT = 0 fallback
                res["inserted"] += 1
            else:
                res["updated"] += 1
        except Exception as exc:  # noqa: BLE001 - continuation IS the feature
            record("update", kt, exc)

    for kt in plan.get("delete", []):
        try:
            sql = f"DELETE FROM {qt} WHERE {_param_key_where(key_cols)}"
            cur_dst.execute(sql, tuple(kt))
            res["deleted"] += 1
        except Exception as exc:  # noqa: BLE001 - continuation IS the feature
            record("delete", kt, exc)

    return res
