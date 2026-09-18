"""Assemble a safe, additive apply script from APPROVED findings only.

The data-loss guard (PLAN.md §6/§8, and the bug this whole module exists to
avoid -- v1's exact-copy reconcile script would have dropped 105's newer
objects):
  - only_on_other items are NEVER included, ever -- including them would mean
    generating a DROP on the target.
  - column drops/retypes are NEVER auto-included -- listed as manual_review
    with the exact DDL shown, never silently applied.
  - added tables are auto-CREATEd only when a complete inspect table_bundle
    (create_sql + extras) was captured on the finding; otherwise manual_review.
  - deletions are opt-in and off by default; this function has no path that
    emits DROP unless include_deletions=True is passed explicitly.

D2 (2026-07-26): `direction` is now REQUIRED, not inferred from
`target_label`. The prior version always pulled `client_def` -- correct
only for client_to_105. In 105_to_client the target IS the client, so the
wanted version is master_def; the old code produced a no-op script for
`modified` findings (writing the client's own existing definition back onto
itself) and pushed every `added` (105-has-it, client-missing-it -- the
entire point of that workspace) into manual_review with "definition not
captured", because client_def is None there by construction.
"""
import re

try:
    from . import diffing
    from .compare import PROGRAMMABLE_TYPES
except ImportError:  # allows `python3.13 test_scriptgen.py` to run standalone --
    import diffing   # compare.py isn't imported here, its own `from . import config`
    PROGRAMMABLE_TYPES = {  # would hit this same relative-import problem one level deeper.
        "SqlProcedure", "SqlView", "SqlScalarFunction",
        "SqlInlineTableValuedFunction", "SqlMultiStatementTableValuedFunction",
        "SqlDmlTrigger", "SqlDatabaseDdlTrigger",
    }

_DEF_KEY = {"client_to_105": "client_def", "105_to_client": "master_def"}
_COLUMNS_KEY = {"client_to_105": "client_columns", "105_to_client": "master_columns"}
_SETTINGS_KEY = {"client_to_105": "client_settings", "105_to_client": "master_settings"}


def assemble(findings: list, target_label: str, direction: str, include_deletions: bool = False,
             include_irrelevant: bool = False) -> dict:
    """findings: APPROVED items from one workspace's index.json (each must
    still carry its captured definition/columns -- pass the enriched pipeline
    findings, not just the index.json summary rows).
    target_label: human label for the header comment (e.g. "105" or "client").
    direction: "client_to_105" or "105_to_client" -- selects which captured
    side is the wanted version (D2). Required, never inferred from
    target_label: a caller that gets this wrong silently generates a no-op
    or an empty script, which is worse than refusing to guess.
    Returns {"script": str, "manifest": dict}."""
    if direction not in _DEF_KEY:
        raise ValueError(f"direction must be 'client_to_105' or '105_to_client', got {direction!r}")
    def_key = _DEF_KEY[direction]
    columns_key = _COLUMNS_KEY[direction]
    settings_key = _SETTINGS_KEY[direction]

    statements = []
    manual_review = []
    included_names = []
    skipped_deletions = []

    skipped_irrelevant = []
    backfill_warnings = []
    for f in findings:
        if f["role"] == "only_on_other":
            skipped_deletions.append(f["name"])
            continue

        # PLAN-V4 B.2a: a finding whose scoped fingerprints match on both
        # sides differs ONLY inside blocks this client never executes --
        # excluded from the script by default (visible in the manifest),
        # includable via include_irrelevant=True for a mirror-style sync.
        if not include_irrelevant and (f.get("scope") or {}).get("irrelevant_to_client"):
            skipped_irrelevant.append(f["name"])
            continue

        if f["type"] in PROGRAMMABLE_TYPES:
            # AI-merge feature (2026-07-29): an accepted merge proposal takes
            # priority over the raw def_key side for client_to_105 -- it's
            # client_def's content ALREADY merged into 105's current body,
            # not a blind overwrite that could drop other clients' branches
            # 105 gained since this client's image was taken (see PLAN
            # Context). Falls back to today's def_key behavior when no merge
            # was ever proposed/accepted for this finding, so every other
            # finding is byte-identical to before this change.
            definition = f.get("merged_def") if direction == "client_to_105" else None
            if not definition:
                definition = f.get(def_key)  # the side that has the wanted version, per direction
            if not definition:
                manual_review.append({"name": f["name"], "reason": "definition not captured"})
                continue
            statements.append(_as_create_or_alter(definition, f.get(settings_key)))
            included_names.append(f["name"])

        elif f["type"] == "SqlTable":
            if f["role"] == "added":
                bundle = f.get("table_bundle") or {}
                create_sql = bundle.get("create_sql") if isinstance(bundle, dict) else None
                if create_sql:
                    statements.append(create_sql.rstrip().rstrip(";") + ";")
                    for extra in bundle.get("extras") or []:
                        statements.append(extra.rstrip().rstrip(";") + ";")
                    included_names.append(f["name"])
                else:
                    manual_review.append({
                        "name": f["name"],
                        "reason": "new table -- no complete table_bundle (CREATE + extras) captured",
                    })
            elif f["role"] == "modified" and f.get("columns"):
                cols = f["columns"]
                if cols.get("removed") or cols.get("retyped"):
                    manual_review.append({
                        "name": f["name"],
                        "reason": f"column removal/retype needs manual review: "
                                  f"removed={cols.get('removed')}, retyped={[r['name'] for r in cols.get('retyped', [])]}",
                    })
                if cols.get("added"):
                    by_name = {c["name"]: c for c in f.get(columns_key, [])}
                    backfill = f.get("backfill") or {}
                    for col_name in cols["added"]:
                        col = by_name.get(col_name)
                        if col:
                            statements.append(
                                f"ALTER TABLE [dbo].[{f['bare_name']}] ADD {diffing.column_ddl(col)};"
                            )
                            included_names.append(f"{f['name']}.[{col_name}] (added column)")
                            # PLAN-V5 Lane C (C3): optional per-column backfill
                            # value -> typed UPDATE after the ADD. Only for
                            # columns whose captured metadata exists on the
                            # wanted side; quoting decided by the CAPTURED type
                            # via quote_backfill_literal, never guessed.
                            bf = backfill.get(col_name) if backfill else None
                            if col_name in backfill:
                                if not isinstance(bf, str):
                                    backfill_warnings.append({
                                        "column": f"{f['bare_name']}.{col_name}",
                                        "reason": f"backfill value must be a string, got {type(bf).__name__}",
                                    })
                                else:
                                    literal = quote_backfill_literal(bf, col.get("type", ""))
                                    if literal is None:
                                        backfill_warnings.append({
                                            "column": f"{f['bare_name']}.{col_name}",
                                            "reason": f"cannot quote value {bf!r} as {col['type']!r} "
                                                      f"-- skipped rather than guessed",
                                        })
                                    else:
                                        statements.append(
                                            f"UPDATE [dbo].[{f['bare_name']}] SET [{col_name}] = {literal} "
                                            f"WHERE [{col_name}] IS NULL;"
                                        )
                        elif col_name in (f.get("backfill") or {}):
                            backfill_warnings.append({
                                "column": f"{f['bare_name']}.{col_name}",
                                "reason": "column metadata not captured on wanted side -- backfill skipped",
                            })
        elif f["type"] == "SqlUserDefinedTableType":
            # PLAN-V5 Lane C (C8): table types have no ALTER -- a "modified"
            # type means drop-and-recreate against every dependent proc, which
            # stays manual. An ADDED type is safe to create guarded: if it
            # already exists on the target we do nothing rather than fail.
            if f["role"] == "modified":
                manual_review.append({
                    "name": f["name"],
                    "reason": "type modification requires dropping dependents first",
                })
            else:
                definition = f.get(def_key)
                if not definition:
                    manual_review.append({"name": f["name"], "reason": "definition not captured"})
                else:
                    inner = definition.replace("'", "''")
                    statements.append(
                        f"IF TYPE_ID(N'[dbo].[{f['bare_name']}]') IS NULL EXEC(N'{inner}');"
                    )
                    included_names.append(f"{f['name']} (added table type)")
        else:
            manual_review.append({"name": f["name"], "type": f["type"], "reason": "object type not auto-applied in Phase 1"})

    if include_deletions:
        for f in findings:
            if f["role"] == "only_on_other" and f["type"] in PROGRAMMABLE_TYPES:
                statements.append(f"DROP {_drop_kind(f['type'])} {f['name']};")
                included_names.append(f"{f['name']} (DELETE)")

    # D2b: no transaction/error handling previously existed at all -- a
    # failure partway through left the target (often 105, the master image
    # every client is re-imaged from) half-applied with no record of where
    # it stopped. GO batches can't share one enclosing transaction, so this
    # can't be atomic end-to-end; XACT_ABORT + numbered PRINT progress lines
    # make a partial run loud and diagnosable instead of silent.
    header = [
        f"-- Apply script for {target_label}, generated by drift-tool.",
        f"-- Direction: {direction}.",
        f"-- {'ADDITIVE + DELETIONS (explicitly enabled)' if include_deletions else 'ADDITIVE ONLY -- no deletions'}.",
        f"-- {len(included_names)} statement(s) from approved findings. "
        f"{len(manual_review)} item(s) need manual review (see manifest.json).",
        "-- NOT ATOMIC: GO batches cannot share one transaction. XACT_ABORT aborts the CURRENT",
        "-- batch loudly on error and the PRINT lines below show exactly how far it got --",
        "-- but earlier batches in this script are NOT rolled back. Back up the target first.",
        "SET XACT_ABORT ON;",
        "SET NOCOUNT ON;",
        "",
    ]
    body = []
    total = len(statements)
    for i, stmt in enumerate(statements, 1):
        body.append(f"PRINT N'applying {i}/{total}';")
        body.append(stmt)
    script = "\n".join(header) + "\n".join(body) + ("\n" if body else "")

    manifest = {
        "target": target_label,
        "direction": direction,
        "included": included_names,
        "manual_review": manual_review,
        "deletions_enabled": include_deletions,
        "skipped_as_only_on_other": len(skipped_deletions) if not include_deletions else 0,
        "skipped_irrelevant_to_client": skipped_irrelevant,
        "backfill_warnings": backfill_warnings,
    }
    return {"script": script, "manifest": manifest}


# D2a: sys.sql_modules.definition preserves the EXACT original batch text,
# including anything before the CREATE keyword. Measured against the real
# dump: 107/1629 (~7%) definitions begin with a comment before CREATE
# (e.g. "--DROP FUNCTION [dbo].[GetAnswerDesc]\nCREATE FUNCTION ...");
# `if lower.startswith("create ")` silently no-ops on all of them, so the
# script emitted a bare CREATE that fails with "there is already an object
# named ..." against a target that already has it. Also missed 126
# definitions with CREATE followed by more than one space/tab
# ("CREATE  function [dbo].[Fun_GetCustTaxType]") -- those happened to
# survive the old single-space slice by accident, not by design.
#
# Fixed by reusing diffing.code_spans/mask_comments -- the exact literal-
# and comment-aware scanner already built (and unit-tested) for finding the
# real AS split point in split_param_body. Same class of problem: don't
# mistake a keyword inside a string literal, bracketed identifier, or
# comment for the real one.
_CREATE_RE = re.compile(r"(?i)\bcreate\b")


def _find_create_keyword(definition: str):
    """(start, end) offsets of the real CREATE keyword, or None if not
    found -- searches only outside string literals/bracketed identifiers,
    with comments masked out, so a leading comment or a literal containing
    the word CREATE can't be mistaken for it."""
    for start, end in diffing.code_spans(definition):
        masked = diffing.mask_comments(definition[start:end])
        m = _CREATE_RE.search(masked)
        if m:
            return start + m.start(), start + m.end()
    return None


def _as_create_or_alter(definition: str, settings: dict | None = None) -> str:
    """CREATE OR ALTER is idempotent (works whether or not the target already
    has the object) and needs SQL Server 2016 SP1+ -- scratch is 2022,
    observed clients are v15/2019, floor holds.

    Follow-up (2026-07-26): `settings` ({"ansi_nulls": bool,
    "quoted_identifier": bool}, from the WANTED side, i.e. the side whose
    definition this is -- see scriptgen.assemble's settings_key) is baked
    into a module at CREATE time and never changes for the life of the
    object regardless of a later caller's own session settings -- so
    there's nothing to "restore" afterward; each object being applied
    already states its own required values up front, unconditionally
    correct regardless of whatever ran before it in this script. Without
    this, a detected ANSI_NULLS/QUOTED_IDENTIFIER difference (compare.py's
    find_settings_only, change_kind="settings") gets silently lost the
    moment the fix is actually applied -- the new object would pick up
    whichever setting the operator running this script happens to have,
    defeating the exact drift this tool just finished detecting.
    settings=None (not captured -- shouldn't happen for a real module,
    get_all_module_settings sweeps all of them) skips the SET wrapper
    rather than guessing a default."""
    loc = _find_create_keyword(definition)
    if loc is None:
        # No CREATE keyword found at all -- shouldn't happen for a real
        # captured sys.sql_modules definition. Return unchanged rather than
        # guessing; flagged loudly instead of silently fabricating a
        # rewrite that might be wrong.
        rewritten = f"-- WARNING: could not locate CREATE keyword to rewrite as CREATE OR ALTER; applying as-is\n" \
                    f"{definition.rstrip()}"
    else:
        start, end = loc
        rewritten = (definition[:start] + "CREATE OR ALTER" + definition[end:]).rstrip()

    if settings:
        ansi = "ON" if settings.get("ansi_nulls") else "OFF"
        quoted = "ON" if settings.get("quoted_identifier") else "OFF"
        return f"SET ANSI_NULLS {ansi};\nSET QUOTED_IDENTIFIER {quoted};\nGO\n{rewritten}\nGO\n"
    return rewritten + "\nGO\n"


def quote_backfill_literal(value: str, sql_type_name: str) -> str | None:
    """Port of the legacy tool's §8.3 type/quoting matrix (SQL_Compare report),
    with its two known flaws fixed: quote-stripping replaced by '' doubling,
    and unvalidated numeric interpolation replaced by a strict numeric check.

    int/bigint/smallint/tinyint/decimal/numeric/money/float/real -> raw
    (validated numeric, else None); bit -> 1/0 from truthy strings;
    date/time/datetime/smalldatetime/datetime2 -> N'...' quoted;
    char/nchar/varchar/nvarchar/text/ntext/uniqueidentifier -> N'...' with
    single quotes DOUBLED (''), never stripped; unknown type -> None
    (caller skips backfill, adds manifest warning -- never guesses)."""
    t = (sql_type_name or "").strip().lower()
    if t in _QUOTED_TYPES or t in _DATETIME_TYPES:
        return "N'" + str(value).replace("'", "''") + "'"
    if t == "bit":
        s = str(value).strip().lower()
        if s in _BIT_TRUE:
            return "1"
        if s in _BIT_FALSE:
            return "0"
        return None
    if t in _RAW_NUMERIC_TYPES:
        s = str(value).strip()
        return s if _BACKFILL_NUMERIC_RE.match(s) else None
    return None


_RAW_NUMERIC_TYPES = {"int", "bigint", "smallint", "tinyint",
                      "decimal", "numeric", "money", "float", "real"}
_DATETIME_TYPES = {"date", "time", "datetime", "smalldatetime", "datetime2"}
_QUOTED_TYPES = {"char", "nchar", "varchar", "nvarchar", "text", "ntext",
                 "uniqueidentifier"}
_BIT_TRUE = {"1", "true", "t", "yes", "y"}
_BIT_FALSE = {"0", "false", "f", "no", "n"}
# Strict numeric form for raw interpolation into SET x = <value>: optional
# sign, digits with optional fraction (or bare fraction). No exponent, no
# currency symbols -- anything outside this is refused (None), because a
# raw-interpolated value IS injection surface if we guess loosely.
_BACKFILL_NUMERIC_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$")


def _drop_kind(sqlpackage_type: str) -> str:
    return {
        "SqlProcedure": "PROCEDURE", "SqlView": "VIEW",
        "SqlScalarFunction": "FUNCTION", "SqlInlineTableValuedFunction": "FUNCTION",
        "SqlMultiStatementTableValuedFunction": "FUNCTION",
        "SqlDmlTrigger": "TRIGGER", "SqlDatabaseDdlTrigger": "TRIGGER",
    }.get(sqlpackage_type, "OBJECT")
