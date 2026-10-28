# Full Update compare and executable trimmer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the query trimmer emits a batch SQL Server can parse for any input, and add a Full Update button that writes per-database schema scripts, per-database user-defined table type scripts (the same file drops a type and recreates the modules it dropped), and one dependency-ordered unified script, with the old-tool procedure exclusions visible and applied as exclusions.

**Architecture:** Leave the existing Compare / Apply path on sqlpackage and `scriptgen.assemble` (additive, never writes server 105). Add a separate generator, `drift/full_update.py`, that diffs two in-memory catalogs and writes files only. The left catalog is a recorded stand-in for server 105. The right catalog is the Client connection already in the Schema tab, or a live read of the local SQL Server. A `.bak` left side is restored physically as `drift_left_<id>` and dropped in `finally`; the catalog key, `USE`, and output filename come from `RESTORE HEADERONLY.DatabaseName` (for the 105 stand-in, `Olives_BO`). Procedure exclusions live in one Python tuple and are shown in a dialog. Generated SQL is UTF-8 with BOM and CRLF, written as bytes.

**Tech Stack:** Python 3.13, Flask, existing `pymssql` connection helpers, unittest, the local Docker SQL Server `mssql` on port 1433 for read-only capture, `SET PARSEONLY` of the trimmed large procedure, and one required order proof that executes only on `drift_right_<id>`. No new services.

**Branch:** `feature/full-update-compare` (created from `origin/main` at `c329908`). This planning revision does not commit and does not push. Implementation commits on `feature/full-update-compare` only, through the named integration tasks below. Never switch the main workspace to `main`.

**Plan path (read this absolute path from every worktree):** `/media/alaa/data/my apps/Drift-SQL-Tool/docs/plans/2026-10-28-full-update-compare.md`

Devil's advocate verdict on 2026-10-28 was **AMEND THEN SHIP**. A1–A14 are accepted in full. No further review round. The task bodies below already contain those amendments. Follow the task bodies.

## Global Constraints

- Generated Full Update files are never executed by the app. There is no Apply button for them.
- Do not open a connection to `10.0.10.105`. That host is not reachable from this machine. Left is a catalog file or a `.bak` restored under a new temporary name.
- Do not execute generated DDL against the databases already online in the local `mssql` container: `Olives_BO`, `olives_PEEK`, `Olives_POS`, `OSFA_DB`, `osfa_PEEK`. `SET PARSEONLY ON` against `Olives_BO` is allowed for the trimmed-procedure test (T7) only. Restores for capture use `drift_left_<id>`. The order proof executes only against a new `drift_right_<id>`, then `DROP DATABASE`. `SET PARSEONLY` of the multi-batch unified file is not the order proof, and executing it against `drift_left_<id>` is not the order proof either (those objects already exist).
- The catalog key, the `USE` name, and the output filename for a restored bak come from `RESTORE HEADERONLY.DatabaseName`. Restoring as `drift_left_<id>` must not make the script target `drift_left_<id>`.
- Procedure-filter tokens are exactly the two lists in **Do not change**. Do not add tokens. Do not anchor them.
- Do not change `exclude-from-drift.txt` and do not change `scriptgen.assemble` drop behavior.
- Windows: `pathlib` for paths, no bash or GNU-only commands inside the app, generated `.sql` is UTF-8 BOM + CRLF on every OS, written with `Path.write_bytes` (not text mode). `.bat` stays CRLF and `.sh` stays LF, per `.gitattributes`.
- Passwords stay out of scripts, catalogs, `meta.json`, and git. The planning read used the container's own `MSSQL_SA_PASSWORD` and did not copy it.
- Executor commits on lane branches, then the named integration tasks merge those branches into `feature/full-update-compare`. Push that branch only in T10, after `/qa`. Never push `main`.
- Lane worktrees are separate checkouts. T1, T2, and T3 must not share the main workspace. Do not edit this plan file from a lane.

## Do not change

Copied from the devil's advocate. These are constraints, not bugs to fix.

- Contains tokens, exactly: `alpha`, `sap`, `bonanza`, `integ`, `mms`, `jawad`, `hammoudeh`, `technical`, `niroukh`, `api`, `medical`, `poa`, `tax`, `asset`, `thuraya`, `cmms`, `memo`.
- Starts-with tokens, exactly: `sp`, `oms`, `sms`, `owms`.
- Do not add tokens. Do not anchor `sp`, `api`, `integ`, `memo`, or `tax` to a word boundary or to an underscore. `sp` matching `Spartan_SAP_Integ` and `SpecialReport` is the requested prefix. `integ` matching 397 procedures is the requested substring. Starts-with `sp` matching `Spartan_*` and contains `integ` matching many procedures is the requested blast radius, not a bug.
- Contains and Starts with exclude. They do not filter the grid down to matching names. Several rules combine with OR.
- Do not merge this list into `exclude-from-drift.txt`. Do not change that file's `fnmatch` behavior.
- Do not drop an excluded procedure or function in order to `DROP TYPE`. Skip the type.
- Do not add `GRANT` / user / role scripting. Permissions stay out of scope. The outage to avoid is dropping a module in the table-type file and recreating it only in a later phase. Recreate it in the same file (A3). Do not add a permission feature.
- Do not generate Full Update SQL with sqlpackage, `livescan`, or `_start_compare_job`.
- The application does not execute the generated files. T7 may `SET PARSEONLY` against `Olives_BO`. T10 may restore `olives_bo.bak` to `drift_left_<id>` for capture, then drop it. T10's order proof executes only on `drift_right_<id>`, then drops it. Never execute a generated script against `Olives_BO`, `olives_PEEK`, `Olives_POS`, `OSFA_DB`, or `osfa_PEEK`.
- Do not push `main`.

---

## Problem

Operators need a script that moves a client database toward the master image on server 105. This machine cannot connect to 105. The current Compare button builds an additive apply script from an approved finding list and refuses to `DROP` a changed table type. The old desktop SQL Compare (DB1 = source `10.0.10.105`, DB2 = target) scripted procedures as drop-and-create and built table types by hand. The new button has to write the files, including table types as `DROP` + `CREATE`, in an order that survives dependency errors, while a procedure filter hides the customer-specific procedures the operator already excludes.

The trimmer must return SQL that is ready to parse, including a procedure that is not a stored procedure wrapper, a multi-batch script, and the large `Olives_BO` procedures. It must not wrap arbitrary SQL as `CREATE PROCEDURE [dbo].[Unknown]`. A `USE` batch stays a real `USE` batch.

## Current code map

| Area | File | What it does today |
|---|---|---|
| Compare UI | `templates/index.html` 141-228 | Schema tab. Master (105) and Client slots, Live or Bak. Object-type checkboxes default to Tables, Indexes, Constraints (`schema_default` at line 169). Compare button is `#go` (line 178). No Full Update button. No procedure-exclusion dialog. |
| Findings search | `static/app.js` 938-951 | `renderFindingsTable` keeps rows whose `bare_name` includes the search string (line 951). This is an include filter. It is not the procedure exclusion list. |
| Compare job | `app.py` 598-679, 462-492 | `POST /api/compare` starts `_start_compare_job`. Live sides require `server` and `database` (line 630). The job `kind` is `compare` (`app.py` 465). |
| Result stream | `app.py` 762-784 | `api_stream` emits `workspaces` for every kind except `ai_batch` (lines 779-783). A Full Update result that has `files` and no `workspaces` raises `KeyError`. |
| Busy button | `static/app.js` 56-84, 585-625 | `setBusy` disables the button. `clearBusy` runs on the compare stream's `result` or `error` event, and on POST failure. It does not re-enable when the job id returns. |
| Live connect | `app.py` 403-421 | `_sql_connect` uses the `database` field on the side dict. `livescan.connect` when port is omitted, `pymssql` with `port` when a port is set. SQL login only. |
| DB list | `app.py` 578-595 | `POST /api/live/databases` lists `sys.databases` where `database_id > 4`. |
| Pipeline | `drift/pipeline.py` 65-129, 168-184 | Restore or live extract, dacpac, `compare.run_deploy_report`. Direction `105_to_client` uses master as source and client as target (lines 173-174). |
| Deploy report roles | `drift/compare.py` 45-46, 78-104, 154-213 | `Create` → added, `Drop` → only_on_other, else modified. `is_excluded` (line 102) uses `fnmatch` on the bare name against `exclude-from-drift.txt`. |
| Exclusion file | `exclude-from-drift.txt` 1-24 | Globs such as `*_Jebrene`, `*alpha*`, `*_integ`, `Dynamics*`. This is a different list from the procedure filter. On Linux `fnmatch` is case-sensitive, which is why the file repeats `*alpha*` and `*Alpha*`. |
| Apply script | `drift/scriptgen.py` 56-194, `app.py` 936-975 | Approved findings only. `only_on_other` is never dropped unless `include_deletions`. Modules become `CREATE OR ALTER` plus `SET ANSI_NULLS` / `SET QUOTED_IDENTIFIER` and `GO` (`scriptgen.py` 273-310). Added table types are `IF TYPE_ID(...) IS NULL EXEC(N'CREATE TYPE ...')` (lines 188-192). Modified table types are manual review (lines 178-182). |
| Module rewrite | `drift/scriptgen.py` 260-304 | `_find_create_keyword` finds `CREATE`. `_as_create_or_alter` writes `CREATE OR ALTER` at that span. A definition that already says `CREATE OR ALTER` becomes `CREATE OR ALTER OR ALTER`. |
| Table type capture | `drift/inspect_objects.py` 531-578 | `get_table_type_definitions` builds `CREATE TYPE`. Line 574 appends ` PRIMARY KEY` to every key column. Two live types have 3-column keys, so that string is illegal. Do not emit it. |
| Index capture | `drift/inspect_objects.py` 289-359 | `get_index_definitions` emits `CREATE PRIMARY KEY CLUSTERED INDEX ...` (line 346) and appends ` [FLAGS: ...]`. SQL Server rejects that. Do not emit it. The legal primary key is `ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY`. |
| Scalar UDT capture | `drift/inspect_objects.py` 581-598 | `CREATE TYPE ... FROM ...`. |
| Type rendering | `drift/inspect_objects.py` 278-286 | `_rendered_type_ext` turns `nvarchar` `max_length` 40 into `nvarchar(20)` (length in characters, bytes divided by 2). |
| Caller graph | `drift/dependencies.py` 31-56 | `get_callers` reads `sys.sql_expression_dependencies` for a name set. It does not order a script. The column is `referenced_database_name`. There is no `referenced_database_id` column. |
| Trimmer | `drift/trimmer.py` 95-149, route `app.py` 211-214 | Strips the preamble before `CREATE`/`ALTER`, resolves `@ClientActive` with `blocks.resolve_scope`, and always emits `header + BEGIN + body + END` (line 138). A missing header becomes `CREATE PROCEDURE [dbo].[Unknown] AS` (lines 131-134). |
| Scope engine | `drift/blocks.py` 463-496, 512-513, 660-668 | Invalid `client_active_id` returns `ok=False` (lines 495-496). "no statement boundaries" (512-513), unbalanced `BEGIN`/`END` (660), and a cursor or unrecognized body with nothing to delete (668) also return `ok=False`. Those non-id failures must not become HTTP 400 for the trimmer. |
| Scratch restore | `drift/restore.py` 112-181 | `restore_backup` restores under the `db_name` it is given. It reads `RESTORE HEADERONLY` but returns only `backup_date` and `engine_major_version` (line 181). It does not return `DatabaseName`. |
| Windows process flags | `drift/config.py` 185-186, 208-220, 257 | Windows auth rejected when `os.name != "nt"`. `sqlpackage.exe` on Windows. `NO_WINDOW` is `CREATE_NO_WINDOW` on Windows. |
| Line endings | `.gitattributes` | `*.bat text eol=crlf`, `*.sh text eol=lf`. `*.sql` is not forced. Text-mode writes on Windows turn an already-CRLF string into CR CR LF. |
| PyInstaller | `drift-tool.spec` 12-28 | Collects imports from the entry module. New modules are included when `app.py` imports them. Test fixtures are not datas. |
| Old tool | `docs/legacy/sql-compare/SQL_Compare_Reverse_Engineering_Report.md` 207-279, 358-367 | Left picker is source, right picker is target. Shipped config: Server1 `10.0.10.105`, Server2 `.`. Procedures are drop-and-create. Table types are a hand-built `CREATE TYPE ... AS TABLE`. Grid `ActiveFilterString` is a DevExpress grid filter (line 232). That report does not define a Contains button that excludes names. The exclusion semantics in this plan come from the user's lists. |
| Livescan | `drift/livescan.py` 10-17, 178-190 | `SCAN_ONLY = True`. No script function, on purpose. `connect` has no port argument. |

## What already exists

Reuse these. Do not rebuild them.

- Side model `kind` `live` or `bak`, redaction of `password` (`app.py` 434-437), and the job queue shape (`_start_compare_job`). Do not call `_start_compare_job` for Full Update.
- Catalog reads in `inspect_objects.py` for column types (`_rendered_type_ext`). Do not reuse `get_table_type_definitions` or `get_index_definitions` as script text. Their strings are illegal for a multi-column primary key and for `CREATE PRIMARY KEY ... INDEX`.
- `scriptgen._as_create_or_alter` for modules, after T2 changes it so an existing `CREATE OR ALTER` stays one phrase. Call that function. Do not copy a second prefix rewriter into `full_update.py`. Do not route Full Update through `assemble`.
- `blocks.resolve_scope` and `hoist_declares` for the trimmer. Fix the wrapper around them.
- `statements._mask_literals_and_comments` so a `GO` inside a string is not a batch boundary, and so the words `CREATE PROCEDURE` inside a string are not a module.
- Existing Compare, Apply, data copy, and web deploy. They stay as they are.
- `exclude-from-drift.txt` for the existing Compare button only.

`livescan` stays scan-only. A test already asserts it has no script entry point (`tests/test_livescan.py`). Full Update does not import it for generation.

## Observed local facts (read-only, 2026-10-28)

These are measurements, not guesses. The container `mssql` (`mcr.microsoft.com/mssql/server:2022-latest`) listens on port 1433. `drift-tool-mssql` on 14330 is not running. Host `sqlcmd` is absent. Queries ran inside the container. The devil's advocate measured the same instance.

Database `Olives_BO` collation: `SQL_Latin1_General_CP1256_CI_AS` (case-insensitive).

| Objects | Count |
|---|---|
| Stored procedures | 1664 |
| User tables | 440 |
| Views | 428 (412 of them in schema `t`, and those 412 are `SELECT *`) |
| Scalar functions | 164 |
| Inline TVFs | 76 |
| Multi-statement TVFs | 50 |
| Triggers | 1 |
| User-defined table types | 119 (108 have no primary key; `CustomersPromotionsGroupsLink_Type` and `Meatland_Integration_PriceLists` have 3-column primary keys) |
| Scalar user-defined types | 0 |
| Foreign keys | 485 |
| Schema-bound modules | 0 |
| Indexed views | 0 |
| Module texts that already contain `CREATE OR ALTER` | 0 (the next Full Update will store that phrase; the run after that must not emit `CREATE OR ALTER OR ALTER`) |
| Procedures whose text contains `@ClientActive` | 210 |
| Table-type dependency rows (`referenced_class_desc = 'TYPE'`) | 178, all stored procedures |
| Procedure edges to `OSFA_DB` | 672 |
| Procedure edges to `olives_BO` (this database, different casing) | 183 |
| View edges to `Olives_OWMS` (not on this instance) | 6, including `IssueMaster` → `Olives_OWMS.dbo.Items` |
| Function pairs where the caller sorts before the callee | 41 (example: `dbo.Fun_CalcDistanceBetweenTwoPoints` references `dbo.Trim`) |
| Table types referenced by at least one default-excluded name | 53 of 119 (skip `DROP TYPE`; do not drop the excluded procedure) |

Largest procedures by `LEN(definition)`: `dbo.OT_SendSalesmanData` 900940 (contains Arabic letters), `dbo.OT_SendSalesmanData_Test` 864771, `dbo.OT_SendCustomersInfo` 379805. The code comment in `blocks.py` line 467 describes an older 218KB measurement of `OT_SendCustomersInfo`. Validation uses `OT_SendSalesmanData`, read through `pymssql` so the Arabic body is not decoded with the container's default code page.

`dbo.ClientsActive` columns: `CompanyID`, `ClientID`, `WF_ClientID`, all `smallint`. 8 rows. Distinct `ClientID` values: 0, 62, 122, 124, 207. Equality gates inside `OT_SendSalesmanData` (`@ClientActive = <id>` or `<id> = @ClientActive`): 0, 62, 122, 124 are present. 207 is active in the table and has no equality gate in that procedure.

Default exclusion tokens, under this collation, match 568 of 1664 procedures and 31 functions. `name LIKE 'sp%'` matches 11 names: `sp_alterdiagram`, `sp_creatediagram`, `sp_dropdiagram`, `sp_helpdiagramdefinition`, `sp_helpdiagrams`, `sp_renamediagram`, `sp_upgraddiagrams`, `SP_IntegrationErrorLog`, and three `Spartan_SAP_Integ*` procedures. Contains `integ` matches 397 procedures. Contains `api` matches 30. Contains `memo` matches 4. Starts-with `sms` matches 18. That width is the list the user gave. Do not narrow it.

Sample view, schema `t`: `CREATE VIEW t.[ActivityList] AS SELECT * FROM dbo.[ActivityList]`. An unchanged copy of that text still has to be emitted when this script adds or alters a column of `dbo.ActivityList`. Schema qualification comes from the catalog (`[t].[ActivityList]`, not `dbo`).

105 stand-in file on disk (not a live server): `/media/alaa/data/olives/data/db-snapshots/backup test/105/olives_bo.bak` (1175 MB). Its `RESTORE HEADERONLY.DatabaseName` is `Olives_BO`. Sibling `osfa.bak` is in the same folder. Client-side snapshot also exists at `.../backup test/morec/Olives_BO.bak`. Disk free on this volume: about 622 GB. Do not commit these files.

No `work/scratch_server.json` and no `.env` in the repo. Right-side tests that need a password read `MSSQL_SA_PASSWORD` from inside the container, or `DRIFT_RIGHT_PASSWORD` from the environment. Do not print the password.

## Data flow

```
Operator
  |
  |  Left source                         Right source
  |  kind=catalog  tests/fixtures/...    Client slot (server, port, database, SQL login)
  |  kind=bak      105/olives_bo.bak     physical restore name drift_left_<id>
  |                catalog key =         dropped in finally
  |                HEADERONLY.DatabaseName
  |                (Olives_BO), not the
  |                physical name
  |  kind=live     only if a real host   never 10.0.10.105 from this machine
  v
POST /api/full_update
  |
  +-- load_catalog(path)
  +-- capture_live_catalog(connector, physical_or_live_name)
  |     connector is called once per database name
  |     the side dict's database field is that name (a copy of the slot side)
  |     bak: connect to drift_left_<id>, then store the catalog under
  |     the header DatabaseName
  |
  v
diff per requested database
  default: the selected right database, if the left catalog has the same
           name under casefold (Olives_BO matches olives_BO)
  checkbox: casefold intersection of user databases
  |
  +-- procedure_excluded(bare_name, rules)     rules default to the dialog list
  |
  v
order_database(diff)  -->  batches
  |
  +-- {HeaderName}_udtt.sql
  |     DROP non-excluded referencers, DROP TYPE, CREATE TYPE,
  |     then CREATE OR ALTER of every module this file just dropped
  |     never DROP an excluded name
  +-- {HeaderName}_schema.sql
  |     tables, views, functions, procedures that the udtt file did not
  |     already recreate; no CREATE TYPE and no DROP TYPE
  +-- unified_full_update.sql
  |     every database, referenced database first (not alphabetical),
  |     same recreate-immediately rule inside the type phase
  |
  v
write_sql_file: UTF-8 BOM + CRLF bytes under work/output/<run_id>/full_update/
job kind = full_update
/api/stream emits {run_id, meta, files} and does not read workspaces
UI offers download. The server does not execute the files.
The Full Update button stays disabled until that stream's result or error.
```

Catalog dict (both sides). Keys are the logical database name (`Olives_BO`), never `drift_left_<id>`.

```python
{
  "server_label": "105-stand-in",
  "databases": {
    "Olives_BO": {
      "objects": {
        "dbo.KeepMe": {
          "schema": "dbo", "name": "KeepMe", "type": "SqlProcedure",
          "definition": "CREATE PROCEDURE [dbo].[KeepMe] ...",
          "ansi_nulls": True, "quoted_identifier": True,
          "schema_bound": False,
        }
      },
      "dependencies": [
        {
          "from": "dbo.UsesType",
          "to": "dbo.Tvp",
          "to_class": "TYPE",
          "referenced_database_name": None,
        }
      ],
    }
  },
}
```

Keys are `schema.name`. Table types use `type` `SqlUserDefinedTableType`. Passwords are not a field. A dependency whose `referenced_database_name` casefolds to the database being scripted (`olives_BO` versus `Olives_BO`) is a same-database edge. There is no `referenced_database_id` field.

Column record stored on a table object (decision 28, amended by A9):

```python
{
  "name": "Name",
  "type": "nvarchar",
  "max_length": 40,
  "precision": 0,
  "scale": 0,
  "nullable": True,
  "identity": None,
  "computed": None,
  "default": None,
}
```

`identity` is `{"seed": 1, "increment": 1}` or `None`. `computed` and `default` are expression strings or `None`. Render `type` through `inspect_objects._rendered_type_ext`. `max_length` 40 for `nvarchar` is `nvarchar(20)`.

## Dependency order

Unified script, and the per-database files. Inside one database the phases are fixed. `CREATE SCHEMA` is phase A and is its own batch. Table types are phase B, and the modules they drop are recreated in that same phase, in that same file, immediately after `CREATE TYPE`. Views and functions share one topological order. Procedures that were not already recreated in phase B rely on deferred name resolution, so a cycle between procedures is still emitted (`CREATE OR ALTER` in name order). A cycle between views, or between functions, and any node that still edges into that cycle, is removed from the executable section and printed in the trailing manual appendix.

```
USE [Db];
GO
-- phase A  CREATE SCHEMA [name] for every non-dbo schema this script will
--          write into. Each CREATE SCHEMA is the only statement in its
--          batch, then GO, and it runs before any type, table, or module
--          in that schema. dbo is not emitted. Error 111 if anything else
--          shares the batch.
-- phase B  table types that are missing or whose rendered definition differs
--          if every referencing module is either recreated in THIS file
--          immediately after CREATE TYPE, or does not exist on the right:
--            DROP PROCEDURE/FUNCTION/VIEW for referencers that
--            procedure_excluded() is false for
--            never DROP an excluded name
--            IF TYPE_ID(N'[schema].[name]') IS NOT NULL DROP TYPE [schema].[name];
--            GO
--            CREATE TYPE ... AS TABLE (...);   -- at most one PRIMARY KEY
--            GO
--            CREATE OR ALTER of every module this file just dropped
--            GO
--          else (excluded referencer, or schema-bound referencer):
--            PRINT 'SKIP DROP TYPE ...' and a -- SKIP comment naming it
--            do not DROP TYPE and do not DROP that referencer
-- phase C  sequences: CREATE if missing; a difference goes to the appendix
-- phase D  scalar UDTs: CREATE if missing; a changed one goes to the appendix
--          (Olives_BO has zero scalar UDTs today)
-- phase E  tables: CREATE if missing on the right (left definition, identity
--          included on a new table);
--          ALTER TABLE ADD for a nullable column, rendered with
--          _rendered_type_ext;
--          ALTER TABLE ADD ... NOT NULL CONSTRAINT ... DEFAULT ... as one
--          statement when the column has a default;
--          NOT NULL without a default, and any computed or identity add on
--          an existing table, go to the appendix (no ADD of those)
-- phase F  functions and views together, one order_names() call
--          (dependent, referenced) so the referenced object is first
--          a view is emitted even when its text matches the right side if
--          this script adds or alters a column of a table that view
--          references (the 412 schema-t SELECT * wrappers)
--          qualify the schema from the catalog: [t].[ActivityList]
--          skip any module already emitted in phase B
--          a view, function, or trigger whose referenced_database_name is
--          not this database and is not present on the right-hand catalog
--          goes to the appendix and is not emitted as CREATE OR ALTER
--          procedures with an absent target database stay in the script
-- phase G  procedures not already emitted in phase B, name order,
--          CREATE OR ALTER via scriptgen._as_create_or_alter,
--          filter-excluded names omitted, absent-target procedures kept
-- phase H  triggers, CREATE OR ALTER, same absent-database rule as views
-- phase I  indexes and unique/primary-key constraints
--          before the script drops an index or unique constraint, it drops
--          foreign keys that reference it (error 3723 otherwise)
--          a primary key or unique constraint is
--          ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY|UNIQUE
--          a non-constraint index is CREATE [UNIQUE] INDEX, with INCLUDE
--          and WHERE when captured
--          do not emit get_index_definitions text and do not emit [FLAGS:]
--          an index that belongs to a view is emitted immediately after
--          that view
-- phase J  foreign keys, including every foreign key phase I dropped
-- phase K  manual appendix (comments and PRINT only)
```

Databases in the unified file are ordered by cross-database edges. Read `referenced_database_name`. A name that casefolds to the database being scripted is not a cross-database edge. The referenced database is emitted first. The fixture database `Aaa` references `Zed`, and `Zed` sorts after `Aaa`, so the file contains `USE [Zed]` before `USE [Aaa]`. Alphabetical order and the old `USE [DbA]` before `USE [DbB]` pair are not proof. A cycle at database level falls back to casefold name order and a one-line warning.

Failure modes this order is there to avoid:

| SQL Server error | Cause | What the script does |
|---|---|---|
| 111 | `CREATE SCHEMA` shares a batch with another statement | Phase A batch is only `CREATE SCHEMA [name]` then `GO` |
| 3732 | `DROP TYPE` while a procedure still references it | Drop eligible referencers first, or skip `DROP TYPE` and `PRINT` the skip |
| 2714 | object already exists | `CREATE OR ALTER` for modules (one phrase, never `CREATE OR ALTER OR ALTER`); `IF TYPE_ID IS NOT NULL DROP TYPE` before `CREATE TYPE`; `IF OBJECT_ID IS NULL` around `CREATE TABLE` |
| 208 | view or function created before the object it names | Tables and types before views and functions; topo inside views and functions; callee before caller |
| 207 | column missing when a `SELECT *` view is left stale | Re-emit that view after `ALTER TABLE ADD` |
| 4901 | `ADD ... NOT NULL` with no default on a table that has rows | Nullable adds are emitted; `NOT NULL` without a default goes to the appendix; `NOT NULL` with a default is one `ADD` statement that includes the default |
| 3723 | dropping a primary key or unique index while a foreign key references it | Phase I drops those foreign keys first; phase J creates them again |
| 1767 | foreign key before both tables exist | Phase J after tables and after the primary key they reference |
| 1750 / 1913 | index before the table | Phase I after tables |
| View or function cycle | two objects naming each other | Those objects, and anything that still references them, move to phase K |

`DROP TYPE` is always inside `IF TYPE_ID(N'[schema].[name]') IS NOT NULL`. An excluded procedure that references the type blocks the drop. The type is then not recreated either, because a second `CREATE TYPE` would fail with 2714. The skip is loud (`PRINT` plus a `-- SKIP` comment). The schema file still updates every other object.

Per-file contract, written in the first comment lines of each file:

- `{db}_udtt.sql` contains, for each eligible changed type, the `DROP` of the non-excluded referencers, the `DROP TYPE`, the `CREATE TYPE`, and then `CREATE OR ALTER` of every module that file dropped, immediately after `CREATE TYPE` and before any later phase. Running it alone does not leave those procedures missing. It never contains `DROP` of an excluded name. Grants on those modules are not re-scripted; that stays out of scope.
- `{db}_schema.sql` has no `DROP TYPE` and no `CREATE TYPE`. It carries tables, constraints, and modules that phase B did not already recreate. Running it alone updates those objects and leaves table types as they are.
- `unified_full_update.sql` uses the same phase B recreate. It does not wait until phase G to put the dropped modules back. It is not a transaction. A schema-bound referencer, or a referencer we cannot render, skips that `DROP TYPE` the same way an excluded procedure does.

Object-by-object rules (left is the wanted definition, right is the target):

| Type | Only on left | Only on right | Different |
|---|---|---|---|
| SqlTable | `CREATE TABLE` from the left definition, identity included | leave it | `ADD` missing columns with length, precision, scale, and an inline default when `NOT NULL`; drops, retypes, identity adds, computed adds, and `NOT NULL` without a default in the appendix |
| SqlUserDefinedTableType | phase B create, one `PRIMARY KEY` constraint or none | leave it | phase B drop-and-create plus immediate `CREATE OR ALTER` of modules this file dropped, or skip |
| SqlUserDefinedType (scalar) | phase D create | leave it | appendix |
| Sequence | create | leave it | appendix |
| View, function, procedure, trigger | `CREATE OR ALTER` | leave it | `CREATE OR ALTER` from the left, via `scriptgen._as_create_or_alter` |
| View whose text matches but a referenced table gains or changes a column | emit `CREATE OR ALTER` after the table change, schema-qualified | leave it | same |
| View, function, or trigger whose referenced database is absent on the right | appendix, not `CREATE OR ALTER` | leave it | appendix |
| Procedure whose referenced database is absent on the right | still `CREATE OR ALTER` (deferred name resolution) | leave it | still emitted |
| Module whose text is unchanged but which references a table type this script drops | same file: `DROP` then, immediately after `CREATE TYPE`, `CREATE OR ALTER` the left text | leave it | same |
| Procedure or function whose bare name matches the filter | omit | leave it | omit, even if the text differs. If it also references a type we would drop, skip that type. Never `DROP` the excluded name |
| Index, default, check, FK | create | leave it | drop-and-create of that constraint only; foreign keys that reference a dropped key are dropped first and created again in phase J |
| Users, roles, permissions, data rows, assemblies | omit | omit | omit |

## Decisions (auto, user forbade questions)

Each row is a gate the review would have asked. The chosen option is the one that covers the stated requirement. Completeness 10 means the edge cases in this plan are included. 7 means the happy path only.

### Session and process gates

1. **gstack upgrade 1.58.3.0 to 1.91.283.0.** Decided: snooze (`Not now`), file `~/.gstack/update-snoozed` written for 1.91.283.0. Why: the upgrade path runs `git reset --hard` inside the skill install while this session is executing that skill. Alternatives rejected: upgrade now, always auto-upgrade. Completeness: options differ in kind. The SQL plan does not get more coverage from a newer gstack mid-write.
2. **Design doc / office-hours.** No design doc existed for this branch. Decided: do not run the interactive office-hours skill. The problem statement, the rejected approaches, and the chosen approach are in this file. Why: that skill stops for questions, and the user forbade questions. Alternative rejected: run office-hours and wait. Completeness: 10 for the requested plan file. A second design doc would not add a requirement that is missing here.
3. **Lake intro, telemetry, routing, vendoring, writing style.** Lake intro already seen. Telemetry already prompted and left off. Routing already declined (`ROUTING_DECLINED` true), so `CLAUDE.md` is not created and nothing is committed. gstack is not vendored in this repo. Writing-style prompt already answered. Artifacts sync stays off because gbrain is not on `PATH`. Completeness: these gates were already settled or do not apply. No product files change.
4. **Cross-project learnings.** Enabled, search run. Three hits, all from other products (Workers passwords, chatbot RAG, Arabic FTS synonyms). None apply. The plaintext-password preference is rejected here: this tool already strips `password` in `_redact_side` (`app.py` 434-437) and Full Update keeps doing that. Completeness: 10 for this repo's credential rule.
5. **Scope size.** The work touches more than 8 files and adds two modules. Decided: proceed with the full behavior the user listed (per-database scripts, table-type scripts, unified script, visible exclusions, trimmer compile check, Windows bytes). Why: dropping the unified script or the table-type file would miss a stated output. Alternative rejected: one script and no dialog (about 6/10). Completeness: 10.
6. **TODOS.md.** Decided: deferred items live in "NOT in scope" in this plan. Do not add a repo `TODOS.md` in the planning session. Why: the user asked for one plan file and no product edits. Alternative rejected: create and commit `TODOS.md`. Completeness: 9 for tracking (the items are written down). 10 would also add the file, which this session must not do.
7. **jq.** Not installed. The eng-review JSONL artifact is skipped, per the skill's fallback. Completeness: not a product gap.
8. **Outside voice.** `codex` is not installed. A Claude subagent was the first outside voice (decisions 26-39). The devil's advocate on 2026-10-28 is the second and last review. Completeness of the plan does not wait on Codex.

### Product gates

9. **Left = 105.** Decided: a catalog document (`kind: "catalog"`) plus, at execution time, the option to restore `105/olives_bo.bak` into `drift_left_<id>` on the local instance. The UI label is "Left (105)". The app never dials `10.0.10.105` and never pretends a socket succeeded. Why: the user said this machine has no access, and a `.bak` plus a JSON fixture are real stand-ins. Alternatives rejected: a fake live connection that returns success; blocking the feature until 105 is reachable. Completeness: 10.
10. **Right side.** Decided: the existing Client slot (server, port, user, password, database). On this machine the rehearsal target for capture is `127.0.0.1,1433`, database `Olives_BO`, SQL login, password from the container environment. The generated script is not executed against that database. Why: that is the connection the app already stores. Alternative rejected: a new connection form. Completeness: 10.
11. **Which databases.** Decided: the request carries an explicit database list. The UI default is the one database selected on the right, if the left side has the same name under `casefold`. `olives_BO` is the same database as `Olives_BO`. `drift_left_<id>` is not that name and does not match. A checkbox "All databases on both sides" (default off) sends the intersection of user databases (`database_id > 4`) with the left catalog, compared with `casefold`. Each requested database gets `{db}_schema.sql` and `{db}_udtt.sql`, and all of them go into `unified_full_update.sql`. Databases only on one side are named in the manifest and are not dropped. Why: one click must not script every database on the instance. Alternative rejected: silent intersection of every database. Completeness: 10. Capture opens one connection per database name. Each call copies the side dict and sets `database` to the name being read. It does not reuse the slot's original database for every name. `_sql_connect` uses whatever database is on that copy (`app.py` 403-421).
12. **Direction.** Decided: left is the source of truth, right is the target. The script changes the right database toward the left. Right-only tables and right-only procedures stay. Why: the old tool's DB1-to-DB2 direction, and the current product rule that 105 is not the write target. Alternative rejected: also emit `DROP` for everything that exists only on the right. Completeness: 10 for the stated compare.
13. **Table types.** Decided: `DROP` + `CREATE` in the udtt file and in the unified file, guarded by `TYPE_ID`, and the same file recreates the modules it dropped immediately after `CREATE TYPE` (decision 42). Dependents that the filter excludes cause a skip, not a drop. `scriptgen.assemble` stays manual-review for modified table types. Why: the user asked for drop-and-create, and the existing apply path is additive on purpose (`scriptgen.py` 173-182). Alternative rejected: teach `assemble` to drop types. Completeness: 10.
14. **Dependency algorithm.** Decided: the phase list above, Kahn topo for views and functions together, procedures in name order except those already emitted in phase B, cycles of views or functions moved to the appendix. Why: procedures on SQL Server allow deferred name resolution. Views and functions do not. Alternative rejected: stub `CREATE` plus `ALTER` for every module. Completeness: 10.
15. **Contains / Starts with.** Decided: both operators exclude. `contains` is a case-insensitive substring of the bare name. `starts_with` is a case-insensitive prefix. Several rules combine with OR. Empty tokens match nothing. Match uses `str.casefold`, not `fnmatch`. Do not anchor tokens. Why: the user said the button excludes, and `Olives_BO` collation is `CP1256_CI_AS`. Alternatives rejected: include-filter; case-sensitive match; AND across tokens; word-boundary anchors. Completeness: 10.
16. **Where the defaults live.** Decided: `drift/proc_filter.py` tuples, returned by `GET /api/procedure_filter/defaults`. The dialog renders that payload when it opens. The dialog does not keep a second copy of the words in JavaScript or in `templates/index.html`. `exclude-from-drift.txt` is not seeded into the dialog and is not appended. Why: one list, visible, and the user forbade extra tokens. Alternative rejected: append the new tokens to `exclude-from-drift.txt`. Completeness: 10.
17. **What the filter affects.** Decided: Full Update procedure and function emission, the decision to skip a `DROP TYPE`, and the preview inside the dialog. The findings search box stays an include filter (`app.js` line 951). The Compare button keeps `exclude-from-drift.txt`. Why: mixing them would change today's compare results. Completeness: 10 for the new button.
18. **Token blast radius.** Decided: implement the tokens as written. `sp` excludes `Spartan_SAP_Integ` and `SpecialReport`. `integ` excludes the 397 procedures it substrings. Documented, tested, not "fixed". Completeness: 10.
19. **Trimmer acceptance.** Amended 2026-10-28 by decision 52 (A13). Decided: output is one or more batches separated by a `GO` line. Detect `CREATE`, `ALTER`, and `CREATE OR ALTER` only outside strings and comments, using `statements._mask_literals_and_comments`, the same mask as the `GO` split. A module keeps its kind and its parameter text. A function or trigger keeps the shape the source had, including an inline `RETURNS TABLE AS RETURN` and a `CREATE VIEW ... AS SELECT`. `SET ANSI_NULLS` and `SET QUOTED_IDENTIFIER` batches immediately before the module are kept. A `USE` batch stays a real `USE` batch. It is not commented out. A batch that is not a module is returned as the kept statements, with no synthetic `CREATE PROCEDURE [dbo].[Unknown]`. The loose-SQL probe declares `@ClientActive int` so a batch that mentions that variable can be scoped; the emitted text is not the probe. If the kept loose statements still reference `@ClientActive` and do not declare it, prepend `DECLARE @ClientActive int = <id>;` so the batch does not fail with error 137. Invalid `client_active_id` on a module returns `ok: false` and null `trimmed_sql` (HTTP 400). A module whose `resolve_scope` fails for any other reason (`blocks.py` 512, 660, 668) returns `ok: true`, `trimmed_sql` equal to that original batch, and a `reason` string. `trimmed_sql` in JSON uses `\n`. Why: `trimmer.py` lines 131-138 currently wrap everything. Alternative rejected: commenting out `USE`, or one failure rule for every scope error. Completeness: 10 for parse.
20. **Client active.** Decided: the id is `dbo.ClientsActive.ClientID`. The compile probe uses `dbo.OT_SendSalesmanData` and client id `62`. `122` and `124` are acceptable alternates. `207` is not a valid probe for that procedure. `CompanyID` is not the parameter. Why: measured on the live database. Completeness: 10 for the probe.
21. **File bytes.** Amended 2026-10-28 by decision 51 (A12). Decided: `write_sql_file` writes bytes: `EF BB BF` plus UTF-8, newlines normalized to CRLF, on Linux and on Windows. It calls `Path.write_bytes`. It does not open the file in text mode. On Windows, text mode turns an already-CRLF string into CR CR LF. Why: SSMS reads a BOM as Unicode, and a blank line between every line breaks batches. Alternative rejected: `Path.write_text` or LF because the developer machine is Linux. Completeness: 10. T8 is a byte test and runs on Linux.
22. **Execution of the script.** Decided: the application generates and downloads only. T10's order proof is a separate required check against `drift_right_<id>` only, then `DROP DATABASE`. Why: a 1664-procedure script against the online `Olives_BO` would mutate a real database. Alternative rejected: an Apply button in this same change. Completeness: 10 for safety of the requested generator.
23. **sqlpackage as the generator.** Decided: do not use `DeployReport` or `Script` for Full Update. Why: sqlpackage cannot read the JSON stand-in, and `DropObjectsNotInSource=true` would drop right-only objects. Completeness: 10.
24. **Connection helper.** Decided: live capture uses `_sql_connect` (`app.py` 403-421) on a copy of the side whose `database` is the database being read. It does not call `livescan.connect` for a non-default port. Windows-auth live logins stay unsupported. Scratch Windows auth stays on `scratch_odbc`, used only when restoring a `.bak`. Completeness: 10 for SQL logins.
25. **Tests that need SQL.** Amended 2026-10-28 by decision 50 (A11). Decided: unit tests use the fixture and never need SQL. `tests/test_trimmer_olives_compile.py` runs only when `RUN_LIVE_DB=1` and the container is reachable. It reads `OBJECT_DEFINITION` through `pymssql` (Unicode), not through `sqlcmd`'s default code page. `sqlcmd -f 65001` is only for the `PARSEONLY` file, written as UTF-8 without relying on a BOM, against `Olives_BO`. The test asserts the body is longer than 800000 characters and contains an Arabic-block character (U+0600–U+06FF). Host `sqlcmd` is absent and is not used. If SQL is down, that test skips and the branch is not called validated until it has passed once. T10's order proof is required before push and is execution on `drift_right_<id>`, not `PARSEONLY`. Completeness: 10. A skip is not a pass.

### Outside voice (accepted)

Codex is not installed. A Claude subagent read the plan and listed holes. Each one below is accepted. Where a later devil's-advocate amendment replaces a sentence, the later decision wins. The task bodies follow the later decision.

26. **Unchanged module on a changed table type.** Decided: if phase B drops a type, every non-excluded referencer is dropped and then `CREATE OR ALTER`ed from the left text in that same file, immediately after `CREATE TYPE`, even when the module text is identical on both sides. A filter-excluded or schema-bound referencer skips the type instead. Why: otherwise `DROP TYPE` either fails with 3732 or deletes the procedure until a later phase. Completeness: 10. Amended by decision 42 so this recreate is not delayed until the procedure phase.
27. **Table-type equality.** Amended 2026-10-28 by decision 44 (A5). Decided: both sides render through one function in `drift/full_update.py`. Fields: name, type, max_length, precision, scale, nullability, key ordinal, `is_memory_optimized`. A table type has at most one `PRIMARY KEY` constraint, covering every key column in key order. Do not append ` PRIMARY KEY` to each column (`inspect_objects.py` 574). A type with no key emits no `PRIMARY KEY`. Equality is that rendered string. Do not call `get_table_type_definitions` to produce the script. Why: `CustomersPromotionsGroupsLink_Type` and `Meatland_Integration_PriceLists` have 3-column keys, and 108 of 119 types have no key. Completeness: 10.
28. **Column adds.** Amended 2026-10-28 by decision 48 (A9). Decided: a column record is name, type name, max_length, precision, scale, nullable, identity, computed definition, and the default expression when one exists. Rendering uses `inspect_objects._rendered_type_ext` (`nvarchar(20)` from max_length 40). `ADD` of a nullable column is emitted. `ADD` of `NOT NULL` with a default is one `ALTER TABLE ADD ... NOT NULL CONSTRAINT ... DEFAULT ...` statement. `ADD` of `NOT NULL` without a default, and any computed or identity add on an existing table, goes to the manual appendix and is not executed. Identity is part of `CREATE TABLE` for a new table. Why: bare `ADD col int NOT NULL` fails on a table that has rows (4901), and `nvarchar` without a length, or `nvarchar(40)` from the byte length, is not the captured type. Completeness: 10.
29. **Indexes, checks, defaults, FKs, sequences.** Amended 2026-10-28 by decision 45 (A6). Decided: capture queries them. Do not emit `get_index_definitions` or the `[FLAGS: ...]` suffix as script text. A primary key or unique constraint is `ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY|UNIQUE`. A non-constraint index is `CREATE [UNIQUE] INDEX`, including `INCLUDE` and `WHERE` when captured. Before the script drops an index or unique constraint, it drops foreign keys that reference it, and phase J creates those foreign keys again. A constraint or index is dropped only when the same script contains its recreate text. Otherwise it is named in the appendix and not dropped (`preflight.py` 196-217 already uses that rule for Apply). An index that belongs to a view is emitted immediately after that view. Why: `CREATE PRIMARY KEY CLUSTERED INDEX` does not parse (`inspect_objects.py` 346). Dropping a referenced key while 485 foreign keys still exist fails with 3723. Completeness: 10.
30. **View order.** Decided: the fixture asserts the referenced view's `CREATE` appears before the dependent view's `CREATE`. Why: the opposite order raises 208. Completeness: 10.
31. **Functions and views share one graph.** Decided: one `order_names` call over functions and views together. An edge beats name order, so a function that reads a view is emitted after that view, and a function that calls another function is emitted after that callee even when the caller sorts first (decision 49). A cycle, and any node that still has an edge into a removed cycle, moves to the appendix as a set. Why: separate phases hide a function/view cycle. Completeness: 10.
32. **Cross-database fixture.** Amended 2026-10-28 by decision 43 (A4). Decided: read `referenced_database_name`. `referenced_database_id` is not a column and must not appear in a capture query. A name that casefolds to the database being scripted is not a cross-database edge. The fixture's referenced database sorts after the dependent one: `Aaa` references `Zed`. The unified file contains `USE [Zed]` before `USE [Aaa]`. `USE [DbA]` before `USE [DbB]` is not that test, because `DbA` also sorts first. A view, function, or trigger whose referenced database is not present on the right-hand catalog goes to the appendix and is not emitted as `CREATE OR ALTER`. Procedures stay in the script. Why: the old column does not exist, so live capture throws. `IssueMaster` fails the batch when `Olives_OWMS` is absent. Completeness: 10.
33. **Identity match.** Decided: database names and `schema.name` keys compare with `casefold`. The script prints the left side's spelling. Why: collation `SQL_Latin1_General_CP1256_CI_AS` treats `Olives_BO` and `olives_bo` as the same database. Completeness: 10.
34. **Module rewrite.** Amended 2026-10-28 by decision 46 (A7). Decided: call `scriptgen._as_create_or_alter` after T2 changes it. If the `CREATE` keyword is already followed by `OR ALTER`, leave that single phrase. Do not produce `CREATE OR ALTER OR ALTER`. Do not copy a second rewriter into `full_update.py`. Apply's drop behavior stays unchanged (`test_udtt_modified_lands_manual_review` still passes). Why: `scriptgen.py` 303-304 rewrites the word `CREATE` inside an existing `CREATE OR ALTER`. After the first applied run, `sys.sql_modules.definition` stores `CREATE OR ALTER`, and the next Full Update would emit invalid SQL. The leading-comment case (`scriptgen.py` 241-249) still has to become `CREATE OR ALTER`. Completeness: 10.
35. **Bak left side.** Amended 2026-10-28 by decision 40 (A1). Decided: `kind: "bak"` calls `restore.restore_backup` with physical name `drift_left_<id>` and drops that database in a `finally`. `restore_backup` also returns `database_name` from `RESTORE HEADERONLY.DatabaseName` (today it returns only the date and the engine version, `restore.py` 181). The catalog key, the `USE` name, and the output filename are that logical name. A unit test with a fake header `Olives_BO` and a physical name `drift_left_abc` asserts `USE [Olives_BO]` and asserts the script does not contain `drift_left_`. The 1175 MB file is restored only in T10, for capture, not as the execute target. It does not use `drift_master_<id>`. Completeness: 10.
36. **Job and download.** Amended 2026-10-28 by decision 41 (A2). Decided: do not call `_start_compare_job`. Add `_start_full_update_job` with the same queue shape, `kind` set to `full_update`, and a result of `{run_id, run_dir, meta, files}`. `api_stream` (`app.py` 779-783) emits `{run_id, meta, files}` for that kind and does not read `workspaces`. Add `GET /api/full_update/<run_id>/<filename>` that serves only a file inside that run's `full_update` directory and rejects `..`. The button disables in the click handler and stays disabled until the stream's `result` or `error` event, the same lifetime as `setBusy` / `clearBusy`. It re-enables on POST failure, because no stream exists yet. It does not re-enable when the job id returns. Download links use the new GET route. `renderResults` is the compare path; Full Update does not pass `workspaces` to it. Completeness: 10.
37. **Encrypted modules.** Decided: a NULL `sys.sql_modules.definition` is a manifest warning and a `-- WITH ENCRYPTION` comment, not a scripted body and not a failed job. Same rule as `convert.py` 101-106. Completeness: 10.
38. **Remove a filter row.** Decided: every row in the dialog, including defaults, has a Remove control. Remove affects this run only. Opening the dialog again reloads `default_rules()`. A test removes `alpha` and asserts `Alpha_Foo` is no longer excluded. Completeness: 10.
39. **Cross-model tension.** The review's first draft said the unified file is safe to run alone, and it said view order is optional. The outside voice said both are wrong. Accepted the outside voice. The file is ordered. It is not atomic. Grants are not re-scripted. No item was left as "investigate later".

### Devil's advocate amendments (2026-10-28)

Source: `/media/alaa/data/my apps/Drift-SQL-Tool/docs/plans/2026-10-28-full-update-compare-devil.md`. Verdict: **AMEND THEN SHIP**. The parent accepts A1–A14 in full. These decisions replace the sentences they name. The task bodies are the implementation of these decisions. Rejected alternative for this whole block: another review round (decision 54).

| Id | Replaces | Implemented in |
|---|---|---|
| A1 | Decision 35, data-flow `kind=bak`, T5 bak steps, T10 | T4 writes `catalog_key_for_restore` and the `restore_backup` return field. T5 calls them. T10 asserts the header name. |
| A2 | Decision 36, Task 5 | T5 |
| A3 | Phase B, per-file contract, T4 assertions, T1 drop gate | T1 (`procedure_excluded` is the gate the renderer must call). T4 emits the SQL. T5's dialog shows `default_rules()` and no second copy. |
| A4 | Dependency-order paragraph, decision 32, T4 fixture | T3 (`referenced_database_name`, casefold, `order_databases`). T4 fixture `USE [Zed]` before `USE [Aaa]`, absent-target view in the appendix. |
| A5 | Decision 27, T4 table-type assertion | T4 |
| A6 | Decision 29, phases I and J | T4 |
| A7 | Decision 34 | T2 (`scriptgen._as_create_or_alter` only; Apply drops unchanged) |
| A8 | Phases A and F, unchanged `SELECT *` view | T3 `schema_batch`. T4 re-emits `[t].[Wrap]` after `ALTER TABLE`. |
| A9 | Task 4 column record. Decision 28 stays, plus the default expression | T4 |
| A10 | Fixture function pair | T3 test `dbo.Caller` / `dbo.Zee`. T4 renders that pair. |
| A11 | Task 7 and Task 10 | T7 Unicode read. T10 required execute on `drift_right_<id>` only. |
| A12 | Decision 21, Task 8 | T4 `write_sql_file` bytes. T8 byte test only. |
| A13 | Task 2 steps for scope, mask, and `USE` | T2 |
| A14 | Parallel table, `capture_live_catalog` ownership | T4 owns `capture_live_catalog`. Integration tasks I13, I4, I58. Separate worktrees. |

40. **A1 accepted.** The catalog key, the `USE` name, and the output filename come from `RESTORE HEADERONLY.DatabaseName`. The physical restore name stays `drift_left_<id>` and is dropped in `finally`. `restore_backup` returns `database_name` in addition to `backup_date` and `engine_major_version`. A fake header `Olives_BO` with physical name `drift_left_abc` produces `USE [Olives_BO]` and no `drift_left_` in the script. Dated 2026-10-28. Cited: devil critique A1, `restore.py` 181, decision 35.
41. **A2 accepted.** `_start_full_update_job` sets `kind` to `full_update`. `api_stream` emits `{run_id, meta, files}` for that kind and does not read `workspaces`. The Full Update button disables in the click handler and stays disabled until the stream's result or error event. Each live capture connects with a copy of the side whose `database` field is the database being read. Dated 2026-10-28. Cited: devil critique A2, `app.py` 779-783, `app.py` 403-421, `static/app.js` 56-84 and 606-618.
42. **A3 accepted.** For each changed table type, the same file that contains `DROP TYPE` also contains, immediately after `CREATE TYPE` and before the next phase, `CREATE OR ALTER` of every module that file dropped. `{db}_udtt.sql` included. The unified file does not wait until the procedure phase. An excluded or schema-bound referencer skips that type. The rendered SQL contains no `DROP` of an excluded name. Dated 2026-10-28. Cited: devil critique A3. The filter UI shows `default_rules()` and no other default tokens (decision 16).
43. **A4 accepted.** Read `referenced_database_name`. A name that casefolds to the database being scripted is not a cross-database edge. A view, function, or trigger whose referenced database is not present on the right-hand instance goes to the appendix and is not emitted as `CREATE OR ALTER`. Procedures stay in the script. Assert `USE [Zed]` before `USE [Aaa]` when `Aaa` references `Zed`. Dated 2026-10-28. Cited: devil critique A4.
44. **A5 accepted.** A table type has at most one `PRIMARY KEY` constraint, covering every key column in key order. T4 includes a two-column key and a three-column key (the two live types are three-column; the renderer takes the whole key list) and asserts a single constraint each. A type with no key emits no `PRIMARY KEY`. Dated 2026-10-28. Cited: devil critique A5, `inspect_objects.py` 574.
45. **A6 accepted.** Do not emit `get_index_definitions` or `[FLAGS: ...]`. Primary key and unique constraints are `ALTER TABLE ... ADD CONSTRAINT`. Non-constraint indexes are `CREATE [UNIQUE] INDEX`. Drop referencing foreign keys before dropping the index they use; phase J creates those foreign keys again. T4 has two tables, a primary key, and a foreign key. Dated 2026-10-28. Cited: devil critique A6, `inspect_objects.py` 346.
46. **A7 accepted.** `_as_create_or_alter` leaves an existing `CREATE OR ALTER` as a single phrase. A test whose definition already starts with `CREATE OR ALTER PROCEDURE` must not see `CREATE OR ALTER OR ALTER`. Apply's drop behavior stays unchanged. Dated 2026-10-28. Cited: devil critique A7, `scriptgen.py` 303-304.
47. **A8 accepted.** `CREATE SCHEMA` is its own batch, ended with `GO`, and it runs before any type, table, or module in that schema. A view is emitted even when its text matches the right side if this script adds or alters a column of a table that view references. Schema qualification comes from the catalog (`[t].[Wrap]`, not `dbo`). Dated 2026-10-28. Cited: devil critique A8. 412 views in schema `t` are `SELECT *`.
48. **A9 accepted.** The column record keeps length, precision, scale, identity, computed definition, and the default expression. The T4 assertion contains `nvarchar(20)`. Dated 2026-10-28. Cited: devil critique A9. Decision 28's fields stay; the default expression is added.
49. **A10 accepted.** Fixture functions `dbo.Caller` and `dbo.Zee`, with an edge from `Caller` to `Zee`. `Zee`'s `CREATE` appears before `Caller`'s. `Caller` sorts first by name. The dependency-order test fails if the implementation sorts alphabetically. Dated 2026-10-28. Cited: devil critique A10.
50. **A11 accepted.** Read `OBJECT_DEFINITION` through `pymssql`. `sqlcmd -f 65001` is only for the `PARSEONLY` file, UTF-8, BOM not required. T10 is required before push. Restore `olives_bo.bak` to `drift_left_<id>`, capture it, and assert the catalog key is the header's `DatabaseName`. Prove order by executing a proof copy with `sqlcmd` inside the container against a new `drift_right_<id>` only, then `DROP DATABASE`. Do not execute against `Olives_BO`, `olives_PEEK`, `Olives_POS`, `OSFA_DB`, or `osfa_PEEK`. `SET PARSEONLY` of the multi-batch file is not the order proof. Dated 2026-10-28. Cited: devil critique A11.
51. **A12 accepted.** `write_sql_file` writes bytes. It does not use text mode. T8 stays a byte test on Linux. Dated 2026-10-28. Cited: devil critique A12.
52. **A13 accepted.** A module whose `resolve_scope` fails for any reason other than an invalid `client_active_id` is returned unchanged, with `ok: true` and the original batch. Invalid id on a module stays `ok: false`. Module detection is mask-aware. A `USE` batch stays a real `USE` batch. Tests cover an inline `RETURNS TABLE` function, a `CREATE VIEW ... AS SELECT`, and a string that contains the words `CREATE PROCEDURE`. The trimmer still produces a ready-to-execute query and does not wrap arbitrary SQL as `CREATE PROCEDURE [dbo].[Unknown]`. Dated 2026-10-28. Cited: devil critique A13, `blocks.py` 512, 660, 668, `trimmer.py` 131-138.
53. **A14 accepted.** `capture_live_catalog` is written in T4, in `drift/full_update.py`, before T5 and T8 start. T5 does not edit that module. T1, T2, and T3 run in separate git worktrees and merge in task I13 before T4. T7 may run beside T4 and may edit only `tests/test_trimmer_olives_compile.py`. T8 may run beside T5 and may edit only `tests/test_sql_file_bytes.py`. T5's full-suite run starts after T8's test file is committed (task I58). Dated 2026-10-28. Cited: devil critique A14.
54. **No further review round.** Decided: accept A1–A14 in full and start implementation. Dated 2026-10-28. Cited: devil critique, verdict AMEND THEN SHIP, and the parent's acceptance. Rejected alternative: another review round. CEO review, design review, and a second devil's-advocate pass are not gates for T9–T10.

## Step 0 scope challenge

Existing code already diffs two databases and writes an additive script. Full Update needs drops of table types, a unified order, a recorded left side, and a visible exclusion list. Those four behaviors are not in `assemble`. A new renderer that consumes catalogs is the small version that still produces every file the user named.

Search check: SQL Server has no built-in "compare two catalogs and emit ordered DDL" in T-SQL. sqlpackage is rejected in decision 23. No new package is added.

`TODOS.md` does not exist in the repo. Nothing deferred there blocks this work.

Distribution: no new binary type. `build-windows.bat` and `drift-tool.spec` already build the exe. Importing the new modules from `app.py` is enough for PyInstaller to collect them. The 1 GB `.bak` is not a package asset.

## Architecture review

Findings below are decided in the log above.

1. **[P1] `drift/livescan.py:29`** `SCAN_ONLY = True`. Full Update is `drift/full_update.py`. Do not emit SQL from `livescan`.
2. **[P1] `drift/scriptgen.py:178-182`** modified table types stay manual review on the Apply path.
3. **[P1] `templates/index.html` and `app.py:630`** the Master slot is not a connection to 105. Left is `kind: "catalog"` or a bak restored as `drift_left_<id>` and keyed by the header name.
4. **[P1] `drift/dependencies.py:31-56`** `get_callers` does not return a script order. Full Update captures `referenced_database_name` once per database, then orders in memory.
5. **[P2] two exclusion mechanisms.** `compare.py:102` `fnmatch` stays. The new dialog uses `procedure_excluded`.
6. **[P1] same-file recreate.** The table-type file recreates every module it drops, immediately after `CREATE TYPE`. Running it alone does not leave those procedures missing. Grants are still not scripted. Decision 42.

Production failure for the new path: the right server is offline. `_sql_connect` raises, the job logs `FAILED:`, the stream emits `error`, the button's `clearBusy` runs, no file is written.

Task T4 puts the phase diagram in the module docstring of `drift/full_update.py` and updates it if the phases change.

## Code quality review

1. **[P1] `drift/trimmer.py:131-138`.** Stop wrapping non-modules as `CREATE PROCEDURE [dbo].[Unknown]`. Decision 19 and 52.
2. **[P1] `drift/trimmer.py:98-106`.** Keep `SET ANSI_NULLS`, `SET QUOTED_IDENTIFIER`, and real `USE` batches. Mask `GO` and module keywords. Decision 19 and 52.
3. **[P2] `drift/compare.py:102`.** The new filter must not call `fnmatch`. Do not rewrite `exclude-from-drift.txt`.
4. **[P2] DRY.** The token list lives only in `drift/proc_filter.py`. The dialog loads it. Decision 16.
5. **[P3]** `full_update.py` module docstring contains the phase diagram. T4 owns it.

## Test review

Framework: unittest, discovered as `python3.13 -m unittest discover -s tests`. `conftest.py` puts the repo root on `sys.path`. New tests go in `tests/`, not in the older `drift/test_*.py` copies.

```
CODE PATHS                                            USER FLOWS
[+] drift/proc_filter.py                              [+] Procedures filter dialog
  ├── default_rules() exact tuples                      ├── Open dialog, every default
  └── procedure_excluded()                                token is visible, nothing else
      ├── contains, casefold, OR, not anchored          ├── Contains / Starts with add a row
      ├── "sp" matches Spartan_ and SpecialReport       └── double-click does not start a
      └── excluded name is the DROP gate                    second job (button stays disabled
[+] drift/trimmer.py                                        until the stream ends)
  ├── GO split (mask-aware)
  ├── module detect (mask-aware)
  ├── USE stays USE
  ├── inline TVF and CREATE VIEW stay themselves
  ├── non-id scope failure returns the original batch
  ├── invalid id on a module is ok false
  └── loose SQL is not CREATE PROCEDURE [dbo].[Unknown]
[+] drift/scriptgen.py
  └── CREATE OR ALTER is not doubled
[+] drift/full_update.py
  ├── header DatabaseName, not drift_left_
  ├── one PRIMARY KEY constraint; no-key type has none
  ├── ADD CONSTRAINT; FK drop before that key
  ├── USE [Zed] before USE [Aaa]
  ├── Zee before Caller
  ├── CREATE SCHEMA [t] then GO, alone
  ├── SELECT * view re-emitted after ALTER, schema [t]
  ├── nvarchar(20)
  ├── absent-target view in the appendix; procedure kept
  └── write_sql_file bytes, BOM + CRLF, no CR CR LF
[+] app.py
  ├── kind full_update stream has files, no workspaces
  └── one connect per database name
```

The existing suite already covers `blocks.resolve_scope`, hoist, and adversarial trimmer cases (`tests/test_trimmer_adversarial.py`, `tests/test_blocks.py`). Those stay. Regression rule: T2 changes `trimmer.trim_procedure`. Existing tests that expect the `BEGIN`/`END` wrapper around a real procedure must still pass. Any test that asserted the `Unknown` wrapper is updated in T2. `python3.13 drift/test_scriptgen.py` still prints `32/32 passed`, including `test_udtt_modified_lands_manual_review`. `tests/test_livescan.py` still asserts there is no script function on `livescan`. Unittest discover already fails on 10 legacy flat-import modules (`test_scriptgen` is one of them). Do not "fix" that import in this branch. New tests are `unittest.TestCase` classes in modules discover can import.

E2E marks are the browser `/qa` phase (T10), not a second automation stack. No LLM prompt changes.

## Performance review

1. **[P1] N+1 risk.** One module query, one column query, one table-type query, one dependency query, one index query, one foreign-key query, per database. Do not call `get_table_type_definitions` once per object.
2. **[P1] UI freeze.** `_start_full_update_job` uses a worker thread. The button stays disabled until the stream ends so a second click cannot start a second job.
3. **[P2] memory.** Holding every definition is required to order the unified file. The job logs the total character count. It does not shell out to sqlpackage.

## Failure modes

| Path | Failure | Test | User-visible result |
|---|---|---|---|
| Live right side down | connect raises | API test with a stub | Job log `FAILED:`, stream `error`, button re-enables, no files |
| Catalog path missing | validation | API test | HTTP 400, message names the path |
| Bak keyed by the physical name | script says `USE [drift_left_...]` for a database `finally` already dropped | fake header test | `USE [Olives_BO]`, no `drift_left_` in the file |
| Stream assumes compare shape | `KeyError` on `workspaces` after a good generate | stream test with `kind=full_update` | download links from `files` |
| Excluded proc references a changed type | 3732 if we dropped the type, or the proc disappears if we drop it | fixture test | `PRINT`/`-- SKIP`, no `DROP TYPE`, no `DROP` of that name |
| Udtt file run alone | procedures missing if recreate waits for the schema file | fixture test | `CREATE OR ALTER` of those modules is after `CREATE TYPE` in the udtt file |
| View cycle | 208 if both views are created | fixture test | both views only in the appendix |
| Absent database on a view | `CREATE OR ALTER` fails, sqlcmd stops the file | fixture `IssueMaster` | view only in the appendix |
| Alphabetical database order | `Aaa` emitted before `Zed` | fixture test | `USE [Zed]` first |
| Alphabetical function order | `Caller` emitted before `Zee` | T3 and T4 | `Zee` first |
| Multi-column table-type key | several `PRIMARY KEY` clauses, `CREATE TYPE` fails | two-column and three-column tests | one constraint |
| `get_index_definitions` text | `CREATE PRIMARY KEY ... INDEX` does not parse | fixture test | `ADD CONSTRAINT` |
| FK still present | 3723 on drop of the key | fixture test | `DROP CONSTRAINT` of the FK before the key change |
| Second Full Update | `CREATE OR ALTER OR ALTER` | scriptgen test | one `CREATE OR ALTER` |
| `SELECT *` view unchanged | application schema `t` never sees the new column | fixture test | view emitted after `ALTER TABLE` |
| `CREATE SCHEMA` shares a batch | error 111 | `schema_batch` test | `CREATE SCHEMA [t]` then `GO` alone |
| `nvarchar` byte length | `nvarchar(40)` or bare `nvarchar` | fixture test | `nvarchar(20)` |
| `NOT NULL` add without default | error 4901 | fixture test | appendix only |
| Trimmer scope failure other than bad id | HTTP 400 and an empty box | trimmer tests | original batch, `ok: true` |
| String contains `CREATE PROCEDURE` | batch rewritten into a module | trimmer test | the original statement, no `Unknown` |
| `USE` commented out | the rest runs in the connection's current database | trimmer test | a real `USE` batch |
| Loose SQL uses `@ClientActive` | error 137 | trimmer test | `DECLARE @ClientActive` in the emitted batch, no procedure wrapper |
| Double-click Full Update | two jobs | button stays in `setBusy` until stream result or error; T10 checks the click | one job |
| Password in the catalog | leak on disk | test reads the output files | absent |
| Operator points the script at 105 by hand | the app cannot stop an external SSMS session | header comment | first lines name the right-hand server |
| Order proof uses `PARSEONLY` or `drift_left_*` | a bad order still looks green | T10 executes on empty `drift_right_<id>` | failure fails T10 |

No failure mode is silent. Decision 22: the app still does not execute the files. T10 is the rehearsal, and it is required.

## NOT in scope

- Executing Full Update SQL from the application, including against the online `Olives_BO`.
- Changing `scriptgen.assemble` drop behavior, Apply, data copy, or web deploy. T2 may change `_as_create_or_alter` only so an existing `CREATE OR ALTER` is left alone.
- Adding tokens, anchoring tokens, editing `exclude-from-drift.txt`, or making `fnmatch` case-insensitive for the old Compare path.
- Users, roles, permissions, `GRANT`, extended properties, CLR assemblies, Service Broker, and row data.
- Dropping right-only tables or right-only procedures as a general rule.
- A live TCP session to `10.0.10.105`.
- Windows-auth for arbitrary live servers.
- Bundling `olives_bo.bak` or SA passwords into git or the exe.
- Pushing `main`. Pushing the feature branch is T10, after `/qa`.
- Creating `TODOS.md`, `CLAUDE.md`, or a gstack design doc in the repo.
- Another review round before implementation. Decision 54.
- Upgrading gstack during implementation.

## Risks

- `SET PARSEONLY` does not execute earlier batches. A correctly ordered multi-batch file can still fail `PARSEONLY` on an empty database, and a badly ordered file can pass `PARSEONLY` against `drift_left_<id>` because those objects already exist. T10 therefore executes the proof copy on a new `drift_right_<id>`.
- Restoring the 1175 MB bak during T10 needs a temporary database and several minutes. Disk space is sufficient. Restore only to `drift_left_<id>`, capture, assert the header name, drop it. Do not execute the generated `USE [Olives_BO]` script.
- 568 procedures and 31 functions disappear from the script because of the token list. That is the requested filter. 53 table types stay as they are because an excluded procedure references them. The dialog exists so the operator can see the list before generating.
- `api` and `sp` are short. Tests lock the current meaning so a later edit does not anchor them.

## Parallel work and dependency graph

File ownership is exclusive. Lane agents commit on their own branches in their own worktrees. They do not commit on `feature/full-update-compare` directly, and they do not share the main working tree. The main workspace stays on `feature/full-update-compare` for T9 and for the integration tasks.

Worktree paths are absolute and are not inside `/media/alaa/data/my apps/Drift-SQL-Tool`. Create them only when the task says to. This planning revision does not create them.

```
T9  main workspace, read-only baseline
 |
 +-- T1 /tmp/drift-fu-t1     feature/full-update-t1
 +-- T2 /tmp/drift-fu-t2     feature/full-update-t2
 +-- T3 /tmp/drift-fu-t3     feature/full-update-t3
        (T1, T2, T3 in parallel, only after T9 is green)
 |
 I13 merge T1+T2+T3 into feature/full-update-compare (main workspace)
 |
 +-- T4 /tmp/drift-fu-t4     feature/full-update-t4   (after I13)
 +-- T7 /tmp/drift-fu-t7     feature/full-update-t7   (after T2's commit;
        only tests/test_trimmer_olives_compile.py; may run beside T4)
 |
 I4  merge T4 into feature/full-update-compare
     merge T7 too if it is green; otherwise T7 merges at I58
 |
 +-- T5 /tmp/drift-fu-t5     feature/full-update-t5   (after I4)
 +-- T8 /tmp/drift-fu-t8     feature/full-update-t8   (after I4;
        only tests/test_sql_file_bytes.py; beside T5, no shared files)
 |
 I58 merge T5+T8 and T7 if it is not already merged
     then python3.13 -m unittest discover -s tests -q
     T5 must not run that full discover before T8's file is on the branch
 |
 T10 /qa, required drift_right_* order proof, push feature branch only
```

| Task | Depends on | Worktree | Files | Verification | Amendments |
|---|---|---|---|---|---|
| T9 | — | `/media/alaa/data/my apps/Drift-SQL-Tool` (main workspace, no new worktree) | none | `python3.13 -m unittest discover -s tests -q` | — |
| T1 | T9 | `/tmp/drift-fu-t1` branch `feature/full-update-t1` | `drift/proc_filter.py`, `tests/test_proc_filter.py` | `python3.13 -m unittest tests.test_proc_filter -v` | A3 (never-drop gate; `default_rules()` is the list the filter UI shows) |
| T2 | T9 | `/tmp/drift-fu-t2` branch `feature/full-update-t2` | `drift/trimmer.py`, `drift/scriptgen.py` (`_as_create_or_alter` only), `tests/test_trimmer.py`, `tests/test_create_or_alter.py` | `python3.13 -m unittest tests.test_trimmer tests.test_trimmer_adversarial tests.test_blocks tests.test_create_or_alter -v` then `python3.13 drift/test_scriptgen.py` | A7, A13 |
| T3 | T9 | `/tmp/drift-fu-t3` branch `feature/full-update-t3` | `drift/full_update.py` (order functions only), `tests/test_dependency_order.py` | `python3.13 -m unittest tests.test_dependency_order -v` | A4, A8 (`schema_batch`), A10 |
| I13 | T1, T2, T3 | main workspace, stay on `feature/full-update-compare` | git merge only | the three verification commands above, from the main workspace after merge | A14 |
| T4 | I13 | `/tmp/drift-fu-t4` branch `feature/full-update-t4` | `drift/full_update.py`, `drift/restore.py` (return `database_name` only), `tests/fixtures/left_105_catalog.json`, `tests/fixtures/right_local_catalog.json`, `tests/test_full_update.py` | `python3.13 -m unittest tests.test_full_update tests.test_livescan tests.test_create_or_alter -v` then `python3.13 drift/test_scriptgen.py` | A1, A3, A4, A5, A6, A8, A9, A10 (rendered pair), A12 (`write_sql_file`), `capture_live_catalog` |
| T7 | T2 | `/tmp/drift-fu-t7` branch `feature/full-update-t7` | `tests/test_trimmer_olives_compile.py` only | `RUN_LIVE_DB=1 python3.13 -m unittest tests.test_trimmer_olives_compile -v` | A11 (Unicode read, `PARSEONLY`) |
| I4 | T4; T7 if green | main workspace | git merge only | T4's verification command | A14 |
| T5 | I4 | `/tmp/drift-fu-t5` branch `feature/full-update-t5` | `app.py`, `templates/index.html`, `static/app.js`, `static/style.css`, `tests/test_full_update_api.py` | `python3.13 -m unittest tests.test_full_update_api tests.test_compare_subtabs -v` (not the full discover) | A2, A1 (route uses the header name), filter UI shows `default_rules()` |
| T8 | I4 | `/tmp/drift-fu-t8` branch `feature/full-update-t8` | `tests/test_sql_file_bytes.py` only | `python3.13 -m unittest tests.test_sql_file_bytes -v` | A12 |
| I58 | T5, T8, and T7 | main workspace | git merge only | `python3.13 -m unittest discover -s tests -q` (only the T9 legacy 10 import errors remain) and `python3.13 drift/test_scriptgen.py` | A14 (full suite after T8 is committed) |
| T10 | I58 and a green T7 (a skip is not a pass) | main workspace | `tests/test_full_update_rehearsal.py` if the proof is automated; no other product module | `/qa` notes, rehearsal commands below, `git status` on `feature/full-update-compare` | A1, A11 |

Conflict rules:

- T5 does not edit `drift/full_update.py`, `drift/restore.py`, or `tests/test_sql_file_bytes.py`.
- T8 does not edit `drift/full_update.py`. `write_sql_file` is finished in T4. If T8 fails, stop. Do not patch `full_update.py` from the T8 worktree while T5 is open. Fix it on the T4 branch and re-merge I4 before continuing T8.
- T7 does not edit `drift/trimmer.py`. It only adds its test file.
- Do not let two agents edit `drift/full_update.py` at once. T3 creates the order functions. T4 extends the file only after I13.
- T5's `python3.13 -m unittest discover -s tests -q` runs in I58, after T8's test file is on `feature/full-update-compare`. During T5's own lane, run only the T5 verification command.

How to open a lane, from the main workspace, without switching it off `feature/full-update-compare`:

```bash
git worktree add -b feature/full-update-t1 /tmp/drift-fu-t1 feature/full-update-compare
```

Use the same form for `t2`, `t3`, and, after I13, for `t4`. T7's start point is the T2 branch, and it can be created as soon as T2 has committed:

```bash
git worktree add -b feature/full-update-t7 /tmp/drift-fu-t7 feature/full-update-t2
```

T5 and T8 start points are `feature/full-update-compare` after I4. Remove a worktree only after its branch is merged: `git worktree remove /tmp/drift-fu-t1`. Do not remove the main workspace.

---

## Tasks

An implementer follows these task bodies. They already include A1–A14. Do not restore the pre-amendment behavior (physical name as `USE`, `workspaces` on the Full Update stream, recreate delayed until the procedure phase, `referenced_database_id`, one `PRIMARY KEY` per column, `CREATE PRIMARY KEY ... INDEX`, `CREATE OR ALTER OR ALTER`, `CREATE SCHEMA` sharing a batch, a shrunk column record, alphabetical fixture order, optional T10, text-mode writes, `USE` commented out, or one shared checkout for T1–T3).

### Task 9: Baseline the suite before edits

**Files:** none (read-only).

**Interfaces:** none.

**Worktree:** `/media/alaa/data/my apps/Drift-SQL-Tool`. Do not create a worktree. Do not switch branches.

- [ ] **Step 1: Run the existing suite**

Run: `python3.13 -m unittest discover -s tests -q`

Expected on this branch before any product edit: `Ran 199 tests` and `FAILED (errors=10, skipped=2)`. The 10 errors are import failures in legacy modules that use a flat import (`import scriptgen`, `import webdeploy`, and the same pattern). They are not this feature. The module names are exactly:

`test_ai`, `test_ai_common`, `test_ai_merge`, `test_classify`, `test_diff_render`, `test_ledger`, `test_metrics`, `test_profiles`, `test_scriptgen`, `test_webdeploy`.

Record that list. Do not edit those files to force discover to exit 0. If a different module errors, or the error count is not 10, stop. Do not start T1, T2, or T3. Do not edit product code in this task.

The Apply-script self-check that unittest does not collect:

Run: `python3.13 drift/test_scriptgen.py`

Expected: `32/32 passed`, including `test_udtt_modified_lands_manual_review` and `test_create_or_alter_survives_a_leading_comment`.

### Task 1: Procedure exclusion list

**Files:**
- Create: `drift/proc_filter.py`
- Test: `tests/test_proc_filter.py`

**Interfaces:**
- Consumes: nothing
- Produces: `default_rules() -> list[dict]`, `procedure_excluded(bare_name: str, rules: list[dict] | None = None) -> bool`. Each rule is `{"op": "contains"|"starts_with", "value": str}`. `rules=None` uses `default_rules()`. T4 calls `procedure_excluded` before every `DROP` of a procedure or function. If it returns true, T4 does not emit that `DROP` and does not `DROP TYPE` for a type that referencer uses. T5 renders `default_rules()` in the dialog and does not copy the tuples into JavaScript.

**Worktree:** `/tmp/drift-fu-t1` on `feature/full-update-t1`, created only after T9 is green.

- [ ] **Step 1: Open the worktree**

From the main workspace:

```bash
git worktree add -b feature/full-update-t1 /tmp/drift-fu-t1 feature/full-update-compare
```

Work in `/tmp/drift-fu-t1`. Do not commit from the main workspace.

- [ ] **Step 2: Write the failing test**

```python
import unittest
from drift.proc_filter import default_rules, procedure_excluded

CONTAINS = (
    "alpha", "sap", "bonanza", "integ", "mms", "jawad", "hammoudeh",
    "technical", "niroukh", "api", "medical", "poa", "tax", "asset",
    "thuraya", "cmms", "memo",
)
STARTS = ("sp", "oms", "sms", "owms")

class ProcFilterTests(unittest.TestCase):
    def test_defaults_are_exactly_the_list(self):
        rules = default_rules()
        self.assertEqual([r["value"] for r in rules if r["op"] == "contains"], list(CONTAINS))
        self.assertEqual([r["value"] for r in rules if r["op"] == "starts_with"], list(STARTS))
        self.assertEqual(len(rules), len(CONTAINS) + len(STARTS))
        self.assertEqual(rules[0], {"op": "contains", "value": "alpha"})
        self.assertEqual(rules[-1], {"op": "starts_with", "value": "owms"})

    def test_contains_is_casefold_substring_or(self):
        self.assertTrue(procedure_excluded("OSFA_SP_Api"))
        self.assertTrue(procedure_excluded("Spartan_SAP_Integ"))
        self.assertTrue(procedure_excluded("ABS_Integ_GetDataFromAPI"))
        self.assertTrue(procedure_excluded("Alpha_Foo"))
        self.assertTrue(procedure_excluded("dbo.Alpha_Foo"))
        self.assertFalse(procedure_excluded("OT_SendSalesmanData"))

    def test_starts_with_is_prefix_not_anchored(self):
        self.assertTrue(procedure_excluded("sp_helptext"))
        self.assertTrue(procedure_excluded("SpecialReport"))
        self.assertTrue(procedure_excluded("Spartan_SAP_Integ"))
        self.assertFalse(procedure_excluded("GetSpecial"))
        self.assertTrue(procedure_excluded("owms_sync"))
        self.assertFalse(procedure_excluded("xowms"))

    def test_empty_token_matches_nothing(self):
        self.assertFalse(procedure_excluded("Anything", [{"op": "contains", "value": ""}]))
        self.assertFalse(procedure_excluded("Anything", [{"op": "starts_with", "value": "  "}]))
        self.assertFalse(procedure_excluded("Anything", [{"op": "regex", "value": "Any"}]))

    def test_excluded_name_is_the_drop_gate(self):
        self.assertTrue(procedure_excluded("alpha_hide"))
        self.assertFalse(procedure_excluded("UsesTvp"))
```

- [ ] **Step 3: Run** `python3.13 -m unittest tests.test_proc_filter -v`

Expected: FAIL, import error.

- [ ] **Step 4: Implement** `drift/proc_filter.py` with exactly the tuples above. `procedure_excluded` casefolds, strips one layer of surrounding `[]`, and if the caller passed `schema.name` uses the segment after the last `.`. OR across rules. A blank value matches nothing. An unknown `op` does not match. Do not add tokens. Do not anchor. The module docstring says: callers that emit `DROP` of a procedure or function must skip the name when this returns true, and must skip `DROP TYPE` instead of dropping that referencer; the Procedures filter dialog renders `default_rules()` and must not copy these tuples.

- [ ] **Step 5: Re-run.** Expected: PASS, 5 tests.

- [ ] **Step 6: Commit** on `feature/full-update-t1`: `feat: add procedure exclusion matcher`.

### Task 3: Dependency order

**Files:**
- Create: `drift/full_update.py` (order functions only in this task)
- Test: `tests/test_dependency_order.py`

**Interfaces:**
- Consumes: nothing from T1 yet
- Produces:
  - `order_names(names: list[str], edges: list[tuple[str, str]]) -> tuple[list[str], list[str]]`. `edges` are `(dependent, referenced)`. The referenced name is emitted first. Returns `(executable_order, held_back)`. Cycles are removed. Any remaining name that still edges into a held-back name is held back too, repeating until the executable list has no edge into the held-back list. Ties keep the input order of `names`.
  - `same_database(referenced_database_name: str | None, database_name: str) -> bool`. `None` or `""` is the same database. Otherwise compare with `casefold`. `olives_BO` and `Olives_BO` are the same database. `Olives_OWMS` and `Olives_BO` are not.
  - `order_databases(names: list[str], edges: list[tuple[str, str]]) -> tuple[list[str], list[str]]`. `edges` are `(dependent_database, referenced_database)`. Returns `(order, warnings)`. The referenced database is first. A cycle falls back to casefold name order and one warning string. No edges: keep the input order of `names`.
  - `schema_batch(schema_name: str) -> str`. Returns exactly `CREATE SCHEMA [schema_name]\nGO\n` and no other statement. `dbo` is not a caller's job to pass; T4 skips `dbo`.

**Worktree:** `/tmp/drift-fu-t3` on `feature/full-update-t3`, after T9.

- [ ] **Step 1: Open the worktree**

```bash
git worktree add -b feature/full-update-t3 /tmp/drift-fu-t3 feature/full-update-compare
```

- [ ] **Step 2: Failing tests** in `tests/test_dependency_order.py`

```python
from drift.full_update import order_names, order_databases, same_database, schema_batch

import unittest

class DependencyOrderTests(unittest.TestCase):
    def test_referenced_object_first(self):
        order, held = order_names(["V", "T"], [("V", "T")])
        assert held == [] and order.index("T") < order.index("V")

    def test_cycle_is_removed_from_executable_order(self):
        order, held = order_names(["A", "B", "C"], [("A", "B"), ("B", "A")])
        assert set(held) == {"A", "B"} and order == ["C"]

    def test_dependent_of_a_cycle_is_held_back_too(self):
        order, held = order_names(["A", "B", "D"], [("A", "B"), ("B", "A"), ("D", "A")])
        assert set(held) == {"A", "B", "D"} and order == []

    def test_callee_before_caller_even_when_caller_sorts_first(self):
        order, held = order_names(["dbo.Caller", "dbo.Zee"], [("dbo.Caller", "dbo.Zee")])
        assert held == []
        assert order.index("dbo.Zee") < order.index("dbo.Caller")

    def test_order_is_not_alphabetical_or_reversed(self):
        order, held = order_names(["A", "M", "Z"], [("A", "M"), ("Z", "A")])
        assert held == []
        assert order.index("M") < order.index("A") < order.index("Z")

    def test_cross_database_order_is_not_alphabetical(self):
        order, warnings = order_databases(["Aaa", "Zed"], [("Aaa", "Zed")])
        assert warnings == []
        assert order.index("Zed") < order.index("Aaa")

    def test_same_database_casefold(self):
        assert same_database("olives_BO", "Olives_BO") is True
        assert same_database("Aaa", "aaa") is True
        assert same_database(None, "Olives_BO") is True
        assert same_database("", "Olives_BO") is True
        assert same_database("Olives_OWMS", "Olives_BO") is False

    def test_schema_batch_is_only_create_schema(self):
        text = schema_batch("t")
        assert text == "CREATE SCHEMA [t]\nGO\n"
        assert "CREATE TABLE" not in text
        assert "CREATE TYPE" not in text
```

- [ ] **Step 3: Run** `python3.13 -m unittest tests.test_dependency_order -v`

Expected: FAIL.

- [ ] **Step 4: Implement** Kahn's algorithm in `order_names` and `order_databases`. Stable by the input order of `names` when there is no edge. `same_database` uses `casefold`. `schema_batch` returns the exact string above. Do not add render, capture, or `write_sql_file` in this task.

- [ ] **Step 5: Re-run.** Expected: PASS.

- [ ] **Step 6: Commit** on `feature/full-update-t3`: `feat: order Full Update objects and pull cycles out`.

### Task 2: Trimmer emits a parseable batch

**Files:**
- Modify: `drift/trimmer.py` (`trim_procedure`)
- Modify: `drift/scriptgen.py` (`_as_create_or_alter` only)
- Test: `tests/test_trimmer.py`
- Create: `tests/test_create_or_alter.py`
- Do not edit `tests/test_scriptgen.py` or `drift/test_scriptgen.py`. Unittest cannot import `tests/test_scriptgen.py`. Apply's drop behavior stays checked by `python3.13 drift/test_scriptgen.py`.

**Interfaces:**
- Consumes: `blocks.resolve_scope`, `diffing.split_param_body`, `statements._mask_literals_and_comments`, `hoist_declares`
- Produces: the same dict keys `ok`, `trimmed_sql`, `harvest`, `excluded_ranges`, `reason`. `trimmed_sql` uses `\n` and may contain `\nGO\n`. `_as_create_or_alter` still returns the SET wrapper plus one `CREATE OR ALTER` phrase when the source was a plain `CREATE`, and returns the source unchanged when it already contains `CREATE OR ALTER`.

**Worktree:** `/tmp/drift-fu-t2` on `feature/full-update-t2`, after T9.

- [ ] **Step 1: Open the worktree**

```bash
git worktree add -b feature/full-update-t2 /tmp/drift-fu-t2 feature/full-update-compare
```

- [ ] **Step 2: Add failing tests** to `tests/test_trimmer.py`

```python
class TrimmerBatchTests(unittest.TestCase):
    def test_select_stays_select(self):
        result = trim_procedure("SELECT 1 AS id", 62)
        assert result["ok"] is True
        assert result["trimmed_sql"] == "SELECT 1 AS id"
        assert "Unknown" not in result["trimmed_sql"]
        assert "BEGIN" not in result["trimmed_sql"]

    def test_procedure_keeps_the_matching_branch(self):
        src = (
            "CREATE PROCEDURE dbo.P @ClientActive int AS BEGIN "
            "IF @ClientActive = 62 BEGIN SELECT 62 END ELSE BEGIN SELECT 1 END END"
        )
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert result["trimmed_sql"].startswith("CREATE PROCEDURE")
        assert "SELECT 62" in result["trimmed_sql"]
        assert "SELECT 1" not in result["trimmed_sql"]

    def test_function_stays_function(self):
        src = "CREATE FUNCTION dbo.F() RETURNS int AS BEGIN RETURN 1 END"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert "FUNCTION" in result["trimmed_sql"]
        assert "BEGIN" in result["trimmed_sql"]
        assert "RETURN 1" in result["trimmed_sql"]
        assert "Unknown" not in result["trimmed_sql"]

    def test_inline_tvf_is_returned_executable(self):
        src = "CREATE FUNCTION dbo.F() RETURNS TABLE AS RETURN SELECT 1 AS id"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert "RETURNS TABLE" in result["trimmed_sql"]
        assert "RETURN SELECT 1 AS id" in result["trimmed_sql"]
        assert "Unknown" not in result["trimmed_sql"]
        assert "CREATE PROCEDURE" not in result["trimmed_sql"]

    def test_view_stays_view(self):
        src = "CREATE VIEW dbo.V AS SELECT 1 AS id"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert result["trimmed_sql"].lstrip().upper().startswith("CREATE VIEW")
        assert "Unknown" not in result["trimmed_sql"]

    def test_create_or_alter_procedure_is_a_module(self):
        src = "CREATE OR ALTER PROCEDURE dbo.P @ClientActive int AS BEGIN SELECT 1 END"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert "CREATE OR ALTER PROCEDURE" in result["trimmed_sql"]
        assert "Unknown" not in result["trimmed_sql"]

    def test_use_batch_stays_use(self):
        src = "USE [Olives_BO]\nGO\nSET ANSI_NULLS ON\nGO\nCREATE PROCEDURE dbo.P @id int AS BEGIN SELECT @id END"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert "USE [Olives_BO]" in result["trimmed_sql"]
        assert "-- omitted USE" not in result["trimmed_sql"]
        assert "SET ANSI_NULLS ON" in result["trimmed_sql"]
        assert "\nGO\n" in result["trimmed_sql"]

    def test_go_inside_a_string_does_not_split(self):
        src = "SELECT 'line\nGO\nline' AS q"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert result["trimmed_sql"].count("GO") == 1
        assert "Unknown" not in result["trimmed_sql"]

    def test_string_containing_create_procedure_is_not_a_module(self):
        src = "SELECT 'CREATE PROCEDURE dbo.Fake AS SELECT 1' AS q"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert "Unknown" not in result["trimmed_sql"]
        assert "CREATE PROCEDURE [dbo].[Unknown]" not in result["trimmed_sql"]
        assert result["trimmed_sql"].lstrip().upper().startswith("SELECT")

    def test_invalid_id_on_a_module_is_not_ok(self):
        src = "CREATE PROCEDURE dbo.P @ClientActive int AS BEGIN SELECT 1 END"
        result = trim_procedure(src, "nope")
        assert result["ok"] is False
        assert result["trimmed_sql"] is None

    def test_unbalanced_module_returns_the_original_batch(self):
        src = "CREATE PROCEDURE dbo.P @ClientActive int AS BEGIN IF @ClientActive = 62 BEGIN SELECT 62 END"
        result = trim_procedure(src, 62)
        assert result["ok"] is True
        assert result["trimmed_sql"] == src
        assert result["reason"]

    def test_loose_client_active_is_executable_and_not_a_procedure(self):
        result = trim_procedure("SELECT @ClientActive AS id", 62)
        assert result["ok"] is True
        assert "CREATE PROCEDURE" not in result["trimmed_sql"]
        assert "Unknown" not in result["trimmed_sql"]
        assert "DECLARE @ClientActive int = 62" in result["trimmed_sql"]
        assert "SELECT @ClientActive AS id" in result["trimmed_sql"]

    def test_omitted_id_on_a_batch_with_no_gates_returns_the_select(self):
        result = trim_procedure("SELECT 1 AS id", None)
        assert result["ok"] is True
        assert result["trimmed_sql"] == "SELECT 1 AS id"
```

Create `tests/test_create_or_alter.py` with this module. Do not edit `test_udtt_modified_lands_manual_review`.

```python
import unittest
from drift import scriptgen

class CreateOrAlterOnceTests(unittest.TestCase):
    def test_create_or_alter_is_not_doubled(self):
        src = "CREATE OR ALTER PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        out = scriptgen._as_create_or_alter(src)
        assert "CREATE OR ALTER OR ALTER" not in out
        assert out.upper().count("CREATE OR ALTER") == 1
        plain = "CREATE PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        once = scriptgen._as_create_or_alter(plain)
        assert "CREATE OR ALTER PROCEDURE" in once
        assert "CREATE OR ALTER OR ALTER" not in once
        commented = "-- note\nCREATE OR ALTER PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        kept = scriptgen._as_create_or_alter(commented)
        assert "CREATE OR ALTER OR ALTER" not in kept
        assert kept.upper().count("CREATE OR ALTER") == 1
```

- [ ] **Step 3: Run**

```bash
python3.13 -m unittest tests.test_trimmer tests.test_trimmer_adversarial tests.test_blocks tests.test_create_or_alter -v
python3.13 drift/test_scriptgen.py
```

Expected: the new unittest methods fail. The old adversarial file still passes. `drift/test_scriptgen.py` still prints `32/32 passed`, including `test_udtt_modified_lands_manual_review`.

- [ ] **Step 4: Implement the trimmer**

Behavior inside `trim_procedure`:

1. Normalize CRLF to `\n`.
2. Split on a `GO` line whose masked form (`statements._mask_literals_and_comments`) is only `GO`, case-insensitive. Drop empty batches.
3. A batch whose masked form matches `^\s*USE\b` and is not a module stays the original batch, including `USE [Olives_BO]`. Do not comment it out.
4. Keep `SET ANSI_NULLS` and `SET QUOTED_IDENTIFIER` batches.
5. A batch is a module only when the masked text matches `CREATE`, `ALTER`, or `CREATE OR ALTER`, then `PROC` / `PROCEDURE` / `FUNCTION` / `VIEW` / `TRIGGER`. Words inside a string or comment do not count.
6. For a module, call `blocks.resolve_scope`. If `ok` is false and the reason contains `invalid client_active_id`, return `ok: false`, `trimmed_sql: None`, and that reason. If `ok` is false for any other reason, return `ok: true`, `trimmed_sql` equal to the original batch, and the reason. If `ok` is true, reassemble with the original header through `AS`. Do not replace the verb with `PROCEDURE` when the source is a function, view, or trigger. Keep parameter text. Keep a function's `BEGIN`/`END` and `RETURN` when the source had them. Keep an inline `RETURNS TABLE AS RETURN` body as the source had it. Wrap a procedure body in `BEGIN`/`END` only when the kept body has no outer `BEGIN`.
7. Otherwise the batch is loose SQL. Build a private probe `CREATE PROCEDURE dbo._trim_probe\n    @ClientActive int\nAS\n` plus the batch. Run `resolve_scope` on the probe. Emit only the kept statements, never the probe and never `CREATE PROCEDURE [dbo].[Unknown]`. If the probe's `resolve_scope` fails for an invalid id, return `ok: false` only when the batch itself is a module; a loose batch with no `@ClientActive` and a missing id returns the original batch with `ok: true`. If the probe fails for any other reason, emit the original batch with `ok: true` and the reason. If the emitted loose statements contain `@ClientActive` and do not already `DECLARE` it, prepend `DECLARE @ClientActive int = <id>;`.
8. Join kept batches with `\nGO\n`.

- [ ] **Step 5: Implement the rewriter** in `_as_create_or_alter`, after `_find_create_keyword` returns `(start, end)`:

```python
rest = definition[end:]
if re.match(r"(?is)^\s+or\s+alter\b", rest):
    rewritten = definition.rstrip()
else:
    rewritten = (definition[:start] + "CREATE OR ALTER" + rest).rstrip()
```

Leave the `settings` wrapper as it is. Do not change `assemble`.

- [ ] **Step 6: Re-run** the same two commands. Expected: the unittest command passes, and `drift/test_scriptgen.py` still prints `32/32 passed`.

- [ ] **Step 7: Commit** on `feature/full-update-t2`: `fix: make trimmer output a parseable batch`.

### Task 7: PARSEONLY the large Olives procedure

**Files:**
- Create: `tests/test_trimmer_olives_compile.py`
- Do not modify `drift/trimmer.py` or `drift/full_update.py`.

**Interfaces:**
- Consumes: `trim_procedure` from T2

**Worktree:** `/tmp/drift-fu-t7` on `feature/full-update-t7`, branched from `feature/full-update-t2` after T2's commit. May run beside T4.

```bash
git worktree add -b feature/full-update-t7 /tmp/drift-fu-t7 feature/full-update-t2
```

- [ ] **Step 1: Write the test, skipped unless `RUN_LIVE_DB=1`.**

```python
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

import pymssql

from drift.trimmer import trim_procedure

def _password() -> str:
    env = os.environ.get("DRIFT_RIGHT_PASSWORD")
    if env:
        return env
    out = subprocess.check_output(
        ["docker", "exec", "mssql", "printenv", "MSSQL_SA_PASSWORD"], text=True
    )
    return out.strip()

@unittest.skipUnless(os.environ.get("RUN_LIVE_DB") == "1", "set RUN_LIVE_DB=1")
class OlivesCompileTests(unittest.TestCase):
    def test_ot_send_salesman_data_parses(self):
        password = _password()
        conn = pymssql.connect(
            server="127.0.0.1", port=1433, user="sa", password=password,
            database="Olives_BO", login_timeout=10, timeout=60,
        )
        cur = conn.cursor()
        cur.execute(
            "SELECT OBJECT_DEFINITION(OBJECT_ID(N'dbo.OT_SendSalesmanData')), "
            "CONVERT(varchar(30), modify_date, 126) "
            "FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.OT_SendSalesmanData')"
        )
        definition, before = cur.fetchone()
        cur.execute("SELECT COUNT(*) FROM dbo.ClientsActive WHERE ClientID = 62")
        assert cur.fetchone()[0] >= 1
        conn.close()
        self.assertGreater(len(definition), 800000)
        self.assertTrue(any("\u0600" <= ch <= "\u06ff" for ch in definition))
        result = trim_procedure(definition, 62)
        self.assertTrue(result["ok"])
        self.assertNotIn("Unknown", result["trimmed_sql"])
        payload = (
            "SET PARSEONLY ON;\nGO\n" + result["trimmed_sql"] + "\nGO\nSET PARSEONLY OFF;\n"
        ).encode("utf-8")
        host = pathlib.Path(tempfile.gettempdir()) / "drift_parseonly.sql"
        host.write_bytes(payload)
        subprocess.check_call(["docker", "cp", str(host), "mssql:/tmp/drift_parseonly.sql"])
        subprocess.check_call([
            "docker", "exec", "mssql",
            "/opt/mssql-tools18/bin/sqlcmd", "-C", "-S", "localhost",
            "-U", "sa", "-P", password, "-d", "Olives_BO",
            "-f", "65001", "-i", "/tmp/drift_parseonly.sql",
        ])
        conn = pymssql.connect(
            server="127.0.0.1", port=1433, user="sa", password=password,
            database="Olives_BO", login_timeout=10, timeout=60,
        )
        cur = conn.cursor()
        cur.execute(
            "SELECT CONVERT(varchar(30), modify_date, 126) "
            "FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.OT_SendSalesmanData')"
        )
        after = cur.fetchone()[0]
        conn.close()
        self.assertEqual(before, after)
```

Do not call host `sqlcmd`. Do not print the procedure body or the password. The `PARSEONLY` file is UTF-8 and does not depend on a BOM. `-f 65001` is only on that `sqlcmd` invocation. Do not `ALTER` the procedure.

- [ ] **Step 2: Run** `RUN_LIVE_DB=1 python3.13 -m unittest tests.test_trimmer_olives_compile -v`

Expected: PASS while `mssql` is up. A skip is not a pass for T10.

- [ ] **Step 3: Commit** on `feature/full-update-t7`: `test: parse trimmed OT_SendSalesmanData for client 62`.

### Task I13: Integrate T1, T2, and T3

**Files:** none. Merge only.

**Worktree:** main workspace. `git branch --show-current` must print `feature/full-update-compare`. Do not switch to `main`.

- [ ] **Step 1: Confirm the three lane tests pass** on their branches.
- [ ] **Step 2: Merge**

```bash
git merge --no-ff feature/full-update-t1 -m "merge: procedure exclusion matcher"
git merge --no-ff feature/full-update-t2 -m "merge: parseable trimmer batches"
git merge --no-ff feature/full-update-t3 -m "merge: dependency order"
```

Expected file overlap: none. If the same product file changed on two branches, stop. That is a plan violation.

- [ ] **Step 3: Re-run** from the main workspace:

```bash
python3.13 -m unittest tests.test_proc_filter tests.test_trimmer tests.test_trimmer_adversarial tests.test_blocks tests.test_create_or_alter tests.test_dependency_order -v
python3.13 drift/test_scriptgen.py
```

Expected: PASS.

- [ ] **Step 4: Do not push.**

### Task 4: Render per-database files and the unified script

**Files:**
- Modify: `drift/full_update.py` (add render, capture, and `write_sql_file`; keep T3's functions)
- Modify: `drift/restore.py` (`restore_backup` return dict gains `database_name`)
- Create: `tests/fixtures/left_105_catalog.json`
- Create: `tests/fixtures/right_local_catalog.json`
- Test: `tests/test_full_update.py`

**Interfaces:**
- Consumes: `procedure_excluded`, `order_names`, `order_databases`, `same_database`, `schema_batch`, `scriptgen._as_create_or_alter`, `inspect_objects._rendered_type_ext`
- Produces:
  - `catalog_key_for_restore(header: dict, physical_name: str) -> str` returns `header["database_name"]`. It does not return `physical_name`.
  - `diff_catalogs(left: dict, right: dict) -> dict`
  - `render_table_type(schema: str, name: str, columns: list[dict], memory_optimized: bool) -> str`
  - `render_full_update(left: dict, right: dict, rules: list[dict] | None = None) -> dict` with keys `files` (map of relative name to text using `\n`) and `manifest`
  - `write_sql_file(path, text) -> None`
  - `capture_live_catalog(connector, database_name: str) -> dict`
  - Module docstring contains the phase diagram from this plan

**Worktree:** `/tmp/drift-fu-t4` on `feature/full-update-t4`, created from `feature/full-update-compare` after I13.

```bash
git worktree add -b feature/full-update-t4 /tmp/drift-fu-t4 feature/full-update-compare
```

- [ ] **Step 1: Write the failing tests** in `tests/test_full_update.py` as methods of a `unittest.TestCase`. A bare function is not collected by `python3.13 -m unittest`. Then dump the same catalogs to the two JSON files.

Catalogs use database names `Aaa` and `Zed` on the left. The right catalog keys the same databases as `aaa` and `Zed` so casefold is what matches. Script spelling follows the left (`USE [Aaa]`). `Aaa` is listed first in the dict. `Aaa` references `Zed`. Alphabetical order and dict order both emit `Aaa` first; the assertion requires `Zed` first.

Left `Zed`: table `dbo.T` (`Id` int NULL); procedure `dbo.OnlyZed`.

Right `Zed`: table `dbo.T` present. `OnlyZed` absent.

Left `Aaa`:

- Table `dbo.Parent` columns: `Id` int NOT NULL; `Name` nvarchar max_length 40 nullable (absent on the right); `Flag` int NOT NULL with default `((0))` (absent on the right); `Code` nvarchar max_length 20 NOT NULL with no default (absent on the right); `Seq` int identity seed 1 increment 1 (absent on the right; this add is appendix-only). Right `Parent` has only `Id`.
- Right `Parent` has primary key `PK_Parent` clustered on `(Id)`. Left `PK_Parent` is clustered on `(Id, Name)`.
- Table `dbo.Child` on both sides: `Id` int NOT NULL, `ParentId` int NOT NULL. Right has foreign key `FK_Child_Parent` `(ParentId)` references `Parent(Id)`, and that foreign key references index `PK_Parent`.
- Table `dbo.Fresh` only on the left: `Id` int IDENTITY(1,1) NOT NULL. Right lacks it.
- Table type `dbo.Tvp`, not memory-optimized, columns `Id` int and `Qty` int, both key ordinals 1 and 2. Right `Tvp` is `Id` bigint only, no key.
- Table type `dbo.ThreeKey` columns `A`, `B`, `C` int, key ordinals 1, 2, 3, only on the left, no referencers. This locks the 3-column case. Assert one `PRIMARY KEY`.
- Table type `dbo.NoKey` column `Id` int, no key, only on the left. Assert the rendered type contains no `PRIMARY KEY`.
- Table type `dbo.TvpBound` differs. Referencer `dbo.BoundProc` has `schema_bound: true`. Skip the type.
- Table type `dbo.TvpExcluded` differs. Referencer `dbo.alpha_hide` is excluded by the default list. Skip the type. No `DROP` of `alpha_hide`.
- Procedure `dbo.KeepMe` only on the left.
- Procedure `dbo.UsesTvp` text identical on both sides, dependency to `dbo.Tvp`, and `referenced_database_name` `aaa` (same database, different casing). That edge is not cross-database.
- Procedure `dbo.NeedsZed` only on the left, dependency `referenced_database_name` `Zed`, `to` `dbo.T`. Procedures stay in the script.
- View `dbo.IssueMaster` only on the left: `CREATE VIEW [dbo].[IssueMaster] AS SELECT Id FROM Olives_OWMS.dbo.Items`, dependency `referenced_database_name` `Olives_OWMS`. `Olives_OWMS` is not in the right catalog. Appendix. No `CREATE OR ALTER` of `IssueMaster` in the executable section.
- View `[t].[Wrap]` text identical on both sides: `CREATE VIEW [t].[Wrap] AS SELECT * FROM dbo.[Parent]`. Dependency to `dbo.Parent`. Re-emit it after the `ALTER TABLE` because `Name` is added. Qualified `[t].[Wrap]`, not `[dbo].[Wrap]`.
- View `dbo.V1` selects from `dbo.Parent`. View `dbo.V2` selects from `dbo.V1`. `V1` before `V2`.
- Views `dbo.Loop1` and `dbo.Loop2` reference each other. Appendix only.
- Function `dbo.Zee`: `CREATE FUNCTION [dbo].[Zee]() RETURNS int AS BEGIN RETURN 1 END`. Function `dbo.Caller`: `CREATE FUNCTION [dbo].[Caller]() RETURNS int AS BEGIN RETURN dbo.Zee() END`. Edge `(dbo.Caller, dbo.Zee)`. `Zee`'s create appears before `Caller`'s.
- Right-only table `dbo.LocalOnly`. Absent from every file.
- One object key on the right is `dbo.keepme` while the left is `dbo.KeepMe`. They are the same object, not a second create.

Assertions on `render_full_update` output (text uses `\n`):

- `catalog_key_for_restore({"database_name": "Olives_BO"}, "drift_left_abc") == "Olives_BO"`.
- A catalog keyed `Olives_BO` renders `USE [Olives_BO]`. The joined file text does not contain `drift_left_`.
- `Aaa_udtt.sql` contains `DROP TYPE` and `CREATE TYPE` for `Tvp`, the `TYPE_ID` guard, and exactly one `PRIMARY KEY ([Id], [Qty])` (or the same columns with a space after the comma). It does not contain `PRIMARY KEY` on the `Id` column line and again on the `Qty` column line. `CREATE OR ALTER` of `UsesTvp` appears after `CREATE TYPE [dbo].[Tvp]` and before any `CREATE TABLE` or `ALTER TABLE`. `ThreeKey` has exactly one `PRIMARY KEY` covering `A`, `B`, and `C`. `NoKey` has no `PRIMARY KEY`. `TvpBound` and `TvpExcluded` appear next to `SKIP` and are not dropped. No file contains a `DROP` of `alpha_hide`.
- A rules override that excludes `UsesTvp` (`contains` `uses`) makes `DROP TYPE` of `Tvp` absent and the text contain `SKIP`.
- `Aaa_schema.sql` contains `KeepMe`, contains `nvarchar(20)`, does not contain `nvarchar(40)`, does not contain `CREATE TYPE` or `DROP TYPE`, and does not contain `[dbo].[Wrap]`.
- The unified file contains `CREATE SCHEMA [t]\nGO\n` as its own batch (`CREATE SCHEMA [t]` is the entire batch). That batch appears before `[t].[Wrap]`. `ALTER TABLE` adding `Name` appears before `[t].[Wrap]`. The wrap view text contains `SELECT *`.
- `Flag` is one `ALTER TABLE ... ADD` statement that contains both `NOT NULL` and `DEFAULT`. `Code` does not appear in an `ALTER TABLE ADD`. `Code` and `Seq` appear in the `-- MANUAL` section. `Fresh`'s `CREATE TABLE` contains `IDENTITY`.
- `ADD CONSTRAINT [PK_Parent] PRIMARY KEY` appears after `ALTER TABLE [dbo].[Parent] ADD [Name]` and after `DROP CONSTRAINT [FK_Child_Parent]`. Phase J's `ADD CONSTRAINT [FK_Child_Parent]` appears after the primary-key add. The file does not contain `CREATE PRIMARY KEY` and does not contain `[FLAGS:`.
- `USE [Zed]` appears before `USE [Aaa]`. `USE [aaa]` does not appear. `OnlyZed` and `NeedsZed` are in the executable section (before `-- MANUAL`). `IssueMaster` is only in the manual section.
- `Zee`'s create index is before `Caller`'s. `V1`'s create index is before `V2`'s. `Loop1` and `Loop2` appear only inside `-- MANUAL`.
- Manifest lists excluded `alpha_hide` and has no password key. `dbo.LocalOnly` is absent from every file.
- `render_full_update` does not import `livescan`. The source of `drift/full_update.py` does not contain `referenced_database_id` and does not call `get_index_definitions` or `get_table_type_definitions`.

`capture_live_catalog` test: a fake connector records the database name it was called with and returns a cursor. The SQL strings passed to `execute` include `referenced_database_name` and do not include `referenced_database_id`. Calling `capture_live_catalog(connector, "Olives_BO")` calls the connector once with `Olives_BO`.

`restore_backup` test is the return-shape change: the function's return statement includes `database_name` taken from `header.get("DatabaseName")`. Do not require a live restore in this task. The unit test may read `inspect.getsource` or, simpler, set the return by a fake: T4's test of `catalog_key_for_restore` is the behavior lock, and a one-line source assertion checks `drift/restore.py` contains `"database_name"` in `restore_backup`. Keep the existing keys `backup_date` and `engine_major_version`.

- [ ] **Step 2: Run** `python3.13 -m unittest tests.test_full_update -v`

Expected: FAIL.

- [ ] **Step 3: Implement**

`restore_backup` returns:

```python
return {
    "backup_date": str(backup_date),
    "engine_major_version": sw_version,
    "database_name": header.get("DatabaseName"),
}
```

The physical `db_name` argument is unchanged. The function still restores under that name.

```python
def catalog_key_for_restore(header: dict, physical_name: str) -> str:
    logical = (header.get("database_name") or "").strip()
    if not logical:
        raise ValueError("RESTORE HEADERONLY DatabaseName is empty")
    return logical
```

`physical_name` is accepted so the caller cannot forget it exists, and so the test can pass `drift_left_abc`. The return value ignores it.

`write_sql_file`:

```python
def write_sql_file(path, text) -> None:
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
    path.write_bytes(b"\xef\xbb\xbf" + normalized.encode("utf-8"))
```

Do not use `write_text` or open the file in text mode.

`render_table_type` writes each column without `PRIMARY KEY`. If any column has a key ordinal, append one constraint line `PRIMARY KEY ([c1], [c2], ...)` in key order. Zero key columns means that line is absent. `WITH (MEMORY_OPTIMIZED = ON)` only when the flag is set.

`render_full_update` follows the phase list in this plan. Table-type equality is the rendered string. Column adds use the column record from the Data flow section. Call `_rendered_type_ext` for the type text. Call `_as_create_or_alter` for modules. Call `procedure_excluded` before every module `DROP`. Call `schema_batch` for each non-dbo schema and emit that batch before any object in the schema. Call `order_names` for functions and views. Call `order_databases` with edges built only from dependencies whose `referenced_database_name` fails `same_database`. A view, function, or trigger with a referenced database that is not in the right catalog's database names (casefold) goes to the appendix. A procedure does not.

Index and primary-key text is built in this module:

```python
def render_add_primary_key(schema, table, constraint, columns, clustered: bool) -> str:
    kind = "CLUSTERED" if clustered else "NONCLUSTERED"
    cols = ", ".join(f"[{c}]" for c in columns)
    return (
        f"ALTER TABLE [{schema}].[{table}] ADD CONSTRAINT [{constraint}] "
        f"PRIMARY KEY {kind} ({cols})"
    )
```

Before a `DROP` of `PK_Parent`, emit `ALTER TABLE [dbo].[Child] DROP CONSTRAINT [FK_Child_Parent]` when the captured foreign key's referenced index is `PK_Parent`. Phase J emits the `ADD CONSTRAINT` for that foreign key again. Do not append `[FLAGS:`.

`capture_live_catalog(connector, database_name)` calls `connector(database_name)` once. The connector returns a connection whose current database is that name. Queries are read-only, one statement each: modules (`definition` NULL counted as encrypted, `is_schema_bound` captured), columns with max_length, precision, scale, nullability, identity seed and increment, computed definition, and default definition, table-type columns with key ordinal, dependencies selecting `referenced_database_name` and `referenced_class_desc` (do not select `referenced_database_id`), indexes (key columns, included columns, filter, primary-key and unique-constraint flags), checks, defaults, sequences, and foreign keys including the referenced index name. A NULL module definition becomes a manifest warning. The returned dict matches the catalog shape. It does not include a password.

The phase diagram in the module docstring matches the Dependency order section of this plan.

- [ ] **Step 4: Re-run**

```bash
python3.13 -m unittest tests.test_full_update tests.test_livescan tests.test_create_or_alter -v
python3.13 drift/test_scriptgen.py
```

Expected: PASS. `drift/test_scriptgen.py` still prints `32/32 passed`, including `test_udtt_modified_lands_manual_review`. Livescan still has no script entry point.

- [ ] **Step 5: Commit** on `feature/full-update-t4`: `feat: render Full Update schema, table type, and unified scripts`.

### Task 8: Windows file bytes

**Files:**
- Create: `tests/test_sql_file_bytes.py`
- Do not modify `drift/full_update.py`.

**Interfaces:**
- Consumes: `write_sql_file` from T4

**Worktree:** `/tmp/drift-fu-t8` on `feature/full-update-t8`, after I4. May run beside T5. No shared files with T5.

```bash
git worktree add -b feature/full-update-t8 /tmp/drift-fu-t8 feature/full-update-compare
```

- [ ] **Step 1: Test**

```python
import pathlib
import tempfile
import unittest

from drift.full_update import write_sql_file

class SqlFileByteTests(unittest.TestCase):
    def test_bom_crlf_and_arabic_round_trip(self):
        text = "USE [Olives_BO]\nGO\n-- ع\n"
        path = pathlib.Path(tempfile.mkdtemp()) / "out.sql"
        write_sql_file(path, text)
        data = path.read_bytes()
        self.assertTrue(data.startswith(b"\xef\xbb\xbf"))
        self.assertIn(b"\r\n", data)
        self.assertNotIn(b"\r\r\n", data)
        body = data[3:]
        self.assertNotIn(b"\n", body.replace(b"\r\n", b""))
        self.assertIn("ع", data.decode("utf-8-sig"))

    def test_already_crlf_is_not_doubled(self):
        path = pathlib.Path(tempfile.mkdtemp()) / "out.sql"
        write_sql_file(path, "A\r\nB\r\n")
        self.assertEqual(path.read_bytes(), b"\xef\xbb\xbf" + "A\r\nB\r\n".encode("utf-8"))
```

- [ ] **Step 2: Run** `python3.13 -m unittest tests.test_sql_file_bytes -v`

Expected: PASS on Linux. The test does not call `os.name`. If it fails, stop. Do not edit `drift/full_update.py` in this worktree. Fix `write_sql_file` on `feature/full-update-t4` and re-run I4.

- [ ] **Step 3: Commit** on `feature/full-update-t8`: `test: Full Update SQL files are UTF-8 BOM and CRLF`.

### Task 5: API and the two buttons

**Files:**
- Modify: `app.py`
- Modify: `templates/index.html`
- Modify: `static/app.js`
- Modify: `static/style.css` (dialog layout only, match existing `.block` / `.ghost` styles)
- Test: `tests/test_full_update_api.py`
- Do not modify `drift/full_update.py`, `drift/restore.py`, `drift/proc_filter.py`, or `tests/test_sql_file_bytes.py`.

**Interfaces:**
- Consumes: `render_full_update`, `write_sql_file`, `capture_live_catalog`, `catalog_key_for_restore`, `default_rules`, `procedure_excluded`, `_sql_connect`, `_redact_side`, `restore.restore_backup`. Do not call `_start_compare_job`.
- Produces:
  - `GET /api/procedure_filter/defaults` → `{"rules": default_rules()}`
  - `POST /api/full_update` returns `{"job_id": "..."}`
  - `_start_full_update_job` sets `kind` to `full_update` and stores `{run_id, run_dir, meta, files}`
  - `GET /api/full_update/<run_id>/<filename>` sends one file from `work/output/<run_id>/full_update/` and returns 400 if the name contains `..` or a separator
  - UI: `#fullUpdateBtn` text `Full Update`, `#procFilterBtn` text `Procedures filter`, `#procFilterDialog`, `#procFilterContainsBtn` label `Contains`, `#procFilterStartsBtn` label `Starts with`, `#fullUpdateAllDbs` label `All databases on both sides` default unchecked

**Worktree:** `/tmp/drift-fu-t5` on `feature/full-update-t5`, after I4.

```bash
git worktree add -b feature/full-update-t5 /tmp/drift-fu-t5 feature/full-update-compare
```

- [ ] **Step 1: API tests** with the Flask test client and the fixture paths.

```python
import pathlib
import time
import unittest
from unittest import mock

import app as flask_module

class FullUpdateApiTests(unittest.TestCase):
    def setUp(self):
        flask_module.app.config["TESTING"] = True
        self.client = flask_module.app.test_client()

    def test_defaults_match_the_python_list(self):
        from drift.proc_filter import default_rules
        body = self.client.get("/api/procedure_filter/defaults").get_json()
        self.assertEqual(body["rules"], default_rules())
        self.assertEqual(len(body["rules"]), 21)
        self.assertEqual(body["rules"][0]["value"], "alpha")

    def test_stream_full_update_emits_files_without_workspaces(self):
        import queue
        from app import JOBS
        q = queue.Queue()
        q.put(None)
        JOBS["fu1"] = {
            "queue": q, "error": None, "kind": "full_update",
            "result": {"run_id": "r1", "meta": {}, "files": ["Olives_BO_schema.sql"]},
        }
        body = self.client.get("/api/stream/fu1").get_data(as_text=True)
        self.assertIn("Olives_BO_schema.sql", body)
        self.assertNotIn("workspaces", body)

    def test_bak_script_targets_the_header_name(self):
        import app as app_module
        captured = {}
        dropped = []

        def fake_restore(path, db_name, log):
            self.assertTrue(str(db_name).startswith("drift_left_"))
            captured["physical"] = db_name
            return {
                "backup_date": "2026-01-01",
                "engine_major_version": 16,
                "database_name": "Olives_BO",
            }

        def fake_capture(connector, database_name):
            captured["read_database"] = database_name
            connector(database_name)
            return {"objects": {}, "dependencies": []}

        def fake_drop(name, log):
            dropped.append(name)

        with mock.patch.object(app_module.restore, "restore_backup", fake_restore), \
             mock.patch.object(app_module.full_update, "capture_live_catalog", fake_capture), \
             mock.patch.object(app_module, "drop_database", fake_drop):
            logical, catalog = app_module.load_bak_catalog(
                "/tmp/olives_bo.bak", "drift_left_abc",
                {"server": "127.0.0.1", "port": 1433, "database": "master", "user": "sa", "password": "x"},
                lambda msg: None,
            )
        self.assertEqual(logical, "Olives_BO")
        self.assertEqual(captured["physical"], "drift_left_abc")
        self.assertEqual(captured["read_database"], "drift_left_abc")
        self.assertEqual(dropped, ["drift_left_abc"])
        tiny = {
            "objects": {
                "dbo.KeepMe": {
                    "schema": "dbo", "name": "KeepMe", "type": "SqlProcedure",
                    "definition": "CREATE PROCEDURE [dbo].[KeepMe] AS SELECT 1",
                    "ansi_nulls": True, "quoted_identifier": True, "schema_bound": False,
                }
            },
            "dependencies": [],
        }
        files = app_module.full_update.render_full_update(
            {"databases": {logical: tiny}},
            {"databases": {}},
        )
        joined = "\n".join(files["files"].values())
        self.assertIn("USE [Olives_BO]", joined)
        self.assertNotIn("drift_left_", joined)

    def test_connect_database_uses_a_copy(self):
        import app as app_module
        seen = []
        base = {"server": "127.0.0.1", "port": 1433, "database": "Olives_BO", "user": "sa", "password": "secret"}

        def fake_connect(side):
            seen.append(dict(side))
            return object()

        with mock.patch.object(app_module, "_sql_connect", fake_connect):
            app_module.connect_database(base, "Zed")
            app_module.connect_database(base, "Aaa")
        self.assertEqual([s["database"] for s in seen], ["Zed", "Aaa"])
        self.assertEqual(base["database"], "Olives_BO")

    def test_missing_catalog_path_is_400(self):
        res = self.client.post("/api/full_update", json={
            "left": {"kind": "catalog", "path": "/no/such/left_105_catalog.json"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "databases": ["Aaa"],
        })
        self.assertEqual(res.status_code, 400)
        self.assertIn("path", res.get_json()["error"].lower())

    def test_catalog_pair_writes_keepme_without_a_password(self):
        from drift.proc_filter import procedure_excluded
        self.assertFalse(procedure_excluded("KeepMe"))
        res = self.client.post("/api/full_update", json={
            "left": {"kind": "catalog", "path": "tests/fixtures/left_105_catalog.json"},
            "right": {"kind": "catalog", "path": "tests/fixtures/right_local_catalog.json"},
            "databases": ["Aaa", "Zed"],
        })
        self.assertEqual(res.status_code, 200)
        job_id = res.get_json()["job_id"]
        import app as app_module
        for _ in range(50):
            job = app_module.JOBS[job_id]
            if job.get("done"):
                break
            time.sleep(0.05)
        self.assertIsNone(job.get("error"))
        run_dir = pathlib.Path(job["result"]["run_dir"])
        schema = (run_dir / "full_update" / "Aaa_schema.sql").read_text(encoding="utf-8-sig")
        self.assertIn("KeepMe", schema)
        meta = (run_dir / "meta.json").read_text(encoding="utf-8")
        self.assertNotIn("password", meta.lower())

    def test_filter_ui_has_no_second_copy_of_the_tokens(self):
        js = pathlib.Path("static/app.js").read_text()
        html = pathlib.Path("templates/index.html").read_text()
        self.assertIn("/api/procedure_filter/defaults", js)
        self.assertNotIn("hammoudeh", js)
        self.assertNotIn("hammoudeh", html)
        self.assertNotIn("thuraya", js)

    def test_full_update_button_stays_disabled_until_the_stream_ends(self):
        js = pathlib.Path("static/app.js").read_text()
        start = js.index("fullUpdateBtn.addEventListener")
        handler = js[start:js.index("/* end fullUpdateBtn */")]
        self.assertLess(handler.index("setBusy("), handler.index("fetch("))
        between = handler[handler.index("fetch("):handler.index("new EventSource")]
        self.assertNotIn("clearBusy(", between)
        self.assertNotIn("disabled = false", between)
        self.assertIn('addEventListener("result"', handler)
        self.assertIn('addEventListener("error"', handler)
        self.assertIn("clearBusy(fullUpdateBtn)", handler[handler.index('addEventListener("result"'):])
```

`right.kind` may be `"catalog"` with a `path`, which is how the tests avoid SQL. The Schema tab still sends the Client slot as the right side. `load_bak_catalog` and `connect_database` and `drop_database` are the seams the route uses; they are not a second generator.

Do not edit the `ACTIVE_SEARCH` block in `renderFindingsTable`. `tests/test_compare_subtabs.py` must still pass. The button handler in Step 3 ends with the comment `/* end fullUpdateBtn */` so the source assertion has a bound.

- [ ] **Step 2: Run** `python3.13 -m unittest tests.test_full_update_api tests.test_compare_subtabs -v`

Expected: the new tests fail, compare subtabs still pass. Do not run `unittest discover` in this lane.

- [ ] **Step 3: Implement routes and UI**

`api_stream`, after the `ai_batch` branch and before the compare `else`:

```python
elif job.get("kind") == "full_update":
    payload = {
        "run_id": job["result"]["run_id"],
        "meta": job["result"]["meta"],
        "files": job["result"]["files"],
    }
    yield f"event: result\ndata: {json.dumps(payload)}\n\n"
```

The compare branch still reads `workspaces`. Do not remove it.

`_start_full_update_job` copies the queue shape from `_start_compare_job` and sets `"kind": "full_update"`. It does not write `workspaces` or `_findings`.

Live capture:

```python
def connect_database(base_side: dict, database_name: str):
    side = dict(base_side)
    side["database"] = database_name
    return _sql_connect(side)
```

`app.py` imports `drift.restore as restore` and `drift.full_update as full_update` so tests can patch `app.restore.restore_backup` and `app.full_update.capture_live_catalog`.

Call `capture_live_catalog` once per database name, through `connect_database`. For `all_databases`, the names are the casefold intersection of the left catalog and `sys.databases` (`database_id > 4`). Do not pass the slot database for every name.

```python
def drop_database(name: str, log) -> None:
    log(f"DROP DATABASE [{name}]")
    # Execute that statement on the scratch connection.
    # Never pass Olives_BO, olives_PEEK, Olives_POS, OSFA_DB, or osfa_PEEK.

def load_bak_catalog(bak_path, physical_name, server_side, log):
    header = restore.restore_backup(bak_path, physical_name, log)
    logical = full_update.catalog_key_for_restore(header, physical_name)
    try:
        captured = full_update.capture_live_catalog(
            lambda name: connect_database(server_side, name),
            physical_name,
        )
        return logical, captured
    finally:
        drop_database(physical_name, log)
```

The route stores the captured dict at `left["databases"][logical]`. Files are `{logical}_schema.sql` and `{logical}_udtt.sql`. The script's `USE` is `[logical]`. `physical_name` is `drift_left_<job_id>`. `server_side` is the scratch connection info; `connect_database` overwrites `database` per call.

Left mode gains a third radio `catalog` with a path field. Do not remove Live or Bak.

Full Update click handler, same lifetime as compare (`static/app.js` 585-625):

```javascript
fullUpdateBtn.addEventListener("click", async () => {
  if (fullUpdateBtn.disabled) return;
  setBusy("Full Update…", fullUpdateBtn);
  let res, body;
  try {
    res = await fetch("/api/full_update", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    body = await res.json();
  } catch (err) {
    appendLog("ERROR: " + (err && err.message ? err.message : err), true);
    clearBusy(fullUpdateBtn);
    return;
  }
  if (!res.ok) {
    appendLog("ERROR: " + body.error, true);
    clearBusy(fullUpdateBtn);
    return;
  }
  const es = new EventSource("/api/stream/" + body.job_id);
  es.addEventListener("log", (e) => {
    const msg = JSON.parse(e.data);
    appendLog(msg);
    setBusyLabel(msg);
  });
  es.addEventListener("result", (e) => {
    const result = JSON.parse(e.data);
    renderFullUpdateFiles(result.run_id, result.meta, result.files);
    es.close();
    clearBusy(fullUpdateBtn);
  });
  es.addEventListener("error", (e) => {
    if (e.data) appendLog("FAILED: " + JSON.parse(e.data), true);
    es.close();
    clearBusy(fullUpdateBtn);
  });
});
/* end fullUpdateBtn */
```

`renderFullUpdateFiles` builds download links to `/api/full_update/<run_id>/<filename>`. It does not call `renderResults` and it does not read `workspaces`.

Dialog: on open, `fetch("/api/procedure_filter/defaults")` and render every rule. Contains adds `{"op":"contains","value":<input>}`. Starts with adds `{"op":"starts_with","value":<input>}`. Each row has Remove. Do not hardcode `hammoudeh` or any other token in `app.js` or `index.html`. The button does not call `/apply`.

- [ ] **Step 4: Re-run** `python3.13 -m unittest tests.test_full_update_api tests.test_compare_subtabs -v`

Expected: PASS. Do not run the full discover here.

- [ ] **Step 5: Commit** on `feature/full-update-t5`: `feat: add Full Update button and procedure filter dialog`.

### Task I4: Integrate T4

**Files:** none. Merge only.

**Worktree:** main workspace, branch `feature/full-update-compare`.

- [ ] **Step 1: Merge T4**

```bash
git merge --no-ff feature/full-update-t4 -m "merge: Full Update renderer"
```

- [ ] **Step 2: If T7 is already green, merge it too**

```bash
git merge --no-ff feature/full-update-t7 -m "merge: PARSEONLY OT_SendSalesmanData"
```

If T7 is still running, leave it for I58. T5 and T8 do not need T7's file.

- [ ] **Step 3: Run** `python3.13 -m unittest tests.test_full_update tests.test_dependency_order -v`

Expected: PASS.

- [ ] **Step 4: Do not push.** T5 and T8 may start after this merge.

### Task I58: Integrate T5, T8, and T7

**Files:** none. Merge only.

**Worktree:** main workspace, branch `feature/full-update-compare`.

- [ ] **Step 1: Merge**

```bash
git merge --no-ff feature/full-update-t5 -m "merge: Full Update API and dialog"
git merge --no-ff feature/full-update-t8 -m "merge: SQL file byte test"
```

Merge `feature/full-update-t7` here if I4 did not. Expected overlap: none. T5 must not have edited `drift/full_update.py`. T8 must not have edited it either.

- [ ] **Step 2: Full suite**, now that T8's test file is on the branch:

```bash
python3.13 -m unittest discover -s tests -q
```

Expected: the only errors are the same 10 legacy import modules recorded in T9. No new error module. `Ran` is higher than 199 by the tests added in T1–T8. This is the full-suite run A14 places after T8. A skipped T7 is not a pass; run `RUN_LIVE_DB=1 python3.13 -m unittest tests.test_trimmer_olives_compile -v` and require PASS before T10. Also run `python3.13 drift/test_scriptgen.py` and require `32/32 passed`.

- [ ] **Step 3: Do not push.**

### Task 10: QA, required order proof, push the feature branch

**Depends on:** I58 green, and T7 passed once with `RUN_LIVE_DB=1` (a skip is not a pass).

**Files:**
- Create: `tests/test_full_update_rehearsal.py` for the order proof and the header-name capture. No change to the generator's `USE` spelling.

**Worktree:** main workspace, branch `feature/full-update-compare`. Do not switch to `main`.

- [ ] **Step 1: Browser `/qa`.** Pages: `/` Schema tab, the Procedures filter dialog, the Full Update download, the Trimmer tab. Cases: empty rules input, double-click while the first job's stream is open (the button stays disabled; a second job does not start), left catalog missing, right server down, two databases in the fixture, the skip-`DROP TYPE` fixture, BOM download opened as text, existing Compare still lists a name that the new filter would exclude (Compare uses the txt file, not the dialog). The open dialog shows every default token from the API and no extra token.

- [ ] **Step 2: Header-name capture (required).** Restore `/media/alaa/data/olives/data/db-snapshots/backup test/105/olives_bo.bak` through `restore.restore_backup` to physical name `drift_left_<id>` only. Assert the returned `database_name` casefolds equal to `olives_bo`. Capture that physical database. Assert the catalog key, the output filename, and `USE` are the header name `Olives_BO`. Assert the generated file text does not contain `drift_left_`. Do not execute that file. `DROP DATABASE [drift_left_<id>]` in a `finally`.

- [ ] **Step 3: Order proof (required).** This is not `SET PARSEONLY`.

  - Generate `unified_full_update.sql` from `tests/fixtures/left_105_catalog.json` and `tests/fixtures/right_local_catalog.json`.
  - `CREATE DATABASE [drift_right_<id>]` inside the container. `<id>` is new. Do not create or write `Olives_BO`, `olives_PEEK`, `Olives_POS`, `OSFA_DB`, or `osfa_PEEK`.
  - Write a proof copy under `tempfile.gettempdir()`. The only edits are: replace `USE [Zed]` and `USE [Aaa]` with `USE [drift_right_<id>]`, and delete the `-- MANUAL` appendix so `IssueMaster` is not executed. Do not change the generator and do not change the file that the button would download.
  - `docker cp` the proof copy. Run `/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P <password> -d drift_right_<id> -f 65001 -i` that file inside the container. Assert return code 0.
  - Assert, with a query against `drift_right_<id>` only, that `dbo.Zee` and `dbo.Caller` both exist (the create order was already enforced by execution: `Caller`'s body calls `Zee`, and functions bind at create time).
  - `DROP DATABASE [drift_right_<id>]`.
  - Do not point sqlcmd at `Olives_BO` for this step.

- [ ] **Step 4: Run** `RUN_LIVE_DB=1 python3.13 -m unittest tests.test_full_update_rehearsal tests.test_trimmer_olives_compile -v`

Expected: PASS. The rehearsal test does not print the password or the 900940-character procedure.

- [ ] **Step 5: Push the feature branch only**

```bash
git status
git push -u origin feature/full-update-compare
```

`git status` must show branch `feature/full-update-compare`. Do not push `main`. Do not force-push.

## Deep checks (T9, then again at I58)

- `python3.13 -m unittest tests.test_trimmer tests.test_trimmer_adversarial tests.test_blocks tests.test_statements tests.test_compare tests.test_livescan tests.test_create_or_alter -v`
- `python3.13 drift/test_scriptgen.py` still prints `32/32 passed`, including `test_udtt_modified_lands_manual_review` and `test_create_or_alter_survives_a_leading_comment`.
- `tests/test_livescan.py` still asserts there is no script function on `livescan`.
- T4 asserts rendering does not import `livescan`.

## Windows verification method

T8 runs on Linux and checks bytes. It does not shell out. `write_sql_file` uses `pathlib.Path.write_bytes` and does not branch on `os.name`. The app paths used by Full Update are `pathlib.Path` and `pymssql`. No `bash`, `grep`, or `/tmp` hard-code inside `drift/full_update.py` or `drift/proc_filter.py`. Temp files in T7 and T10 use `tempfile.gettempdir()`. The worktree paths under `/tmp/drift-fu-*` are for git checkouts, not for application code. The existing `tools/check_windows_exe.py` and `build-windows.bat` stay the exe check. This branch does not require an exe rebuild to merge. Script contents are identical across OSes because the byte write does not branch on `os.name`.

## Implementation Tasks

- [ ] **T9 (P1)** — baseline in the main workspace. Verify: `python3.13 -m unittest discover -s tests -q` shows only the 10 legacy import errors named in Task 9, and `python3.13 drift/test_scriptgen.py` prints `32/32 passed`
- [ ] **T1 (P1)** — `proc_filter` in `/tmp/drift-fu-t1`. Amendments: A3. Verify: `python3.13 -m unittest tests.test_proc_filter -v`
- [ ] **T2 (P1)** — trimmer and `_as_create_or_alter` in `/tmp/drift-fu-t2`. Amendments: A7, A13. Verify: `python3.13 -m unittest tests.test_trimmer tests.test_trimmer_adversarial tests.test_blocks tests.test_create_or_alter -v` and `python3.13 drift/test_scriptgen.py`
- [ ] **T3 (P1)** — order functions in `/tmp/drift-fu-t3`. Amendments: A4, A8, A10. Verify: `python3.13 -m unittest tests.test_dependency_order -v`
- [ ] **I13 (P1)** — merge T1–T3 onto `feature/full-update-compare`. Amendment: A14.
- [ ] **T4 (P1)** — renderer, `capture_live_catalog`, `write_sql_file`, header database name, in `/tmp/drift-fu-t4`. Amendments: A1, A3, A4, A5, A6, A8, A9, A10, A12. Verify: `python3.13 -m unittest tests.test_full_update tests.test_livescan tests.test_create_or_alter -v` and `python3.13 drift/test_scriptgen.py`
- [ ] **T7 (P1)** — Unicode `PARSEONLY` in `/tmp/drift-fu-t7`. Amendment: A11. May run beside T4. Verify: `RUN_LIVE_DB=1 python3.13 -m unittest tests.test_trimmer_olives_compile -v`
- [ ] **I4 (P1)** — merge T4 (and T7 if green).
- [ ] **T5 (P1)** — API, stream, dialog, button lifetime, in `/tmp/drift-fu-t5`. Amendments: A2, A1 route. Verify: `python3.13 -m unittest tests.test_full_update_api tests.test_compare_subtabs -v`
- [ ] **T8 (P1)** — byte test only, in `/tmp/drift-fu-t8`. Amendment: A12. Beside T5. Verify: `python3.13 -m unittest tests.test_sql_file_bytes -v`
- [ ] **I58 (P1)** — merge T5, T8, and T7, then discover. Amendment: A14. The only discover errors are the T9 legacy 10. `python3.13 drift/test_scriptgen.py` still prints `32/32 passed`.
- [ ] **T10 (P1)** — `/qa`, required `drift_right_<id>` order proof, push `feature/full-update-compare` only. Amendments: A1, A11.

## Completion summary

- Step 0: scope accepted (full behavior, two new modules, plus the `restore_backup` return field and the `_as_create_or_alter` single-phrase fix)
- Architecture, code quality, tests, performance, and failure modes: folded into the decisions and the task bodies
- Outside voice (Claude subagent): 19 holes accepted into decisions 26-39
- Devil's advocate 2026-10-28: verdict AMEND THEN SHIP. A1–A14 accepted into decisions 40-53 and into the task bodies. Rejected alternative: another review round (decision 54)
- Parallelization: T9 in the main workspace, then T1/T2/T3 in separate worktrees, I13, then T4 beside T7, I4, then T5 beside T8, I58, then T10
- NOT in scope: written, including no further review round and no token changes

## Retrospective

Recent commits on `main` (`c329908`, `b537924`, `ba72f5b`) already repaired trimmer scoping, declare hoisting, and GOTO labels, and added the procedure viewer. This plan extends that work. It does not reopen the viewer. The `Unknown` wrapper, the commented-out `USE`, and the doubled `CREATE OR ALTER` are the holes those commits left for T2.

## Files that get a diagram comment

- `drift/full_update.py` module docstring: the phase list. Task T4 owns it. If a later task changes a phase, it updates the docstring in the same commit.

## Outside voice

Codex CLI is not installed (`command -v codex` empty). The first outside voice was a Claude subagent and is decisions 26-39.

```
CROSS-MODEL TENSION (first outside voice):
  [Unified file is safe]: accepted as ordered, not atomic.
  [View order]: V1 before V2 is required.
  [All databases by default]: checkbox, default off.
```

Devil's advocate (`docs/plans/2026-10-28-full-update-compare-devil.md`), 2026-10-28, verdict AMEND THEN SHIP. A1–A14 are in decisions 40-53 and in the task bodies. No tension from that critique was left open. No further review round.

## Suggested next reviews

None before implementation. Decision 54 rejected another review round. `/plan-design-review` and `/plan-ceo-review` are not gates for T9–T10.

## Unresolved decisions

None. Decisions 1-54 each have a chosen option. A1–A14 are accepted. The rejected alternative to another review round is recorded in decision 54.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN) | 46 issues, 0 critical gaps, all folded |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |
| Devil's advocate | `docs/plans/2026-10-28-full-update-compare-devil.md` | Fatal flaws before implementation | 1 | AMEND THEN SHIP | A1–A14 accepted 2026-10-28; rejected alternative: another review round |

**VERDICT:** ENG CLEARED — ready to implement. Outside voice was a Claude subagent (Codex CLI absent); its 19 findings were accepted into decisions 26-39.

NO UNRESOLVED DECISIONS
