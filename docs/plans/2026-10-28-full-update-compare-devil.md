# Devil's advocate: Full Update plan

Verdict: **AMEND THEN SHIP**

The separate renderer is a sound approach. The plan as written would still generate a script that does not target `Olives_BO`, crash the button's result stream, emit SQL Server will reject, and drop procedures a later error never puts back. Measured on the local `Olives_BO` (2026-10-28): 1664 procedures, 119 table types, 485 foreign keys, 412 views in schema `t`, 0 schema-bound modules, 0 indexed views, 0 `CREATE OR ALTER` texts today.

Cited line numbers that match the code: `trimmer.py` 131-138, `blocks.py` 493-496 and 512-513 and 660-668, `scriptgen.py` 178-182 and 303-304, `inspect_objects.py` 346 and 574, `app.py` 779-783, `restore.py` 181. The plan's `referenced_database_id` does not exist on `sys.sql_expression_dependencies`.

## Fatal flaws

1. **Left bak is not `Olives_BO`.** `restore.restore_backup` (`restore.py` 112-181) restores under the name it is given and returns only `backup_date` and `engine_major_version`. It does not return `RESTORE HEADERONLY.DatabaseName`. Decision 35 stores the database as `drift_left_<id>`. Decision 11 then keeps a database only when that name casefolds to the right-hand name. `drift_left_ab12` does not casefold to `Olives_BO`. The default click writes no script, or the script says `USE [drift_left_ab12]` for a database the `finally` block has already dropped. The user runs it and SQL Server reports that the database does not exist. The toy fixture uses the same names on both sides, so T4 passes.

2. **The result stream crashes after a good run.** `api_stream` (`app.py` 779-783) reads `job["result"]["workspaces"]` for every kind except `ai_batch`. The compare UI (`static/app.js` 606-615) always opens that stream and passes `workspaces` to `renderResults`. Decision 36 stores `{run_id, run_dir, meta, files}` and never mentions `api_stream`. The job can write the files and the UI still shows a failure, with no download links.

3. **`{db}_udtt.sql` drops procedures and does not recreate them.** The per-file contract (plan lines 207-208) says the table-type file may `DROP` procedures and the schema file recreates them later, in phase H. That violates the plan's own rule that nothing is dropped unless the same script recreates it. All 178 type references in `Olives_BO` are stored procedures. Running the table-type file alone, or stopping on an error in phases B-G of the unified file, leaves those procedures missing. Grants on them are gone as well; permission scripting stays out of scope, so this window is the actual outage.

4. **The cross-database column is wrong, and the "same-database" claim is false.** `sys.sql_expression_dependencies` has `referenced_database_name`. It does not have `referenced_database_id`. A capture query copied from the plan fails on every live database, including the Docker `Olives_BO`. The same catalog has 672 procedure edges to `OSFA_DB`, 183 to `olives_BO` (the database's own name, different casing), and further edges to `Olives_OWMS`, `Olives_Images`, `Olives_Log`, and many integration databases. Procedures survive `CREATE` because of deferred name resolution. Views and functions do not. Six view edges point at `Olives_OWMS`, which is not on this instance (`IssueMaster` → `Olives_OWMS.dbo.Items`). `CREATE OR ALTER` of that view fails and sqlcmd stops the rest of the file. T4's `USE [DbA]` before `USE [DbB]` also passes a plain name sort, because `DbA` sorts before `DbB`.

5. **Two real table types get illegal `PRIMARY KEY` SQL.** `inspect_objects.py` 574 appends ` PRIMARY KEY` to every key column. `CustomersPromotionsGroupsLink_Type` and `Meatland_Integration_PriceLists` each have a 3-column primary key. Decision 27 makes that rendered string the definition. The script then contains three `PRIMARY KEY` clauses. `CREATE TYPE` fails. T4's single-column `dbo.Tvp` does not catch it. 108 of 119 types have no primary key at all, so a test that only checks that the word `PRIMARY KEY` appears is also the wrong shape for most types.

6. **Primary-key text from the existing catalog reader is not executable.** `get_index_definitions` (`inspect_objects.py` 346) emits `CREATE PRIMARY KEY CLUSTERED INDEX [name] ON [table] (...)`. SQL Server rejects that. The legal statement is `ALTER TABLE [table] ADD CONSTRAINT [name] PRIMARY KEY CLUSTERED (...)`. The same strings append ` [FLAGS: ...]` when a flag is set. "Reuse the catalog readers" points the implementer at this text. There are 485 foreign keys. Dropping a unique index or primary key in phase J while those foreign keys still exist fails with 3723. T4 has no index and no foreign key, so an empty phase J passes.

7. **The second Full Update breaks every module the first one rewrote.** `_as_create_or_alter` (`scriptgen.py` 303-304) replaces the word `CREATE` with `CREATE OR ALTER`. Today zero module texts contain `CREATE OR ALTER`. After this script is applied, `sys.sql_modules.definition` stores `CREATE OR ALTER`, and the next run emits `CREATE OR ALTER OR ALTER PROCEDURE`. The fixture definitions are plain `CREATE`, so the test stays green. The plan says to call this function and not rewrite it.

8. **Schema `t` is 412 of 428 views, and they are `SELECT *`.** Sample: `CREATE VIEW t.[ActivityList] AS SELECT * FROM dbo.[ActivityList]`. Unchanged module text is omitted. An `ALTER TABLE ADD` in phase E therefore does not recreate the wrapper view, and the application, which reads schema `t`, never sees the new column. If schema `t` is missing on the right, `CREATE SCHEMA [t]` must be the only statement in its batch (error 111 otherwise). Phase A currently runs before phase B, and T4 uses only `dbo`, so neither rule is tested.

## Serious holes

- **T4 step 2 shrinks the column record** to `{name, type, nullable}` after decision 28 required length, precision, scale, identity, and computed definition. The assertion says the script adds `Name`. It does not require `nvarchar(20)`. `_rendered_type_ext` stores `nvarchar` length in bytes (40 for `nvarchar(20)`). A renderer that prints `nvarchar(40)` or bare `nvarchar` passes T4 and fails on the server. A `NOT NULL` column whose default lives only in the separate defaults query is indistinguishable from a `NOT NULL` column with no default. Emitting `ADD ... NOT NULL` with no inline default fails on a table that has rows (4901). The defaults capture is not in the column record.

- **Function order is untested and name order is wrong for 41 real pairs.** Example: `dbo.Fun_CalcDistanceBetweenTwoPoints` references `dbo.Trim`, and `Fun_Calc...` sorts first. Functions are bound at `CREATE`. T4's fixture has no function. Phase F says "topological" and nothing in the tests fails if the implementer sorts by name. Zero functions read a view, so phase F then phase G does not fail on this database. Function-to-function order does.

- **T10's check cannot prove the script runs.** `SET PARSEONLY ON` does not execute earlier batches, so a correctly ordered file still fails on an empty database when a view follows `CREATE TABLE` after `GO`. `PARSEONLY` against `drift_left_<id>` does not prove order either, because those objects already exist. The rehearsal is marked optional, so the 105 `.bak` and the logical database name can ship untested. `dbo.OT_SendSalesmanData` is 900940 characters and contains Arabic letters. T7 reads it with `sqlcmd` and no `-f 65001`. The container's default code page corrupts that body before `PARSEONLY`. A corrupted string can still be longer than 800000 characters, so the length assert does not catch it.

- **Trimmer task steps drop decision 19's fallback.** `blocks.resolve_scope` returns `ok: false` for "no statement boundaries" (512-513), unbalanced `BEGIN`/`END` (660), and a cursor or unrecognized body with nothing to delete (668), not only for a bad client id. Task 2 step 5 never says what a module does in those cases. An inline TVF (`RETURNS TABLE AS RETURN`) and a view (`CREATE VIEW v AS SELECT`) are absent from the tests. The module detector is not described as mask-aware, so a batch whose string contains `CREATE PROCEDURE` is rewritten as a module. Step 6's probe procedure does not declare `@ClientActive`, so a loose batch that still mentions that variable does not execute (error 137). Commenting out `USE` makes the rest of an SSMS script run in whatever database the connection already has.

- **The Full Update button is re-enabled too early.** Task 5 disables it until the job id returns, then re-enables it. The compare button stays disabled until the stream finishes (`setBusy` / `clearBusy` in `app.js` 56-84 and 606-618). A second click after the id returns starts a second job. The double-click test is only in the later `/qa` pass.

- **Default exclusions freeze 53 of 119 table types.** Every type reference is a procedure, and 53 types are referenced by at least one name the default rules match. The plan skips `DROP TYPE` in that case. That is the safe outcome. T4 never applies the default list to a type dependency, and it never asserts that the excluded procedure itself is absent from `DROP`. A regression that drops `alpha_hide` still passes the current assertions.

## Parallelism hazards

- The ownership table says T5 does not edit `drift/full_update.py`. The T5 prose then adds `capture_live_catalog` to that module. T8 runs beside T5 and imports `write_sql_file` from the same module. One checkout: T8 collects a half-edited module, or T5's full `unittest discover` imports T8's half-written file.
- T1, T2, and T3 each commit on `feature/full-update-compare`. One working tree serializes on `.git/index.lock` and can commit a mix of unfinished files. Separate worktrees avoid that. The plan does not say to use them.
- T4 and T7 do not share files. T1, T2, and T3 do not share files. Those pairs are safe once each lane has its own worktree and T4 starts only from commits that contain both T1 and T3.

## Decisions that are fine

- New module `drift/full_update.py`. Leave `assemble`, `livescan`, and `_start_compare_job` alone.
- App writes files and does not execute them. Do not point generated SQL at the online `Olives_BO`, `Olives_POS`, or `OSFA_DB`.
- UTF-8 BOM and CRLF for the files the user opens in SSMS.
- Casefold match for this database's `SQL_Latin1_General_CP1256_CI_AS` collation.
- Procedure filter stored once in Python and loaded by the dialog. `exclude-from-drift.txt` stays on the old Compare path.
- Contains and Starts with exclude, combined with OR. The legacy report's `ActiveFilterString` (`SQL_Compare_Reverse_Engineering_Report.md` 232) is a DevExpress grid filter. That report never defines a Contains button. The user's exclude instruction is the one to implement.
- Cycles of views or functions, and their dependents, go to the appendix. `CREATE OR ALTER` plus deferred resolution is enough for procedures.
- Right-only objects stay. No live connection to `10.0.10.105`.

## Blast radius (do not "fix")

Starts-with `sp` matches **11** of 1664 procedures, not most of them. The 11 names are `sp_alterdiagram`, `sp_creatediagram`, `sp_dropdiagram`, `sp_helpdiagramdefinition`, `sp_helpdiagrams`, `sp_renamediagram`, `sp_upgraddiagrams`, `SP_IntegrationErrorLog`, and three `Spartan_SAP_Integ*` procedures. `Spartan` matches because it begins with `Sp`. The wide token is contains `integ` (397 procedures). Contains `api` matches 30, contains `memo` matches 4, starts-with `sms` matches 18. The default list matches 568 procedures and 31 functions. That width is the list the user gave.

## Required plan amendments

### A1
- Section: Decision 35, data-flow "kind=bak", T5 bak paragraph, T10.
- Replacement decision: The catalog key, the `USE` name, and the output filename come from `RESTORE HEADERONLY.DatabaseName`. The physical restore name stays `drift_left_<id>` and is dropped in `finally`. `restore_backup` must return that logical name (today it returns only the date and the engine version, `restore.py` 181). A unit test with a fake header `Olives_BO` and a physical name `drift_left_abc` asserts `USE [Olives_BO]` and asserts the script does not contain `drift_left_`.
- Why: Otherwise the default click does not match the right-hand `Olives_BO`, and the downloaded script targets a database that no longer exists.

### A2
- Section: Decision 36 and Task 5.
- Replacement decision: `_start_full_update_job` sets `kind` to `full_update`. `api_stream` (`app.py` 779-783) emits `{run_id, meta, files}` for that kind and does not read `workspaces`. The button disables in the click handler and stays disabled until the stream's result or error event, using the same lifetime as `setBusy` / `clearBusy`. Each live capture connects with a copy of the side whose `database` field is the database being read. `_sql_connect` uses whatever database is on the side dict (`app.py` 403-421).
- Why: The current stream raises `KeyError` after a successful generate. Re-enabling when the job id returns allows a second job. Reusing the slot database for every name makes "all databases" capture one database repeatedly.

### A3
- Section: Dependency order phase A, per-file contract (lines 207-208), T4 assertions.
- Replacement decision: For each changed table type, the same file that contains `DROP TYPE` also contains, immediately after `CREATE TYPE` and before the next phase, `CREATE OR ALTER` of every module that file dropped. `{db}_udtt.sql` included. The unified file does not wait until phase H to put those modules back. An excluded or schema-bound referencer still skips that type. The rendered SQL contains no `DROP` of an excluded name. T4 asserts that.
- Why: Phase H is hundreds of statements later. Any error before it, or running the table-type file alone, deletes procedures. All 178 type referencers in this database are procedures.

### A4
- Section: Dependency order paragraph that cites `referenced_database_id`, Decision 32, T4 cross-database fixture.
- Replacement decision: Read `referenced_database_name`. A name that casefolds to the database being scripted is not a cross-database edge (`olives_BO` versus `Olives_BO` is 183 edges). A view, function, or trigger whose referenced database is not present on the right-hand instance goes to the appendix and is not emitted as `CREATE OR ALTER`. Procedures stay in the script. The fixture's referenced database must sort after the dependent one by name. Assert `USE [Zed]` before `USE [Aaa]` when `Aaa` references `Zed`. `USE [DbA]` before `USE [DbB]` is not that test.
- Why: The planned column does not exist, so live capture throws. A view such as `IssueMaster` fails the batch when `Olives_OWMS` is absent. The current fixture passes a name sort.

### A5
- Section: Decision 27 and T4 table-type assertion.
- Replacement decision: A table type has at most one `PRIMARY KEY` constraint, covering every key column in key order. Do not append `PRIMARY KEY` to each column (`inspect_objects.py` 574). T4 includes a two-column key and asserts a single constraint. A type with no key, which is 108 of 119 here, emits no `PRIMARY KEY`.
- Why: `CustomersPromotionsGroupsLink_Type` and `Meatland_Integration_PriceLists` have 3-column keys. The mandated renderer produces illegal `CREATE TYPE`.

### A6
- Section: Decision 29 and phase J / phase K.
- Replacement decision: Do not emit `get_index_definitions` or the `[FLAGS: ...]` suffix as script text. A primary key or unique constraint is `ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY|UNIQUE`. A non-constraint index is `CREATE [UNIQUE] INDEX`, including `INCLUDE` and `WHERE` when captured. Before the script drops an index or unique constraint, it drops foreign keys that reference it, and phase K creates those foreign keys again. T4 has two tables, a primary key, and a foreign key, and asserts the primary-key statement is `ADD CONSTRAINT` and that it appears after both tables exist and after any `DROP CONSTRAINT` of the foreign key.
- Why: `CREATE PRIMARY KEY CLUSTERED INDEX` does not parse (`inspect_objects.py` 346). Dropping a referenced key while 485 foreign keys still exist fails with 3723. T4 currently passes with both phases empty.

### A7
- Section: Decision 34.
- Replacement decision: `_as_create_or_alter` leaves an existing `CREATE OR ALTER` as a single phrase. It must not produce `CREATE OR ALTER OR ALTER`. Add a test whose definition already starts with `CREATE OR ALTER PROCEDURE`. Apply's drop behavior stays unchanged.
- Why: The first applied run stores `CREATE OR ALTER` in `sys.sql_modules`. The next Full Update then emits invalid SQL for every such module. The function does that today (`scriptgen.py` 303-304). This database simply has not been through that run yet.

### A8
- Section: Phase A/B/G and the "unchanged module text" row.
- Replacement decision: `CREATE SCHEMA` is its own batch, ended with `GO`, and it runs before any type, table, or module in that schema. A view is emitted even when its text matches the right side if this script adds or alters a column of a table that view references. Schema qualification comes from the catalog (`[t].[ActivityList]`, not `dbo`). T4 includes schema `t`, a `SELECT *` view on `dbo.T`, and an added column, and asserts `CREATE SCHEMA [t]` is followed by `GO` and that the view is emitted after the `ALTER TABLE`.
- Why: 412 views are `CREATE VIEW t.[Name] AS SELECT * FROM dbo.[Name]`. Skipping an unchanged `SELECT *` view hides the new column from the application. `CREATE SCHEMA` beside other statements in one batch fails with 111.

### A9
- Section: Task 4 step 2 and the column-add assertions. Decision 28 stays.
- Replacement decision: The column record is name, type name, max_length, precision, scale, nullable, identity, computed definition, and the default expression when one exists. Render types with `_rendered_type_ext` (`nvarchar(20)` from max_length 40). The T4 assertion contains `nvarchar(20)`. A `NOT NULL` add that has a default is one `ALTER TABLE ADD ... NOT NULL CONSTRAINT ... DEFAULT ...` statement. A `NOT NULL` add with no default, and any computed or identity add, stays in the appendix. Identity is part of `CREATE TABLE` for a new table.
- Why: The task text the implementer will follow drops length and the default. Bare `ADD col int NOT NULL` fails on a non-empty table.

### A10
- Section: Task 4 fixture.
- Replacement decision: Include `dbo.Caller` and `dbo.Zee`, with an edge from `Caller` to `Zee`, and assert `Zee`'s `CREATE` appears before `Caller`'s. `Caller` sorts first by name.
- Why: 41 function pairs in `Olives_BO` are in that shape. Functions fail at create time if the callee is not already on the target. The current fixture has no function, so name order passes.

### A11
- Section: Task 7 and Task 10.
- Replacement decision: Read `OBJECT_DEFINITION` through `pymssql` (the app's driver), not through `sqlcmd`'s default code page. `sqlcmd -f 65001` is only for the `PARSEONLY` file, written as UTF-8 without relying on a BOM. T10 is required before push. Restore `olives_bo.bak` to `drift_left_<id>`, capture it, and assert the catalog key is the header's `DatabaseName`. Prove order by executing the unified script with `sqlcmd` inside the container against a new `drift_right_<id>` only, then `DROP DATABASE`. `SET PARSEONLY` of that multi-batch file is not the proof. Do not execute against `Olives_BO`, `olives_PEEK`, `Olives_POS`, `OSFA_DB`, or `osfa_PEEK`.
- Why: The procedure body contains Arabic and is 900940 characters. `PARSEONLY` does not apply earlier batches, so it rejects a correct script on an empty database and accepts a badly ordered script against a database that already has the objects. The optional label lets the 105 mimic ship untested.

### A12
- Section: Decision 21 and Task 8.
- Replacement decision: `write_sql_file` writes bytes: UTF-8 BOM plus the text with newlines normalized to CRLF. It does not use text mode. On Windows, text mode turns an already-CRLF string into CR CR LF. T8 stays a byte test and runs on Linux; the implementation requirement is the binary write.
- Why: T8 passes on Linux either way. SSMS on Windows then shows a blank line between every line, and some clients reject the batch.

### A13
- Section: Task 2 steps 5-6 and the new tests.
- Replacement decision: A module whose `resolve_scope` fails for any reason other than an invalid `client_active_id` is returned unchanged, with `ok: true` and the original batch (`blocks.py` 512, 660, 668). Invalid id on a module stays `ok: false`. Detect `CREATE` / `ALTER` / `CREATE OR ALTER` only outside strings and comments, using the same mask as the `GO` split. A `USE` batch stays a real `USE` batch. Add tests for an inline `RETURNS TABLE` function, a `CREATE VIEW ... AS SELECT`, and a string that contains the words `CREATE PROCEDURE`.
- Why: The task steps only special-case loose SQL. An inline function or a failed cursor body becomes HTTP 400 and an empty box. A commented-out `USE` runs the rest of the script in the connection's current database.

### A14
- Section: Parallel work table and the T5 file list.
- Replacement decision: `capture_live_catalog` is written in T4, in `drift/full_update.py`, before T5 and T8 start. T5 does not edit that module. T1, T2, and T3 run in separate git worktrees and merge before T4. T5's full-suite run starts after T8's test file is committed.
- Why: The task prose and the ownership table disagree, and T8 imports the module T5 would still be editing. Parallel commits in one checkout collide on the git index.

## Do not change

- Contains tokens, exactly: `alpha`, `sap`, `bonanza`, `integ`, `mms`, `jawad`, `hammoudeh`, `technical`, `niroukh`, `api`, `medical`, `poa`, `tax`, `asset`, `thuraya`, `cmms`, `memo`.
- Starts-with tokens, exactly: `sp`, `oms`, `sms`, `owms`.
- Do not add tokens. Do not anchor `sp`, `api`, `integ`, `memo`, or `tax` to a word boundary or to an underscore. `sp` matching `Spartan_SAP_Integ` and `SpecialReport` is the requested prefix. `integ` matching 397 procedures is the requested substring.
- Contains and Starts with exclude. They do not filter the grid down to matching names. Several rules combine with OR.
- Do not merge this list into `exclude-from-drift.txt`. Do not change that file's `fnmatch` behavior.
- Do not drop an excluded procedure or function in order to `DROP TYPE`. Skip the type.
- Do not add `GRANT` / user / role scripting. Permissions stay out of scope. The outage to avoid is the early `DROP` in A3, not a new permission feature.
- Do not generate Full Update SQL with sqlpackage, `livescan`, or `_start_compare_job`.
- The application does not execute the generated files. Rehearsal execution is only against `drift_left_<id>` / `drift_right_<id>`, then drop those databases.
- Do not push `main`.

Execution can start after A1-A14 are written into the plan. No further review round is required before implementation, as long as those replacement decisions replace the sentences they name and the T4 fixture assertions are updated with them.
