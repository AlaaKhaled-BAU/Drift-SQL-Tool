"""Compare two .dacpac schemas via sqlpackage (parsed object model, not text
diff) and classify results along two independent axes:

  role     -- direction-relative: added (in source, not target) / modified
              (in both, differs) / only_on_other (in target, not source).
              Direction-agnostic by design: the caller picks which side is
              source vs target for whichever workspace this is (Client->105
              or 105->Client), and the same Create/Alter/Drop -> role mapping
              applies both ways. See PLAN.md §1/§3.

  category -- what kind of difference: structural (real) / documentation
              (MS_Description comments) / cascading (SqlPackage's own cached-
              metadata-refresh side effect) / formatting_only (raw text
              differs but normalized text doesn't -- these never appear in
              the DeployReport at all, since the ignore-options already treat
              them as "same"; found separately via find_formatting_only()).

See PLAN-03 §5-§6 for why DeployReport (not DriftReport) and why each
ignore-option is pinned explicitly rather than left at its default.
"""
import fnmatch
import re
import subprocess
import xml.etree.ElementTree as ET

from . import config

# sqlpackage's own error text when an encrypted object blocks report
# generation, e.g. "The element [dbo].[X] cannot be deployed as the script
# body is encrypted." -- observed live (SQL74502), see run_deploy_report().
_ENCRYPTED_BLOCK_RE = re.compile(
    r"element \[([^\]]+)\]\.\[([^\]]+)\] cannot be deployed as the script body is encrypted"
)

# Only Create/Drop mean "exists on one side only" -- everything else (Alter,
# TableRebuild, and whatever future action SqlPackage ever emits) means the
# object exists on both sides and something changed, i.e. "modified". Default
# to counting as modified rather than requiring an exhaustive whitelist: an
# unlisted action silently dropping real drift is worse than an unlisted
# action being (correctly, as it happens) bucketed as "modified" by default.
# Found by comparing against v1's run on the same real data: v1's more
# permissive default-catch-all counted "TableRebuild" (9 items on the real
# backup test/ pair) as structural; this file's first version had an explicit
# {Create,Alter,Drop} whitelist that silently dropped those 9 entirely.
_ROLE_BY_ACTION = {"Create": "added", "Drop": "only_on_other"}
_DEFAULT_ROLE = "modified"

PROGRAMMABLE_TYPES = {
    "SqlProcedure", "SqlView", "SqlScalarFunction",
    "SqlInlineTableValuedFunction", "SqlMultiStatementTableValuedFunction",
    "SqlDmlTrigger", "SqlDatabaseDdlTrigger",
}

# D5a: the human-facing categories the "only compare procedures" pre-run
# filter offers. "Other" is deliberately open-ended (sequences, synonyms,
# table types, UDTs, roles, and anything SqlPackage names that isn't in one
# of the other 7 buckets) -- an unrecognized type must fall into a visible
# bucket the user can still select, never silently vanish from every
# possible filter selection.
TYPE_CATEGORIES = ["Procedures", "Views", "Functions", "Triggers", "Tables", "Indexes", "Constraints", "Other"]

_CATEGORY_BY_TYPE = {
    "SqlProcedure": "Procedures",
    "SqlView": "Views",
    "SqlScalarFunction": "Functions", "SqlInlineTableValuedFunction": "Functions",
    "SqlMultiStatementTableValuedFunction": "Functions",
    "SqlDmlTrigger": "Triggers", "SqlDatabaseDdlTrigger": "Triggers",
    "SqlTable": "Tables",
    "SqlIndex": "Indexes",
    "SqlForeignKeyConstraint": "Constraints", "SqlCheckConstraint": "Constraints", "SqlDefaultConstraint": "Constraints",
}


def type_category(obj_type: str) -> str:
    return _CATEGORY_BY_TYPE.get(obj_type, "Other")


def passes_type_filter(obj_type: str, type_filter: set | None) -> bool:
    """type_filter is a set of TYPE_CATEGORIES names to KEEP, or None/empty
    to mean "no filter, keep everything" -- an empty set is never sent by
    the UI (at least one category is always checked) but treating it the
    same as None here means a caller can't accidentally filter out
    EVERYTHING by passing one instead of the other."""
    return not type_filter or type_category(obj_type) in type_filter


def _localname(tag: str) -> str:
    return tag.split("}", 1)[-1] if "}" in tag else tag


def load_exclusions() -> list[str]:
    if not config.EXCLUDE_FILE.exists():
        return []
    patterns = []
    for line in config.EXCLUDE_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            patterns.append(line)
    return patterns


def is_excluded(object_name: str, patterns: list[str]) -> bool:
    bare = object_name.strip("[]").split("].[")[-1]
    return any(fnmatch.fnmatch(bare, p) for p in patterns)


def bare_name(object_name: str) -> str:
    return object_name.strip("[]").split("].[")[-1]


def qualified_name(object_name: str, obj_type: str) -> str:
    """Like bare_name(), except a SqlIndex keeps its owning table:
    "[dbo].[Table].[IndexName]" -> "Table.IndexName" instead of just
    "IndexName". Index names are unique only WITHIN a table in SQL Server,
    unlike every other type here (procs/views/FKs/etc all occupy one
    schema-wide namespace) -- two different tables can legally reuse the
    same index name, and bare_name() alone would collapse them into one
    lookup key (D3 Change B; collision count measured in VALIDATION.md)."""
    parts = object_name.strip("[]").split("].[")
    if obj_type == "SqlIndex" and len(parts) >= 3:
        return f"{parts[-2]}.{parts[-1]}"
    return parts[-1]


def run_deploy_report(source_dacpac, target_dacpac, out_path, log) -> str:
    cmd = [
        config.SQLPACKAGE_BIN, "/Action:DeployReport",
        f"/SourceFile:{source_dacpac}", f"/TargetFile:{target_dacpac}",
        "/TargetDatabaseName:target_db",  # required label even in file-vs-file mode; no live connection made
        f"/OutputPath:{out_path}",
    ] + config.COMPARE_PROFILE
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=config.sqlpackage_env())
    if r.returncode != 0:
        combined = r.stdout + "\n" + r.stderr
        if "SQL74502" in combined:
            enc = _ENCRYPTED_BLOCK_RE.findall(combined)
            if enc:
                names = ", ".join(f"[{s}].[{n}]" for s, n in enc)
                raise RuntimeError(
                    f"sqlpackage refuses to generate ANY comparison report while {len(enc)} encrypted "
                    f"(WITH ENCRYPTION) object(s) are in scope: {names}. This is a SqlPackage/DacFx "
                    f"limitation (SQL74502) -- it can't plan a deployment for an object it can't read, "
                    f"even just to compare, and blocks the WHOLE report, not only that object. The run "
                    f"cannot proceed with these objects present. Options: add them to "
                    f"exclude-from-drift.txt (skips ALL drift detection for them -- a change to their "
                    f"encrypted body will never be flagged, use with caution), or decrypt/redeploy them "
                    f"without WITH ENCRYPTION before comparing."
                )
        raise RuntimeError(f"sqlpackage DeployReport failed:\n{r.stdout[-1500:]}\n{r.stderr[-1500:]}")
    return str(out_path)


def parse_deploy_report(xml_path: str, exclusions: list[str], log, type_filter: set | None = None) -> dict:
    """Direction-agnostic parse. Caller supplies which (source, target) this
    XML came from; role labels come out relative to that, via _ROLE_BY_ACTION.

    D5a: type_filter (a set of TYPE_CATEGORIES names, or None for no filter)
    is applied here -- a non-selected type is counted into filtered_out
    (distinct from excluded_count, which is the client-name exclusion list)
    rather than silently dropped, so the UI can show a real "N object(s)
    not examined because of your type filter" count."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    items = []
    excluded_count = 0
    filtered_out_count = 0
    seen_actions = set()

    for operation in root.iter():
        if _localname(operation.tag) != "Operation":
            continue
        action = operation.get("Name", "Unknown")
        seen_actions.add(action)
        role = _ROLE_BY_ACTION.get(action, _DEFAULT_ROLE)
        for item in operation:
            if _localname(item.tag) != "Item":
                continue
            obj_type = item.get("Type", "?")
            obj_name = item.get("Value", "?")
            if is_excluded(obj_name, exclusions):
                excluded_count += 1
                continue
            if not passes_type_filter(obj_type, type_filter):
                filtered_out_count += 1
                continue
            # Cascading refreshes are a side effect of some other change, not
            # independently meaningful drift -- their own category, not a role.
            if action == "Refresh":
                category = "cascading"
            elif obj_type == "SqlExtendedProperty":
                category = "documentation"
            else:
                category = "structural"
            items.append({
                "action": action, "type": obj_type, "name": obj_name,
                "role": role, "category": category,
            })

    unknown_actions = seen_actions - set(_ROLE_BY_ACTION) - {"Refresh"}
    if unknown_actions:
        log(f"  note: unrecognized SqlPackage action(s) {sorted(unknown_actions)} -- "
            f"counted as structural/modified by default, not dropped")

    items, collapsed = _collapse_drop_create_pairs(items)
    if collapsed:
        log(f"  collapsed {collapsed} Drop+Create pair(s) into single 'modified' findings "
            f"(SqlPackage represents some incompatible in-place changes -- e.g. removing an "
            f"OUTPUT parameter -- as drop-then-recreate rather than Alter; same object, not "
            f"an add and a removal)")

    return {"items": items, "excluded_count": excluded_count, "filtered_out_count": filtered_out_count}


def _collapse_drop_create_pairs(items: list) -> tuple:
    """Found on real data: SqlPackage sometimes emits the SAME object name under
    both a Drop operation and a Create operation in one DeployReport, when a
    change is incompatible with in-place ALTER (e.g. OSFA_SP_Api_Jawad losing an
    OUTPUT parameter -- verified by reading both captured definitions directly).
    Left alone, that reads as two contradictory findings: 'client added this'
    AND 'master has this, client doesn't'. It's one object, genuinely modified;
    collapse to a single 'modified' finding so it doesn't fight itself in the
    added/only_on_other buckets."""
    by_name = {}
    for it in items:
        by_name.setdefault(it["name"], []).append(it)

    out = []
    collapsed = 0
    for name, group in by_name.items():
        has_create = any(g["action"] == "Create" for g in group)
        has_drop = any(g["action"] == "Drop" for g in group)
        if has_create and has_drop and len(group) == 2:
            template = group[0]
            out.append({
                "action": "DropCreate", "type": template["type"], "name": name,
                "role": "modified", "category": template["category"],
            })
            collapsed += 1
        else:
            out.extend(group)
    return out, collapsed


def find_formatting_only(source_hashes: dict, target_hashes: dict, already_flagged_bare_names: set,
                          exclusions: list, type_filter: set | None = None) -> tuple:
    """Objects present on both sides where the raw definition differs but
    sqlpackage's ignore-aware compare already called them equal -- so they
    never appear in the DeployReport at all. Only a raw hash compare finds
    these. Skips anything already flagged structural/documentation/cascading
    (that's real drift, already accounted for) and anything excluded.

    source_hashes/target_hashes: bare name -> (sqlpackage_type, hash), from
    inspect_objects.get_definition_hashes() -- a FULL sweep, not scoped to
    any type filter, so D5a's filter is applied here instead (leak check:
    without this, a "procedures only" run would still emit formatting_only
    findings for views/functions/triggers, visibly contradicting its own
    label). Returns (findings, filtered_out_count)."""
    out = []
    filtered_out = 0
    common = set(source_hashes) & set(target_hashes)
    for name in sorted(common):
        if name in already_flagged_bare_names or is_excluded(name, exclusions):
            continue
        obj_type, source_hash = source_hashes[name]
        _, target_hash = target_hashes[name]
        if source_hash == target_hash:
            continue
        if not passes_type_filter(obj_type, type_filter):
            filtered_out += 1
            continue
        out.append({
            "action": "Alter", "type": obj_type, "name": f"[dbo].[{name}]",
            "role": "modified", "category": "formatting_only",
        })
    return out, filtered_out


def find_settings_only(source_settings: dict, target_settings: dict, already_flagged_bare_names: set,
                        exclusions: list, type_filter: set | None = None) -> tuple:
    """Objects present on both sides with byte-identical OBJECT_DEFINITION
    (so neither the DeployReport nor the raw-hash sweep flagged them) but
    different ANSI_NULLS/QUOTED_IDENTIFIER -- invisible to any text-based
    check but a real behavior difference (qwen-review L-11). Emitted as
    category=structural from the start, never formatting_only: settings
    drift changes runtime semantics, it is not cosmetic.

    source_settings/target_settings: bare name -> (sqlpackage_type,
    {"ansi_nulls", "quoted_identifier"}), from
    inspect_objects.get_all_module_settings() -- same full-sweep/leak-check
    reasoning as find_formatting_only above. Returns (findings, filtered_out_count)."""
    out = []
    filtered_out = 0
    common = set(source_settings) & set(target_settings)
    for name in sorted(common):
        if name in already_flagged_bare_names or is_excluded(name, exclusions):
            continue
        obj_type, s = source_settings[name]
        _, t = target_settings[name]
        if s["ansi_nulls"] == t["ansi_nulls"] and s["quoted_identifier"] == t["quoted_identifier"]:
            continue
        if not passes_type_filter(obj_type, type_filter):
            filtered_out += 1
            continue
        out.append({
            "action": "Alter", "type": obj_type, "name": f"[dbo].[{name}]",
            "role": "modified", "category": "structural",
        })
    return out, filtered_out
