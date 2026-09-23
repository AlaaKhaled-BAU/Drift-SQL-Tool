"""Orchestrates one Master(105)-vs-Client drift check end to end, across
whichever direction(s) were requested:

  .bak -> RESTORE (once per side) -> script to .sql + extract to .dacpac (once per side)
       -> per requested direction: sqlpackage DeployReport -> categorize -> formatting-only
          hash sweep -> (shared, once) capture definitions/columns/callers for the union of
          changed objects across all requested directions -> per-direction enrich + diff
          -> write workspace folder + index.json
       -> ProcedureChangeLog attribution + lost-fix (once per side, shared across directions)
       -> teardown

Every step reports through `log(str)` so the GUI can stream it live. Wall-clock
per phase is recorded into `meta["timings"]` -- feeds metrics.py's runtime report.
"""
import json
import time
import uuid
from pathlib import Path

from . import (blocks, changelog, compare, config, convert, dependencies, diffing,
               docker_mgmt, extract, inspect_objects, report_writer, restore, statements)

DIRECTIONS = ("client_to_105", "105_to_client")
_UNSET = object()  # recompare()'s "caller didn't pass type_filter at all" marker -- None is meaningful (no filter)


def _side_kind(side: dict) -> str:
    return side.get("kind", "bak")


def _side_for_meta(side: dict) -> dict:
    return {k: v for k, v in side.items() if k != "password"}


def _assert_source_cache_fresh(side: str, recorded: dict) -> None:
    """Bak sides must still match size/mtime; live sides trust the cached dacpacs."""
    if not recorded:
        raise RuntimeError(f"{side} cache key missing -- run a full compare instead")
    if "live" in recorded:
        return
    p = Path(recorded["path"])
    if not p.is_file():
        raise FileNotFoundError(f"{side} backup no longer exists at {p} -- cannot re-compare")
    st = p.stat()
    if st.st_size != recorded["size"] or st.st_mtime != recorded["mtime"]:
        raise RuntimeError(
            f"{side} backup at {p} has changed (size/mtime differs from this run's "
            f"capture) -- it may have been re-exported since; run a full compare "
            f"instead of trusting a stale cache"
        )


def run_compare(master_path: str, client_path: str, directions: list, log, type_filter: set | None = None,
                client_active_id=None) -> dict:
    return run_compare_sides(
        {"kind": "bak", "path": str(master_path)},
        {"kind": "bak", "path": str(client_path)},
        directions,
        log,
        type_filter=type_filter,
        client_active_id=client_active_id,
    )


def run_compare_sides(master_side: dict, client_side: dict, directions: list, log,
                      type_filter: set | None = None, client_active_id=None) -> dict:
    directions = [d for d in directions if d in DIRECTIONS] or ["client_to_105"]

    run_id = f"{int(time.time())}_{uuid.uuid4().hex[:6]}"
    run_dir = config.OUTPUT_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    timings = {}
    t_run_start = time.time()

    def phase(name):
        return _Phase(name, timings)

    master_bak = _side_kind(master_side) == "bak"
    client_bak = _side_kind(client_side) == "bak"
    master_path = Path(master_side["path"]).resolve() if master_bak else None
    client_path = Path(client_side["path"]).resolve() if client_bak else None
    db_master, db_client = f"drift_master_{run_id}", f"drift_client_{run_id}"
    # D5d: recompare()'s cache key -- a source .bak changing (re-exported,
    # replaced) after this run must never silently serve a stale re-compare.
    # Stat'd up front, once; the file is only ever read (restore), never
    # written, for the rest of this run.
    def _bak_cache_entry(p: Path) -> dict:
        return {"path": str(p), "size": p.stat().st_size, "mtime": p.stat().st_mtime}

    bak_cache_key = {
        "master": _bak_cache_entry(master_path) if master_bak else {"live": master_side.get("database", "")},
        "client": _bak_cache_entry(client_path) if client_bak else {"live": client_side.get("database", "")},
    }

    master_label = master_path.name if master_bak else master_side.get("database", "live")
    client_label = client_path.name if client_bak else client_side.get("database", "live")
    log(f"=== run {run_id}: Master(105)={master_label}  Client={client_label}  "
        f"directions={directions} ===")
    if master_bak or client_bak:
        with phase("docker_start"):
            docker_mgmt.ensure_running(log)

    with phase("restore"):
        header_master = (
            restore.restore_backup(master_path, db_master, log) if master_bak else {}
        )
        header_client = (
            restore.restore_backup(client_path, db_client, log) if client_bak else {}
        )

    with phase("script_to_sql"):
        master_sql_name = f"master__{_safe(master_path) if master_bak else _safe(Path(master_label))}.sql"
        client_sql_name = f"client__{_safe(client_path) if client_bak else _safe(Path(client_label))}.sql"
        sql_master = convert.script_to_sql(
            db_master, run_dir / master_sql_name, log, side=master_side if not master_bak else None,
        )
        sql_client = convert.script_to_sql(
            db_client, run_dir / client_sql_name, log, side=client_side if not client_bak else None,
        )

    with phase("extract_dacpac"):
        if master_bak:
            dacpac_master = extract.extract_dacpac(db_master, run_dir / "master.dacpac", log)
        else:
            dacpac_master = extract.extract_dacpac_source(master_side, run_dir / "master.dacpac", log)
        if client_bak:
            dacpac_client = extract.extract_dacpac(db_client, run_dir / "client.dacpac", log)
        else:
            dacpac_client = extract.extract_dacpac_source(client_side, run_dir / "client.dacpac", log)

    exclusions = compare.load_exclusions()

    with phase("hash_sweep"):
        log("hashing all programmable objects on both sides (for formatting-only detection)...")
        master_hashes = inspect_objects.get_definition_hashes(
            db_master, side=master_side if not master_bak else None,
        )
        client_hashes = inspect_objects.get_definition_hashes(
            db_client, side=client_side if not client_bak else None,
        )
        master_encrypted = inspect_objects.get_encrypted_names(
            db_master, side=master_side if not master_bak else None,
        )
        client_encrypted = inspect_objects.get_encrypted_names(
            db_client, side=client_side if not client_bak else None,
        )
        if master_encrypted or client_encrypted:
            log(f"  WARNING: {len(master_encrypted)} encrypted object(s) on master, "
                f"{len(client_encrypted)} on client -- these cannot be compared, flagged not skipped")

        # Full settings sweep (qwen-review L-11): a pure ANSI_NULLS/
        # QUOTED_IDENTIFIER-only difference has byte-identical OBJECT_DEFINITION
        # on both sides, so it produces NO signal from the DeployReport or the
        # hash sweep above -- it would never enter the changed-object set
        # otherwise. Confirmed live: without this, a settings-only flip on an
        # unchanged real procedure produced zero findings in either direction.
        master_all_settings = inspect_objects.get_all_module_settings(
            db_master, side=master_side if not master_bak else None,
        )
        client_all_settings = inspect_objects.get_all_module_settings(
            db_client, side=client_side if not client_bak else None,
        )

    if type_filter:
        log(f"  ⚠ TYPE FILTER ACTIVE: only {sorted(type_filter)} -- this run is PARTIAL, "
            f"not a clean full comparison (D5a)")

    raw_by_direction = {}
    detail_names = set()  # union across directions: objects needing a captured definition/columns

    with phase("compare"):
        for direction in directions:
            source_dacpac, target_dacpac = (
                (dacpac_client, dacpac_master) if direction == "client_to_105" else (dacpac_master, dacpac_client)
            )
            source_hashes, target_hashes = (
                (client_hashes, master_hashes) if direction == "client_to_105" else (master_hashes, client_hashes)
            )
            source_settings, target_settings = (
                (client_all_settings, master_all_settings) if direction == "client_to_105"
                else (master_all_settings, client_all_settings)
            )
            diff_xml = compare.run_deploy_report(Path(source_dacpac), Path(target_dacpac),
                                                  run_dir / f"diff_{direction}.xml", log)
            parsed = compare.parse_deploy_report(diff_xml, exclusions, log, type_filter=type_filter)
            items = parsed["items"]
            filtered_out = parsed["filtered_out_count"]
            already_seen = {compare.bare_name(i["name"]) for i in items}
            fmt_items, fmt_filtered = compare.find_formatting_only(
                source_hashes, target_hashes, already_seen, exclusions, type_filter=type_filter)
            items = items + fmt_items
            filtered_out += fmt_filtered
            already_seen = {compare.bare_name(i["name"]) for i in items}
            settings_items, settings_filtered = compare.find_settings_only(
                source_settings, target_settings, already_seen, exclusions, type_filter=type_filter)
            items = items + settings_items
            filtered_out += settings_filtered

            structural_count = sum(1 for i in items if i["category"] == "structural")
            fmt_count = sum(1 for i in items if i["category"] == "formatting_only")
            doc_count = sum(1 for i in items if i["category"] == "documentation")
            casc_count = sum(1 for i in items if i["category"] == "cascading")
            log(f"  [{direction}] {structural_count} structural, {fmt_count} formatting-only, "
                f"{doc_count} documentation, {casc_count} cascading -- {parsed['excluded_count']} excluded"
                + (f", {filtered_out} filtered out by type filter" if type_filter else ""))

            raw_by_direction[direction] = {
                "items": items, "excluded_count": parsed["excluded_count"], "filtered_out_count": filtered_out,
            }
            detail_names |= {
                compare.bare_name(i["name"]) for i in items
                if i["category"] in ("structural", "formatting_only")
            }

    with phase("capture_definitions"):
        log(f"capturing definitions for {len(detail_names)} changed object(s) before teardown...")
        m_side = master_side if not master_bak else None
        c_side = client_side if not client_bak else None
        master_defs = inspect_objects.get_definitions(db_master, detail_names, side=m_side)
        client_defs = inspect_objects.get_definitions(db_client, detail_names, side=c_side)
        master_cols = inspect_objects.get_columns(db_master, detail_names, side=m_side)
        client_cols = inspect_objects.get_columns(db_client, detail_names, side=c_side)
        master_table_names = inspect_objects.get_all_table_names(db_master, side=m_side)
        client_table_names = inspect_objects.get_all_table_names(db_client, side=c_side)

        # Extended object types (qwen-review L-3): not sys.sql_modules objects,
        # so OBJECT_DEFINITION can't see them -- each getter reconstructs a
        # canonical, diffable text form from catalog views instead. Merged
        # straight into master_defs/client_defs: diffing.py doesn't care
        # whether text came from real SQL Server source or a reconstruction,
        # only that both sides used the identical reconstruction, so a real
        # difference still produces a real diff. This is what gives indexes/
        # FKs/constraints/sequences/synonyms/table-types/UDTs actual
        # has_definition=True body-level detail instead of name-only.
        extended_getters = (
            inspect_objects.get_index_definitions, inspect_objects.get_fk_definitions,
            inspect_objects.get_check_constraint_definitions, inspect_objects.get_default_constraint_definitions,
            inspect_objects.get_sequence_definitions, inspect_objects.get_synonym_definitions,
            inspect_objects.get_table_type_definitions, inspect_objects.get_udt_definitions,
        )
        for getter in extended_getters:
            master_defs.update(getter(db_master, detail_names, side=m_side))
            client_defs.update(getter(db_client, detail_names, side=c_side))
        log(f"  extended-type capture: {len(master_defs)} master / {len(client_defs)} client definition(s) total "
            f"(programmable + index/FK/constraint/sequence/synonym/table-type/UDT)")

        # Settings view scoped to the changed set, for _enrich()'s per-finding
        # note-attachment (a body change AND a settings change on the same
        # object) -- derived from the full sweep already fetched in
        # hash_sweep, not re-queried. Drops the (type, settings) tuple down
        # to just settings, matching what _enrich()/diffing.settings_diff()
        # expect.
        master_settings = {n: v[1] for n, v in master_all_settings.items() if n in detail_names}
        client_settings = {n: v[1] for n, v in client_all_settings.items() if n in detail_names}
        master_db_options = inspect_objects.get_database_options(db_master, side=m_side)
        client_db_options = inspect_objects.get_database_options(db_client, side=c_side)
        db_options_match = master_db_options == client_db_options
        if not db_options_match:
            log(f"  WARNING: database options differ -- master={master_db_options} client={client_db_options} "
                f"(collation/compatibility-level drift changes semantics even when object text matches)")

    with phase("blast_radius"):
        log(f"resolving callers for {len(detail_names)} changed object(s) "
            f"(sys.sql_expression_dependencies -- exact, not the regex-derived vault graph)...")
        master_callers = dependencies.get_callers(db_master, detail_names, side=m_side)
        client_callers = dependencies.get_callers(db_client, detail_names, side=c_side)
        dynamic_sql_count = len(
            dependencies.get_dynamic_sql_users(db_master, side=m_side)
            | dependencies.get_dynamic_sql_users(db_client, side=c_side)
        )
        resolved = sum(1 for n in detail_names if n in master_callers or n in client_callers)
        log(f"  callers resolved for {resolved}/{len(detail_names)} changed object(s)")
        if dynamic_sql_count:
            log(f"  caveat: {dynamic_sql_count} proc(s) build SQL dynamically (sp_executesql/EXEC(@sql)) -- "
                f"a caller reaching an object ONLY through one of these is invisible to this catalog, "
                f"so caller counts are a floor, not a proven ceiling")

    with phase("attribution"):
        log("cross-referencing ProcedureChangeLog for attribution + lost-fix check...")
        cl_master = changelog.inspect(db_master, "master", detail_names, log, side=m_side)
        cl_client = changelog.inspect(db_client, "client", detail_names, log, side=c_side)
        attribution_by_name = {}
        for row in cl_master["attribution"] + cl_client["attribution"]:
            attribution_by_name.setdefault(row["object"], []).append(row)

    with phase("write_reports"):
        workspaces = {}
        for direction in directions:
            items = raw_by_direction[direction]["items"]
            excluded_count = raw_by_direction[direction]["excluded_count"]
            added_tables = {
                compare.bare_name(i["name"]) for i in items
                if i["type"] == "SqlTable" and i["role"] == "added"
            }
            if direction == "client_to_105":
                existing_tables = master_table_names | added_tables
            else:
                existing_tables = client_table_names | added_tables
            enriched = [
                _enrich(it, direction, master_defs, client_defs, master_cols, client_cols, attribution_by_name,
                        master_callers, client_callers, master_settings, client_settings,
                        client_active_id=client_active_id, existing_tables=existing_tables)
                for it in items
            ]

            # D1: no_difference is a demotion FROM structural (see _enrich), never
            # a dropped bucket -- it must stay in detail_findings alongside
            # structural/formatting_only or it would silently vanish from
            # index.json and the UI entirely, which is worse than being
            # mislabeled. report_writer.py gives it its own 05_no_difference/
            # folder and counts bucket, same treatment as formatting_only.
            detail_findings = [f for f in enriched if f["category"] in ("structural", "formatting_only", "no_difference")]
            documentation_list = [{"name": f["name"], "type": f["type"]} for f in enriched if f["category"] == "documentation"]
            cascading_list = [{"name": f["name"], "type": f["type"]} for f in enriched if f["category"] == "cascading"]

            workspace_dir = run_dir / direction
            index = report_writer.write_workspace(
                workspace_dir, direction, detail_findings, documentation_list, cascading_list,
                cl_master["attribution"] + cl_client["attribution"],
                cl_master["lost_fixes"] + cl_client["lost_fixes"],
                excluded_count, log,
                filtered_out_count=raw_by_direction[direction]["filtered_out_count"], type_filter=type_filter,
            )
            workspaces[direction] = {"index": index, "findings": detail_findings}

    with phase("persist_capture"):
        # D5d: everything a re-compare (recompare(), below) needs that would
        # otherwise require the live DB -- written once, here, while it's
        # still in memory and before teardown drops both databases. This is
        # what makes "reuse the persisted .dacpac files" actually work: the
        # .dacpac alone only gets you a structural DeployReport; formatting-
        # only/settings-only/blast-radius/attribution all need one of these.
        _write_capture(run_dir, master_defs, client_defs, master_cols, client_cols,
                        master_hashes, client_hashes, master_all_settings, client_all_settings,
                        master_callers, client_callers,
                        cl_master["attribution"] + cl_client["attribution"],
                        cl_master["lost_fixes"] + cl_client["lost_fixes"])

    with phase("teardown"):
        if master_bak:
            restore.drop_database(db_master, log)
        if client_bak:
            restore.drop_database(db_client, log)

    timings["total"] = round(time.time() - t_run_start, 1)

    meta = {
        "run_id": run_id,
        "master_path": str(master_path) if master_bak else "",
        "client_path": str(client_path) if client_bak else "",
        "master_side": _side_for_meta(master_side),
        "client_side": _side_for_meta(client_side),
        "header_master": header_master, "header_client": header_client,
        "directions": directions,
        "trigger_present": {"master": cl_master["trigger_present"], "client": cl_client["trigger_present"]},
        "encrypted_objects": {"master": sorted(master_encrypted), "client": sorted(client_encrypted)},
        "db_options": {"master": master_db_options, "client": client_db_options, "match": db_options_match},
        "dependency_coverage": {
            "changed_objects": len(detail_names), "callers_resolved_for": resolved,
            "dynamic_sql_procs": dynamic_sql_count,
        },
        "timings": timings,
        "artifacts": {
            "sql_master": sql_master, "sql_client": sql_client,
            "dacpac_master": dacpac_master, "dacpac_client": dacpac_client,
        },
        "bak_cache_key": bak_cache_key,  # D5d: recompare()'s staleness guard
        # D5a: critical honesty requirement -- a type-filtered run must be
        # visibly, permanently distinguishable from a clean full run, not
        # just reflected in the log. None means no filter (a full run).
        "type_filter": sorted(type_filter) if type_filter else None,
        # PLAN-V4 B.2a: optional ClientActive scoping of programmable diffs.
        # Absent -> detection/enrichment byte-identical to pre-scope behavior.
        "client_active_id": str(client_active_id) if client_active_id is not None else None,
    }
    report_writer.write_meta(run_dir, meta)

    log(f"=== done in {timings['total']}s: run {run_id} -- " +
        ", ".join(f"{d}: {workspaces[d]['index']['counts']['modified']} modified / "
                   f"{workspaces[d]['index']['counts']['added']} added / "
                   f"{workspaces[d]['index']['counts']['only_on_other']} only-on-other"
                   for d in directions) + " ===")

    return {
        "run_id": run_id, "run_dir": str(run_dir), "meta": meta,
        "workspaces": {d: workspaces[d]["index"] for d in directions},
        # full enriched findings (with master_def/client_def/columns), keyed by direction --
        # index.json intentionally omits these to stay lean; app.py caches this in memory
        # for the apply-script step so it never needs to re-parse from disk.
        "_findings": {d: workspaces[d]["findings"] for d in directions},
    }


class _Phase:
    """Tiny context manager: with phase('x'): ... records timings['x'] in seconds."""
    def __init__(self, name, timings):
        self.name, self.timings = name, timings

    def __enter__(self):
        self.t0 = time.time()
        return self

    def __exit__(self, *exc):
        self.timings[self.name] = round(time.time() - self.t0, 1)
        return False


def _side_summary(direction: str, role: str, type_label: str) -> str:
    """Phrasing for a single-sided finding ('added'/'only_on_other'), correct
    for EITHER direction. 'added' means the object exists in this run's
    source and not its target; 'only_on_other' means the reverse -- and
    source/target swap which physical side (master/client) they are when
    direction flips (see run_compare's source_dacpac/target_dacpac
    selection). A direction-blind hardcoded string here was a real bug: it
    read correctly for client_to_105 but came out backwards for
    105_to_client -- e.g. an object that exists ONLY on the client showed as
    "Master (105) has this...; client does not" in the 105_to_client
    workspace, exactly inverted. Caught live via the qwen-review follow-up
    surgical battery (a client-only default constraint), not by inspection."""
    source_is_client = direction == "client_to_105"
    has_source = role == "added"
    client_has_it = has_source == source_is_client
    return (f"Client has this {type_label}; master (105) does not." if client_has_it
            else f"Master (105) has this {type_label}; client does not.")


def _enrich(item: dict, direction: str, master_defs: dict, client_defs: dict, master_cols: dict, client_cols: dict,
            attribution_by_name: dict, master_callers: dict, client_callers: dict,
            master_settings: dict | None = None, client_settings: dict | None = None,
            client_active_id=None, existing_tables: set[str] | None = None) -> dict:
    # D3 Change B: qualified_name() only diverges from bare_name() for
    # SqlIndex (returns "table.index" instead of just "index") -- every
    # other type's attribution/caller/settings lookups below never had
    # index entries anyway, so this is a no-op for them and the fix for
    # get_index_definitions()'s now-qualified dict keys (inspect_objects.py).
    bare = compare.qualified_name(item["name"], item["type"])
    f = dict(item)
    f["bare_name"] = bare
    f["attribution"] = attribution_by_name.get(bare, [])
    f["callers"] = _blast_radius(bare, master_callers, client_callers)
    master_settings = master_settings or {}
    client_settings = client_settings or {}
    # Follow-up (2026-07-26): scriptgen.py needs the WANTED side's own
    # ANSI_NULLS/QUOTED_IDENTIFIER at apply time, not just the diff note --
    # otherwise a detected settings difference (or even a body change on an
    # object with non-default settings) gets silently lost the moment the
    # fix is actually applied, defeating the L-11 sweep this note comes
    # from. None when not a module (e.g. tables never have these).
    f["master_settings"] = master_settings.get(bare)
    f["client_settings"] = client_settings.get(bare)

    if item["type"] == "SqlTable":
        f["master_columns"] = master_cols.get(bare, [])
        f["client_columns"] = client_cols.get(bare, [])
        if item["role"] == "modified":
            cdiff = diffing.diff_columns(f["master_columns"], f["client_columns"])
            f["columns"] = cdiff
            f["change_kind"] = cdiff["change_kind"]
            f["summary"] = cdiff["summary"]
        elif item["role"] in ("added", "only_on_other"):
            f["summary"] = _side_summary(direction, item["role"], "table")
            if item["role"] == "added" and existing_tables is not None:
                source_is_client = direction == "client_to_105"
                cols = client_cols.get(bare, []) if source_is_client else master_cols.get(bare, [])
                if cols:
                    schema = inspect_objects.schema_from_qualified_name(item["name"])
                    src_defs = client_defs if source_is_client else master_defs
                    extras = inspect_objects.collect_extras_for_table(src_defs, bare)
                    bundle = inspect_objects.build_table_bundle(
                        bare, schema, cols, extras, existing_tables)
                    if bundle:
                        f["table_bundle"] = bundle
    elif bare in master_defs or bare in client_defs:
        # Any type text was actually captured for -- real sys.sql_modules
        # source for programmable objects (compare.PROGRAMMABLE_TYPES), or a
        # catalog-reconstructed canonical form for indexes/FKs/constraints/
        # sequences/synonyms/table-types/UDTs (qwen-review L-3). Gated on
        # "did we capture text", not on a hardcoded type allowlist, so this
        # stays correct even for a sqlpackage type-name string never observed
        # before -- a real text difference is a real text difference either way.
        f["master_def"] = master_defs.get(bare)
        f["client_def"] = client_defs.get(bare)
        if item["category"] in ("structural", "formatting_only") and f["master_def"] and f["client_def"]:
            d = diffing.diff_programmable(f["master_def"], f["client_def"],
                                           split_params=item["type"] in compare.PROGRAMMABLE_TYPES)
            f["change_kind"], f["diff"], f["summary"] = d["change_kind"], d["diff"], d["summary"]
            note = diffing.settings_diff(master_settings.get(bare), client_settings.get(bare))
            if note:
                # Settings-only (or settings-plus-text) difference must never
                # collapse to formatting_only/none -- it changes runtime
                # semantics even when the visible SQL is identical (L-11).
                if f["change_kind"] in ("formatting_only", "none"):
                    f["change_kind"] = "settings"
                    f["summary"] = f"Settings differ: {note}."  # replace the stale "No difference."/"Formatting only..." lead-in
                else:
                    f["summary"] = f"{f['summary']} Settings also differ: {note}."
            if item["type"] in compare.PROGRAMMABLE_TYPES:
                f["statement_map"], f["statement_alignment"] = _statement_map(f["master_def"], f["client_def"])
        elif item["role"] in ("added", "only_on_other"):
            f["summary"] = _side_summary(direction, item["role"], item["type"])
        else:
            f["summary"] = f"{item['action']} on {item['type']}."
    else:
        f["summary"] = f"{item['action']} on {item['type']}."

    # D1 (2026-07-26, hard-gated on D1a's extended-type flags): a
    # "structural" finding whose OWN change_kind resolved to exactly "none"
    # means every side effect this tool can capture -- text, columns, and
    # (as of D1a) FK/index/check/sequence/table-type disabled/trust/fill-
    # factor/cache/memory-optimized flags -- is identical on both sides.
    # SqlPackage still flagged the object as changed, typically as a side
    # effect of a related change (e.g. a table-rebuild FK cascade,
    # VALIDATION.md §10.2). Measured on real data before this fix
    # (work/output/1784497700_5ff79b/105_to_client): 3/15 (20%) of that
    # workspace's findings were exactly this. Demoted to a visible
    # no_difference bucket, never dropped -- still on disk, still in
    # index.json, just not counted as "modified" drift.
    #
    # Deliberately does NOT touch change_kind == "settings" (an L-11
    # upgrade from "none" just happened above -- re-demoting it here would
    # silently re-hide the exact runtime-semantics difference that upgrade
    # exists to surface) or a missing change_kind entirely (added/
    # only_on_other findings, or a type with no evidence captured at all --
    # absence of a diff is not evidence of sameness for those).
    # PLAN-V4 B.2a: ClientActive block scoping. Only attempted when the run
    # carries an ID and both captured definitions exist -- absent ID leaves
    # every finding untouched (byte-identical to pre-scope behavior). The
    # annotation NEVER changes category/role/change_kind; it adds `scope` and
    # may flag irrelevant_to_client when BOTH sides resolve structured and the
    # relevant-code fingerprints match (differences confined to blocks this
    # client never executes).
    if client_active_id is not None and item["type"] in compare.PROGRAMMABLE_TYPES \
            and f.get("master_def") and f.get("client_def"):
        ms = blocks.resolve_scope(f["master_def"], client_active_id)
        cs = blocks.resolve_scope(f["client_def"], client_active_id)
        scope = {
            "client_id": str(client_active_id),
            "master": {"ok": ms["ok"], "mode": ms.get("mode"),
                       "excluded": len(ms.get("excluded_blocks", [])),
                       "stats": ms.get("stats")},
            "client_side": {"ok": cs["ok"], "mode": cs.get("mode"),
                            "excluded": len(cs.get("excluded_blocks", [])),
                            "stats": cs.get("stats")},
        }
        if ms["ok"] and cs["ok"] and ms.get("fingerprint") and cs.get("fingerprint"):
            scope["master_fingerprint"] = ms["fingerprint"]
            scope["client_fingerprint"] = cs["fingerprint"]
            scope["irrelevant_to_client"] = ms["fingerprint"] == cs["fingerprint"]
        f["scope"] = scope

    if item["category"] == "structural" and f.get("change_kind") == "none":
        f["category"] = "no_difference"
        f["summary"] = (
            "No difference found in captured definition/columns/flags -- SqlPackage flagged this "
            "object as changed, most likely as a side effect of a related change elsewhere (e.g. a "
            "table rebuild cascading into an unrelated FK). Shown for visibility, not counted as drift."
        )

    return f


def _statement_map(master_def: str, client_def: str) -> tuple:
    """D7: (compact_summary, full_alignment_or_None). compact_summary goes
    into index.json (report_writer's index_findings entry) -- ok/reason/
    tag counts only, never the statement text itself, per the plan's
    "do not bloat index.json" instruction. full_alignment (None when
    either side's structure isn't trustworthy) is what report_writer
    writes to a SEPARATE per-finding .statements.json file, which is the
    only place statement TEXT is ever persisted -- api.py's /statements
    route reads that file on demand, same pattern as .diff/.columns.json.

    Never touches change_kind/category/role or anything the apply script
    reads -- this is presentation detail layered over the byte-exact
    detection above, exactly like diff_render.py is for the unified/split
    views. A False ok here means "show a text diff only", never "no
    changes" and never a crash."""
    master_parsed = statements.parse_statements(master_def)
    client_parsed = statements.parse_statements(client_def)
    if not (master_parsed["ok"] and client_parsed["ok"]):
        reason = master_parsed["reason"] if not master_parsed["ok"] else client_parsed["reason"]
        return {"ok": False, "reason": reason}, None

    aligned = statements.align_statements(master_parsed["statements"], client_parsed["statements"])
    counts = {}
    for a in aligned:
        counts[a["tag"]] = counts.get(a["tag"], 0) + 1
    return {"ok": True, "reason": None, "counts": counts, "total": len(aligned)}, aligned


def _blast_radius(bare: str, master_callers: dict, client_callers: dict) -> dict:
    m = master_callers.get(bare, {"callers": [], "unresolved": 0})
    c = client_callers.get(bare, {"callers": [], "unresolved": 0})
    all_callers = sorted(set(m["callers"]) | set(c["callers"]))
    return {
        "count": len(all_callers),
        "names": all_callers,
        "unresolved": m["unresolved"] + c["unresolved"],
    }


def _safe(p: Path) -> str:
    return "".join(ch if ch.isalnum() else "_" for ch in p.stem)[:40]


def _write_capture(run_dir, master_defs, client_defs, master_cols, client_cols,
                    master_hashes, client_hashes, master_all_settings, client_all_settings,
                    master_callers, client_callers, attribution_rows, lost_fixes):
    """D5d: persists everything recompare() needs that otherwise requires the
    live DB. master_hashes/client_hashes values are (type, HASHBYTES raw
    bytes) tuples -- bytes aren't JSON-serializable, and don't need to be:
    compare.find_formatting_only only ever compares two hashes for equality,
    so a hex string round-trips that comparison exactly. Full sweeps
    (hashes/settings) are stored whole, not scoped to detail_names, so a
    re-compare in a different direction or a future type filter (D5a) can
    still find_formatting_only/find_settings_only over objects outside the
    ORIGINAL run's changed-object set."""
    capture = {
        "master_defs": master_defs, "client_defs": client_defs,
        "master_cols": master_cols, "client_cols": client_cols,
        "master_hashes": {n: [t, h.hex()] for n, (t, h) in master_hashes.items()},
        "client_hashes": {n: [t, h.hex()] for n, (t, h) in client_hashes.items()},
        "master_all_settings": {n: [t, s] for n, (t, s) in master_all_settings.items()},
        "client_all_settings": {n: [t, s] for n, (t, s) in client_all_settings.items()},
        "master_callers": master_callers, "client_callers": client_callers,
        "attribution_rows": attribution_rows, "lost_fixes": lost_fixes,
    }
    (run_dir / "capture.json").write_text(json.dumps(capture), encoding="utf-8")


def _load_capture(run_dir: Path) -> dict:
    capture = json.loads((run_dir / "capture.json").read_text(encoding="utf-8"))
    capture["master_hashes"] = {n: (t, bytes.fromhex(h)) for n, (t, h) in capture["master_hashes"].items()}
    capture["client_hashes"] = {n: (t, bytes.fromhex(h)) for n, (t, h) in capture["client_hashes"].items()}
    capture["master_all_settings"] = {n: tuple(v) for n, v in capture["master_all_settings"].items()}
    capture["client_all_settings"] = {n: tuple(v) for n, v in capture["client_all_settings"].items()}
    return capture


def recompare(run_id: str, direction: str, log, type_filter=_UNSET) -> dict:
    """D5d: re-enter the pipeline at the `compare` phase for an EXISTING run,
    reusing its persisted .dacpac pair + capture.json instead of restore ->
    script -> extract (the ~7x-slower, per-database part). Turns iterating
    on direction into a ~30-40s operation instead of ~240s.

    Refuses (raises) rather than silently serving a stale result when: the
    run has no capture.json (predates D5d, or never finished that phase),
    either source .bak has changed size/mtime since the original run, or
    either cached .dacpac is missing from disk. All three are real
    invalidation conditions, not edge cases to paper over.

    type_filter: omit entirely (the _UNSET default) to reuse whatever
    filter the ORIGINAL run used -- least-surprise default, a "+ add this
    direction" click shouldn't silently widen scope beyond what was
    originally asked for. Pass an explicit set (or None for "no filter")
    to deliberately widen/narrow it; capture.json's full (unscoped) sweeps
    support this, but definitions/columns are only ever what the ORIGINAL
    run's own filter captured -- widening beyond that degrades gracefully
    (see the `missing` warning below), it does not fail."""
    if direction not in DIRECTIONS:
        raise ValueError(f"unknown direction {direction!r}")

    run_dir = config.OUTPUT_DIR / run_id
    meta_path = run_dir / "meta.json"
    if not meta_path.is_file():
        raise FileNotFoundError(f"no run {run_id!r} on disk")
    meta = json.loads(meta_path.read_text(encoding="utf-8"))

    capture_path = run_dir / "capture.json"
    if not capture_path.is_file():
        raise RuntimeError(f"run {run_id!r} has no persisted capture data (it predates the re-compare "
                            f"feature, or was interrupted before that phase) -- run a full compare instead")
    capture = _load_capture(run_dir)

    cache_key = meta.get("bak_cache_key")
    if not cache_key:
        raise RuntimeError(f"run {run_id!r} predates the re-compare feature (no bak_cache_key in meta.json) "
                            f"-- run a full compare instead")
    for side in ("master", "client"):
        _assert_source_cache_fresh(side, cache_key.get(side) or {})

    dacpac_master = Path(meta["artifacts"]["dacpac_master"])
    dacpac_client = Path(meta["artifacts"]["dacpac_client"])
    if not dacpac_master.is_file() or not dacpac_client.is_file():
        raise FileNotFoundError(f"cached .dacpac file(s) missing from {run_dir} -- run a full compare instead")

    if type_filter is _UNSET:
        stored = meta.get("type_filter")
        type_filter = set(stored) if stored else None

    t0 = time.time()
    log(f"=== re-compare {run_id}: direction={direction} (reusing cached .dacpac pair, no restore) ===")
    if type_filter:
        log(f"  ⚠ TYPE FILTER ACTIVE: only {sorted(type_filter)} -- this run is PARTIAL (D5a)")
    exclusions = compare.load_exclusions()

    source_dacpac, target_dacpac = (
        (dacpac_client, dacpac_master) if direction == "client_to_105" else (dacpac_master, dacpac_client)
    )
    source_hashes, target_hashes = (
        (capture["client_hashes"], capture["master_hashes"]) if direction == "client_to_105"
        else (capture["master_hashes"], capture["client_hashes"])
    )
    source_settings, target_settings = (
        (capture["client_all_settings"], capture["master_all_settings"]) if direction == "client_to_105"
        else (capture["master_all_settings"], capture["client_all_settings"])
    )

    diff_xml = compare.run_deploy_report(source_dacpac, target_dacpac,
                                          run_dir / f"diff_{direction}_recompare.xml", log)
    parsed = compare.parse_deploy_report(diff_xml, exclusions, log, type_filter=type_filter)
    items = parsed["items"]
    filtered_out = parsed["filtered_out_count"]
    already_seen = {compare.bare_name(i["name"]) for i in items}
    fmt_items, fmt_filtered = compare.find_formatting_only(
        source_hashes, target_hashes, already_seen, exclusions, type_filter=type_filter)
    items = items + fmt_items
    filtered_out += fmt_filtered
    already_seen = {compare.bare_name(i["name"]) for i in items}
    settings_items, settings_filtered = compare.find_settings_only(
        source_settings, target_settings, already_seen, exclusions, type_filter=type_filter)
    items = items + settings_items
    filtered_out += settings_filtered

    new_detail_names = {
        compare.bare_name(i["name"]) for i in items
        if i["category"] in ("structural", "formatting_only")
    }
    captured_names = set(capture["master_defs"]) | set(capture["client_defs"]) | \
        set(capture["master_cols"]) | set(capture["client_cols"])
    missing = sorted(new_detail_names - captured_names)
    if missing:
        log(f"  WARNING: {len(missing)} object(s) changed in this direction have no captured detail from "
            f"the original run ({missing[:5]}{'...' if len(missing) > 5 else ''}) -- shown with limited "
            f"detail (no diff text). This is expected only if the original run used a type filter that "
            f"excluded them; run a full compare to capture them properly otherwise.")

    master_settings = {n: v[1] for n, v in capture["master_all_settings"].items() if n in new_detail_names}
    client_settings = {n: v[1] for n, v in capture["client_all_settings"].items() if n in new_detail_names}

    attribution_by_name = {}
    for row in capture["attribution_rows"]:
        attribution_by_name.setdefault(row["object"], []).append(row)

    enriched = [
        _enrich(it, direction, capture["master_defs"], capture["client_defs"],
                capture["master_cols"], capture["client_cols"], attribution_by_name,
                capture["master_callers"], capture["client_callers"], master_settings, client_settings,
                client_active_id=(meta.get("client_active_id") if isinstance(meta, dict) else None))
        for it in items
    ]
    detail_findings = [f for f in enriched if f["category"] in ("structural", "formatting_only", "no_difference")]
    documentation_list = [{"name": f["name"], "type": f["type"]} for f in enriched if f["category"] == "documentation"]
    cascading_list = [{"name": f["name"], "type": f["type"]} for f in enriched if f["category"] == "cascading"]

    workspace_dir = run_dir / direction
    index = report_writer.write_workspace(
        workspace_dir, direction, detail_findings, documentation_list, cascading_list,
        capture["attribution_rows"], capture["lost_fixes"], parsed["excluded_count"], log,
        filtered_out_count=filtered_out, type_filter=type_filter,
    )

    elapsed = round(time.time() - t0, 1)
    if direction not in meta["directions"]:
        meta["directions"].append(direction)
    meta.setdefault("recompares", []).append({"direction": direction, "seconds": elapsed})
    report_writer.write_meta(run_dir, meta)

    log(f"=== re-compare done in {elapsed}s: {index['counts']['modified']} modified / "
        f"{index['counts']['added']} added / {index['counts']['only_on_other']} only-on-other ===")

    return {"run_id": run_id, "run_dir": str(run_dir), "meta": meta, "direction": direction,
            "index": index, "findings": detail_findings}
