# Olives drift-tool — Project blueprint

**Canonical reference** for everything under `apps/drift-tool/`. This document is the blueprint: what the product is for, how to run and use each tool, what each component can and cannot do, how behavior is validated in code, and how the engine is wired.

Shorter day-to-day recipes also live in [TUTORIAL.md](TUTORIAL.md). Historical SQL Compare teardown notes are in [legacy/sql-compare/](legacy/sql-compare/) (reference only; behavior is defined by this app’s code).

---

## Table of contents

1. [Mission and non-goals](#1-mission-and-non-goals)
2. [How to run the app (desktop-first)](#2-how-to-run-the-app-desktop-first)
3. [Operator guide — UI tools and workflows](#3-operator-guide--ui-tools-and-workflows)
4. [Capability catalog (what each tool does)](#4-capability-catalog-what-each-tool-does)
5. [Runtime and process architecture](#5-runtime-and-process-architecture)
6. [Repository layout](#6-repository-layout)
7. [Schema compare pipeline (authoritative path)](#7-schema-compare-pipeline-authoritative-path)
8. [Engine modules reference](#8-engine-modules-reference)
9. [HTTP API reference](#9-http-api-reference)
10. [Safety model](#10-safety-model)
11. [Configuration and secrets](#11-configuration-and-secrets)
12. [On-disk artifacts and data contracts](#12-on-disk-artifacts-and-data-contracts)
13. [Validation program — how we know it works](#13-validation-program--how-we-know-it-works)
14. [Troubleshooting](#14-troubleshooting)
15. [Legacy and boundaries](#15-legacy-and-boundaries)

---

## 1. Mission and non-goals

### 1.1 Business problem

Olives ERP ships as a **master database image (“105”)**. Each client database is a copy that has **drifted**: custom logic often lives inside shared stored procedures, gated by `IF @ClientActive = <client_id>` (parsed by `drift/blocks.py`, spliced by `drift/gatewrap.py`).

**Naive schema sync** or pasting raw `master_def` onto a client can **delete** client-only gated branches. This tool exists to prevent that class of accident.

### 1.2 What the tool does

| Does | Does not |
|------|----------|
| Compare master vs client (`.bak` or live extract) with SqlPackage evidence | Auto-sync production without human review |
| Scope procedure diffs to **this client’s** executable branches | Decide drift using AI |
| Classify findings deterministically; assemble **additive** scripts from **approved** rows | Emit DROP by default |
| Rehearse scripts on a **scratch** restore of the client `.bak` | Target master (105) from interactive apply |
| Record update packages in an append-only **ledger** | Store API keys in the repo or send keys to the browser |
| Triage live servers in **seconds** (livescan) | Replace full compare with livescan for release sign-off |
| Copy config-table rows (client destination only) and deploy static web trees (with explicit APIs) | Run webpage deletes without `allow_delete=True` |

### 1.3 Design principles (enforced in code)

| Principle | Implementation |
|-----------|----------------|
| Deterministic detection | `compare.py` (DeployReport XML) + `diffing.py` normalization/hashes |
| AI is advisory only | `ai.py` / `ai_merge.py`; `classify.py` rules R1–R6 never call models |
| Evidence on disk | `report_writer.py` → `work/output/<run_id>/` |
| Additive scripts | `scriptgen.assemble()` skips `only_on_other` (DROPs only with explicit `include_deletions=True`); column drops/retypes → manual_review |
| Visible noise | `formatting_only`, `documentation`, `cascading`, `no_difference` buckets |
| Honest degradation | Skipped SQL statements appear in execution reports; corrupt ledger lines skipped; corrupt `profiles.json` read as `{}` |
| ClientActive scoping | `blocks.resolve_scope` → `scope.irrelevant_to_client` |
| Rehearse before trust | `executor.rehearse()` + `RUN_LIVE_DB=1` gate |

---

## 2. How to run the app (desktop-first)

### 2.1 Primary: desktop window

```bash
cd apps/drift-tool
./run-desktop.sh
```

Or install **`olives-drift-tool.desktop`** (points at `run-desktop.sh`).

| Step | Component |
|------|-----------|
| 1 | `run-desktop.sh` sources **`.env`** if present (`set -a`, so every variable is exported), then picks the first interpreter that can `import flask, sqlglot, gi`, in order: `venv_desktop/bin/python`, `python3.12`, `python3.13`, `python3`. None found → exits 1 with install hints (`python3-gi`, `gir1.2-webkit2-4.1`) |
| 2 | `desktop.py` starts Flask (`app.py`) on **`127.0.0.1:5057`** in a daemon thread (`use_reloader=False`), waits up to 15 s for `/` to answer, else exits 1 |
| 3 | GTK 3 **WebKit2 4.1** window (1280×800, title “Drift Tool — DB Schema Compare”) loads the same UI as the browser |
| 4 | Native **`.bak` file picker** (`Gtk.FileChooserNative`, `*.bak` filter, 300 s timeout) registered via `app.register_bak_picker` → served by `/api/desktop/open_bak`; needs `DISPLAY` or `WAYLAND_DISPLAY` |
| 5 | Desktop log: **`~/.drift-tool-desktop.log`** |

Pywebview was **not** used: its GTK backend left the WebKit input surface at 1×1, so clicks never reached the page.

### 2.2 Secondary: system browser

```bash
./run.sh          # docker start drift-tool-mssql + background python3.13 app.py + xdg-open http://localhost:5057
python3.13 app.py # Flask on 127.0.0.1:5057 when run directly (loopback only, debug off)
```

`run.sh` does **not** source `.env`; export secrets in the shell first. `docker start` only starts an existing container — if it does not exist yet, the first compare creates it (`docker_mgmt.ensure_running`). Without the desktop host, `/api/desktop/open_bak` returns **501** and the UI falls back to `/api/browse` / `/api/backups`.

### 2.3 External dependencies

| Dependency | Purpose |
|------------|---------|
| **Docker** | Scratch SQL Server `drift-tool-mssql` (port **14330** → 1433) for `.bak` restore/compare |
| **sqlpackage** | `~/.dotnet/tools/sqlpackage` with `DOTNET_ROOT` `~/.dotnet-8027` (`config.sqlpackage_env()`) |
| **Python 3.12+** | `requirements.txt`: `flask`, `pymssql`, `sqlglot`; desktop adds system **PyGObject** (`python3-gi`) + **WebKit2 4.1** (`gir1.2-webkit2-4.1`). `run.sh`, the test command and `config.PYTHON_BIN` assume `python3.13` |

### 2.4 One-time environment (copy `.env.example` → `.env`)

| Variable | Required | Purpose |
|----------|----------|---------|
| `DRIFT_MSSQL_SA_PASSWORD` | Strongly recommended | SA password for scratch container; must match existing container or recreate with `docker rm -f drift-tool-mssql`. If unset, `config` generates a **random per-process** password (connections to an already-created container will fail with 18456) |
| `DEEPSEEK_API_KEY` | Optional | AI merge (`ai_merge.py`, model `deepseek-chat`) |
| `OPENROUTER_API_KEY` | Optional | AI triage (`ai.py`, fallback `MODEL_CHAIN`: `tencent/hy3:free` → `google/gemma-4-26b-a4b-it:free` → `google/gemma-4-31b-it:free` → `qwen/qwen3-coder:free`; first parseable answer wins) |
| `RUN_LIVE_DB=1` | Not in `.env.example`; export per shell | `executor.rehearse()` runs when `RUN_LIVE_DB` is any non-empty value (else returns `{"skipped": true}`); `test_bak_restore_inject.py` requires exactly `1` |

---

## 3. Operator guide — UI tools and workflows

The UI (`static/app.js`, `templates/index.html`) is organized into **three top-level tabs**. All tabs talk to the same Flask server.

### 3.1 Tab: **Trimmer**

**Purpose:** Paste **one** procedure body + **ClientActive** ID → see which branches run for that client and a reading-oriented trimmed view. **Does not** produce the apply script for a full compare run.

| Action | API |
|--------|-----|
| Trim pasted SQL | `POST /api/trim` body: `{ "definition", "client_active_id" }` → `{ ok, mode, trimmed_sql, harvest, unknown_kept, stats }`; **400** on empty definition or scope failure |

**Use when:** Inspecting a single proc outside a full run, or understanding gate structure before review.

**Validated by:** `tests/test_trimmer.py` (including `fixtures/procedures/OT_SendSalesmanData.sql`), `tests/test_nested_if_battery.py` (`fixtures/OT_NestedIfBattery_master.sql` / `_client.sql`).

### 3.2 Tab: **SQL Compare**

Sub-areas share one **`run_id`** when you run **Schema** compare; that `run_id` feeds the **Drift tool** tab.

#### 3.2.1 Schema (authoritative compare)

**Purpose:** Full master vs client compare from **`.bak`** files or **live** sides, both directions optional.

**Typical workflow:**

1. Pick **Master (105)** and **Client** backups (desktop picker, `/api/browse` under `work/`, or repo-wide `.bak` list `/api/backups`).
2. Set **ClientActive ID** (digits only; non-digits → **400**) — scopes procedure findings to this client.
3. Choose direction(s): **`client_to_105`** (what did the client change?) and/or **`105_to_client`** (what is the client missing?). Omitted → `["client_to_105"]`.
4. **Compare** → job streams on `GET /api/stream/<job_id>` (SSE events `log`, then `result` or `error`).
5. Review findings (rich diff, statements, callers, priority).
6. **Approve** rows that should ship (`POST .../review` with `state` ∈ `pending | approved | skipped | needs_review`, persisted into `index.json`).
7. Optional: **`POST .../classify_all`** → deterministic buckets (`irrelevant_to_client` / `cosmetic` / `gated_customization` / `small` / `major`); advisory only, never changes review state.
8. Optional: **`POST .../gate_wrap`** on `client_to_105` for `gated_customization` (deterministic splice; needs `client_active_id` on the run and a fresh in-memory run).
9. Optional: **`POST .../merge_propose`** / **`merge_accept`** per finding (DeepSeek) when gatewrap cannot parse structure. `merge_propose` is `client_to_105` only, for `modified` + `structural` + programmable findings, and needs `client_active_id` set on the run (`POST /api/run/<run_id>/client_active_id`).
10. **`POST .../apply`** or **`POST .../update_package`** → assembled SQL + manifest. Only `update_package` writes a ledger entry, and it assembles with `include_irrelevant=True` (approved `irrelevant_to_client` rows are **included**, unlike `/apply`). Only `/apply` writes `review_client_extras.sql` (client_to_105) and honors `include_deletions`.
11. **`POST .../rehearse`** with **`RUN_LIVE_DB=1`** → run the assembled script on a scratch restore of the **client** `.bak` only.
12. **`POST .../105_to_client/apply_start`** → interactive live apply to **client** only (after rehearsal discipline).

**Recompare without full restore:** `POST /api/run/<run_id>/recompare` body `{ "direction" }` (one direction per call) when `capture.json` and dacpacs still valid. Reuses the **same** `run_id`, reuses the original run’s `type_filter` (the HTTP route does not accept a new one), rewrites that direction’s `index.json` (**review states reset to pending**), and can add a direction the original run did not compute.

**Profiles:** `GET /api/profiles`, `POST /api/profiles` (`name` required; `master_path`, `client_path`, `client_active_id`, `master_live`, `client_live`), `DELETE /api/profiles/<name>`. A compare body with `profile` fills only fields the request left empty; unknown profile → **400**.

#### 3.2.2 Live scan (triage only)

**Purpose:** Fast catalog diff between **two live** SQL Server instances (object presence, module text, table columns). **No scripts.** Module flag **`livescan.SCAN_ONLY = True`**. SQL authentication only (no Windows auth from this Linux host); connects on the server’s default port, never the scratch `14330`.

| API | `POST /api/livescan` body `{ master: {server, database, user, password}, client: {…} }` → `{ scan_only, compare, summary, oversized_modules, module_text_warn }`. `compare` has `missing_in_b`, `extra_in_b`, `body_changed`, `columns.{added,removed,altered}` (a = master, b = client). Modules over 2 MiB are listed in `oversized_modules` |
|-----|----------------------|
| Also | `POST /api/live/databases` — list user databases (`database_id > 4`) on a server; connects to `master` when `database` is omitted; optional `port` |

**Rule:** Use livescan **before** applying to confirm live DB hasn’t moved since backup; **do not** treat it as release sign-off without the `.bak` pipeline.

#### 3.2.3 Data copy

**Purpose:** Diff and MERGE **config tables** with correct composite keys and quoting. Whitelist is `datacopy.WHITELIST_RE` — table names matching `menu|programs|messag|massag|page` (case-insensitive).

| API | Role |
|-----|------|
| `POST /api/datacopy/tables` | List whitelisted config tables on `source` |
| `POST /api/datacopy/preview` | Row-level diff plan per table (`insert` / `update` / `delete`; deletes only when `include_delete=true`) |
| `POST /api/datacopy/script` | Portable `.sql` text; with `run_id` also written to `work/output/<run_id>/package/datacopy.sql` |
| `POST /api/datacopy/apply` | Parameterized apply on `destination` (alias `client`), committed per table; optional `identity_cols` |

**Server-enforced guard:** every datacopy route requires `"dst_role": "client"` in the body, else **403** (master/105 is never a datacopy destination). Connections accept an optional `port`.

#### 3.2.4 Web pages

**Purpose:** File-tree manifest (SHA-256) for IIS-style deploy; robocopy script emission; optional copy that renames each overwritten file to a `<name>.bak_<epoch>` sidecar. Hidden entries and existing `*.bak_*` sidecars are ignored.

| API | Role |
|-----|------|
| `POST /api/webdeploy/preview` | Manifest diff → `{ manifest, copy_count, delete_count }` |
| `POST /api/webdeploy/script` | Robocopy script text |
| `POST /api/webdeploy/apply` | Copy with sidecar backups; deletes need `allow_delete=true` (otherwise reported as blocked) |

Body: `src_root`, `dst_root` — **both must resolve under `BACKUP_BROWSE_ROOT` (`work/`)**, else **400**. Arbitrary paths (e.g. a UNC share) are only usable through the Python API (`webdeploy.build_manifest` / `emit_robocopy` / `apply_copy`).

#### 3.2.5 Package

**Purpose:** Download **`GET /api/run/<run_id>/<direction>/package.zip`** — `105_to_client` only (**403** for `client_to_105`). Contains `add_update_on_client.sql`, `manifest.json`, and `datacopy.sql` (from the run’s `package/datacopy.sql`) when present; **400** if none exist. (The route also tries to add `TUTORIAL-snippet.md` from `apps/drift-tool/TUTORIAL.md`, which does not exist — the tutorial lives in `docs/` — so the snippet is currently never included.)

**Column backfill (D6):** On approved column findings, `POST .../backfill` body `{"finding_id", "backfill": {"Col": value}}` attaches the map (values stringified; persisted to `<direction>/apply/backfill.json`; needs a fresh in-memory run) → `scriptgen` emits typed `UPDATE ... WHERE col IS NULL` after `ADD`.

### 3.3 Tab: **Drift tool**

**Purpose:** Three **lenses** on **captured** `.master.sql` / `.client.sql` for a finding from an existing **`run_id`** (in-memory or disk). No second restore.

| Lens | Meaning |
|------|---------|
| `full` | Full definition diff (the only lens that works without `client_active_id`) |
| `active_read` | Both sides trimmed (`trimmer.trim_procedure`) to the client’s executable path |
| `active_plus_else` | Active path + each harvested **plain `ELSE`** arm appended as an executable `ELSE BEGIN … END` block. Other-client arms are **not** appended, and no `-- HARVEST` comment markers are emitted (asserted by `test_proc_lens.py`) |

| API | `POST /api/proc_lens` body: either `{ run_id, direction, finding_id, lens }` (defs read from the run’s `.master.sql` / `.client.sql`; `client_active_id` falls back to the run’s meta) or `{ left_def, right_def, lens, client_active_id }` (left = master, right = client). Returns `{ ok, identical, preview_left, preview_right, diff_unified, copy_sql, copy_kind, copy_side, warning }`; **400** for a non-`full` lens without `client_active_id` |

**Copy ALTER (clipboard):** Always intended for paste onto the **client** database. `105_to_client` copies master’s `CREATE OR ALTER`; `client_to_105` copies client definition. `copy_sql` is empty when the lensed previews are identical. Copy is always the **full** wanted-side definition, not the lensed preview. **Never** use Drift copy or apply to write **105**.

**Validated by:** `tests/test_proc_lens.py`, `tests/test_nested_if_battery.py`, `tests/test_compare_subtabs.py`.

### 3.4 End-to-end update diagram

```
pick master + client (.bak or live)
        │
        ▼
pipeline.run_compare ──► work/output/<run_id>/  (evidence on disk)
        │
        ▼
review + classify_all + (gate_wrap | merge) + approve
        │
        ▼
apply / update_package ──► apply/*.sql + manifest (+ ledger.jsonl on update_package only)
        │
        ▼
rehearse (RUN_LIVE_DB=1, client .bak only) ──► execution_report.json
        │
        ▼
human or apply_start (105_to_client, live client only)
```

---

## 4. Capability catalog (what each tool does)

### 4.1 Schema compare (pipeline + SqlPackage)

| Capability | Detail | Limits |
|------------|--------|--------|
| Object-level drift | DeployReport → roles: `added`, `modified`, `only_on_other` | Encrypted modules block report (SQL74502) unless excluded |
| Categories | `structural`, `documentation`, `cascading`, `formatting_only`, `no_difference` | Formatting-only found by the definition hash sweep, settings-only (ANSI_NULLS/QUOTED_IDENTIFIER) by the module-settings sweep — both outside DeployReport; `no_difference` is a demotion from `structural` in `pipeline._enrich` |
| Type filter | `type_filter` on `POST /api/compare`: list of `compare.TYPE_CATEGORIES` = `Procedures`, `Views`, `Functions`, `Triggers`, `Tables`, `Indexes`, `Constraints`, `Other` | Unknown category → HTTP 400. Filtered runs are marked partial in `meta.json`, `index.json` and `summary.md`. HTTP recompare reuses the original filter |
| Blast radius | `dependencies.get_callers` | Dynamic SQL under-reported |
| Attribution | `changelog` / ProcedureChangeLog | Missing log → informational only |
| Priority score | `report_writer._priority_score` → bucket `high` (≥20) / `medium` (≥10) / `low` | `priority_breakdown` in index for tooltips |

### 4.2 ClientActive scoping (`blocks.py`)

`blocks.resolve_scope(definition, client_active_id)` returns one of:

| Result | Meaning |
|--------|---------|
| `ok: true, mode: "structured"` | Full IF-chain parse; relevant-block SHA-256 fingerprint (16 hex chars) |
| `ok: true, mode: "heuristic"` | CURSOR procs or unrecognized vocabulary — exclusions trustworthy, `fingerprint: null`, equality never claimed. Only returned when at least one block is provably dead |
| `ok: false` (+ `reason`) | Nothing decidable (non-numeric id, no statement boundaries, unbalanced BEGIN/END, or heuristic with zero exclusions) — compare the whole definition. There is no separate `opaque` mode value |

When `client_active_id` set: `scope.irrelevant_to_client` is set only when **both** sides resolve `structured` and their fingerprints match (diff lives only in other clients’ branches) → excluded from `/apply` scripts by default.

### 4.3 Classification (`classify.py` — first match wins)

| Rule | Condition | Bucket / action |
|------|-----------|-----------------|
| **R1** | `scope.irrelevant_to_client is True` | `irrelevant_to_client` / skip (0.95) |
| **R2** | category in `formatting_only`, `no_difference`, `documentation` | `cosmetic` / skip (0.99) |
| **R3** | every non-equal alignment entry is an **added** branch whose client condition contains `@ClientActive` | `gated_customization` / gate_wrap (0.85) |
| **R4** | `change_kind == param` | `small` / apply_asis (0.8) |
| **R4b** | `change_kind == column` with added columns only (no removed/retyped) | `small` / apply_asis (0.8) |
| **R5** | `change_kind == body`, alignment present, ≤3 `changed`/`added` entries, no lost master line matching `RISK_RES` (WHERE, JOIN, TOP(, <=, >=, COMMIT, ROLLBACK, THROW, EXEC, INSERT INTO, UPDATE, DELETE) | `small` / apply_asis (0.7); risk hit → `major` / ai_merge (`R5_risk_demote`, 0.5) |
| **R6** | default | `major` / ai_merge (0.5) |

### 4.4 Gate wrap vs AI merge

| Path | When | Output |
|------|------|--------|
| `gatewrap.splice_up` | `client_to_105`, parseable gates (HTTP `gate_wrap`) | `.merged.sql` on disk |
| `gatewrap.preserve_down` | `105_to_client` | Master body + preserved client gates (library function; no HTTP route calls it) |
| `ai_merge.propose_merge` | major / unparsable, `client_to_105` only | DeepSeek draft (cached as `.merge_proposal.json`, `?refresh=1` to redo) → human **merge_accept** writes `.merged.sql` |

`.merged.sql` is only consumed by `scriptgen` for `client_to_105`, and only after the finding is approved and assembled.

### 4.5 Script generation (`scriptgen.py`)

| Emits | Skips / manual |
|-------|----------------|
| `CREATE OR ALTER` for programmable objects (with `SET ANSI_NULLS`/`QUOTED_IDENTIFIER` settings wrappers), `ALTER TABLE … ADD` for added columns, guarded UDTT `IF TYPE_ID(…) IS NULL EXEC(N'CREATE TYPE …')` | Column drop/retype, `only_on_other`, `irrelevant_to_client` (default; `update_package` passes `include_irrelevant=True`), modified UDTT, any other object type → `manual_review` |
| Added tables: `CREATE TABLE` + extras only when a complete `table_bundle` was captured | Otherwise manual_review |
| Backfill `UPDATE` after `ADD` when metadata + backfill map present | Values that cannot be quoted for the captured type → `manifest.backfill_warnings` (never guessed) |
| `DROP` for `only_on_other` programmable objects only with `include_deletions=True` (`POST .../apply` body) | DROP never default |

The script header sets `SET XACT_ABORT ON; SET NOCOUNT ON;` and each statement is preceded by `PRINT N'applying i/n'`. It is **not atomic** across `GO` batches.

### 4.6 Execution (`executor.py`)

| Mode | Behavior |
|------|----------|
| `rehearse(bak, batches, log)` | Restore client `.bak` into `zz_rehearsal_<epoch>` → `run_script` → drop DB in `finally`; returns `{"skipped": true}` unless `RUN_LIVE_DB` is set |
| `run_script(cur, statements)` | Runs each statement; **continues** past benign msgnos, **stops at the first fatal** (later statements never attempted) |
| `run_statement` / apply session | Classify errors by **msgno** (`ERROR_BY_MSGNO`): `dependent` (5074, 3725, 3726, 3729–3732), `truncation` (8152, 2628), `duplicate_key` (2601, 2627), `unique_index` (1505, 1507, 1913) = benign; any other SQL error = `fatal`; non-SQL exceptions = `python_error`. In the interactive apply session the operator decides (`skip`, `stop`, `bind_skip`, `bind_stop`) |

Batches are produced by splitting the assembled script on `\nGO`.

### 4.7 Livescan (`livescan.py`)

| Function | Role |
|----------|------|
| `connect(server, database, user, password)` | SQL auth; no port argument (default port, never 14330); `login_timeout=10`, `timeout=60` |
| `scan(cur)` | Takes a dict-row **cursor** (`conn.cursor(as_dict=True)`), not a connection → `{objects, columns, oversized_modules}` (user objects `is_ms_shipped = 0`, user-table columns) |
| `quick_compare(a, b)` | Deterministic sorted lists: `missing_in_b`, `extra_in_b`, `body_changed`, `columns.{added,removed,altered}`, `summary` counts |

**No** public function whose name contains `script`, `generate` or `emit` (enforced by `tests/test_livescan.py`, which also asserts `SCAN_ONLY is True`).

### 4.8 Datacopy / webdeploy / preflight

| Module | Role |
|--------|------|
| `datacopy` | Config table row hash diff, MERGE script (`emit_merge_script`), parameterized `apply_plan`, `SET IDENTITY_INSERT ON/OFF` pairs |
| `webdeploy` | SHA-256 directory manifest, robocopy script, `apply_copy` with `.bak_<epoch>` sidecars |
| `preflight` | Column-alter dependency teardown/rebuild plans (`find_column_dependencies`, `build_column_alter_plan`). **Library only:** not imported by `app.py`, `scriptgen` or any other engine module today; column drops/retypes still go to `manual_review` |

### 4.9 Ledger (`ledger.py`)

Append-only **`work/ledger.jsonl`** via `append_entry(client_id, run_id, kind, payload)`; **`read_entries(client_id=, kind=)`**, **`last_for_client`**. The module is designed for several kinds (apply manifest, execution report, webpage manifest), but the only writer wired today is **`POST .../update_package`** (`kind="update_package"`, `client_id` = run’s `client_active_id` or `"unset"`). `/apply`, `/rehearse`, `apply_start`, datacopy and webdeploy do **not** write ledger entries. File may be absent until first append; corrupt lines skipped on read.

### 4.10 Metrics (`metrics.py`)

`GET /api/run/<run_id>/metrics?seed=0&sample_size=40` — scorecard (coverage, noise separation, sampled accuracy, blast radius, attribution, runtime) computed on demand from on-disk index/meta/captures; **500** on computation failure.

---

## 5. Runtime and process architecture

```
olives-drift-tool.desktop
         │
         ▼
run-desktop.sh (.env) ──► desktop.py
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        GTK WebKit2    Flask app.py     .bak picker
              │         127.0.0.1:5057
              └───────────────┬───────────────┘
                              │
         ┌────────────────────▼────────────────────┐
         │ JOBS (SSE)  RUNS  APPLY_SESSIONS        │
         └────────────────────┬────────────────────┘
                              │
         ┌────────────────────▼────────────────────┐
         │ drift/pipeline.run_compare[_sides]       │
         │ docker_mgmt → restore → convert →       │
         │ extract → compare → enrich → reports    │
         └─────┬──────────────────┬────────────────┘
               │                  │
               ▼                  ▼
          sqlpackage          pymssql :14330
          (host subprocess)   drift-tool-mssql
```

**Scratch container** (`docker_mgmt.py`):

- Name `drift-tool-mssql`, image `mcr.microsoft.com/mssql/server:2022-latest`.
- `.bak` staged via **`docker cp`** (`restore.stage_bak_in_container`); optional RO mount `work/` → `/host`.
- `--cpuset-cpus 0,1` — visible CPU count matches allocation (avoids PARALLEL REDO stall).
- `DBCC TRACEON(3459,-1)` on startup — parallel redo disabled for RESTORE reliability.
- Mount path mismatch → container **recreate** (scratch data only).

**`RUNS` cache:** Full enriched findings (`master_def` / `client_def`) for runs finished **in this process**. `_load_run()` rebuilds from `meta.json` + `index.json` (with `findings = {}`) for display. Rich diff, statements, AI triage, `merge_propose` and `proc_lens` read on-disk `.master.sql` / `.client.sql` / `.columns.json` via `_finding_full`, so they work on reloaded runs. **`/apply`, `update_package`, `backfill` and `gate_wrap` require the in-memory findings** and return 400/404 on a reloaded run (“re-run the comparison”). `rehearse` and `apply_start` only need the assembled script on disk.

**Other in-memory state:** `JOBS` (SSE queues for compare / recompare / ai_batch) and `APPLY_SESSIONS` (open client connections for interactive apply) are lost on restart.

**Secrets in `meta.json`:** `password` is stripped from `master_side` / `client_side` before `meta.json` is written.

---

## 6. Repository layout

```
apps/drift-tool/
  app.py                 # Flask routes (47 route handlers)
  desktop.py             # GTK host
  run-desktop.sh         # Primary entry
  run.sh                 # Browser helper
  olives-drift-tool.desktop
  conftest.py            # pytest sys.path
  pytest.ini             # testpaths = tests, python_files = test_*.py
  requirements.txt       # flask, pymssql, sqlglot
  .env.example           # Template for secrets (gitignored .env)
  exclude-from-drift.txt # SqlPackage compare exclusions (glob patterns)
  drift-tool.svg         # Desktop entry icon
  drift/                 # Engine (no test_*.py)
  tests/                 # pytest suite (34 modules)
  static/, templates/    # UI (static/app.js, templates/index.html)
  fixtures/              # OT_NestedIfBattery_master.sql / _client.sql; procedures/OT_SendSalesmanData.sql
  ui_check.html          # Offline DOM harness for app.js (UBCHECK lines)
  venv_desktop/          # gitignored — preferred desktop interpreter
  docs/
    ARCHITECTURE.md      # This file
    TUTORIAL.md
    legacy/sql-compare/
  work/                  # gitignored — output/, ledger.jsonl, profiles.json
```

---

## 7. Schema compare pipeline (authoritative path)

**Orchestrator:** `drift/pipeline.py` — `run_compare`, `run_compare_sides`, `recompare`.

### 7.1 Inputs

| Mode | `kind` | Fields |
|------|--------|--------|
| Backup | `bak` | `path` to `.bak` |
| Live | `live` | `server`, `database`, `user`, `password` |

**Directions:** `client_to_105`, `105_to_client` (one or both; unknown values dropped, empty → `client_to_105`).

**Options:** `type_filter` (set of `compare.TYPE_CATEGORIES` names), `client_active_id` (numeric string).

### 7.2 Phases (recorded in `meta.timings`)

1. `docker_start` (only if any `.bak` side)
2. `restore` → `drift_master_<run_id>` / `drift_client_<run_id>` (bak sides only; the phase timing is recorded either way)
3. `script_to_sql` — full DDL scripts
4. `extract_dacpac`
5. `hash_sweep` — formatting-only, settings-only, encrypted warnings
6. `compare` — per direction DeployReport
7. `capture_definitions` — definitions, columns, extended metadata
8. `blast_radius` — callers
9. `attribution` — ProcedureChangeLog / lost-fix hints
10. `write_reports` — workspace folders + `index.json`
11. `persist_capture` — `capture.json`
12. `teardown` — drop scratch DBs (bak sides)

`meta.timings.total` holds the whole run.

**Run id:** `{unix_ts}_{uuid6}` under `work/output/<run_id>/`.

### 7.3 Recompare guards

- Missing `capture.json` or `bak_cache_key` → error (run full compare).
- `.bak` missing, or size/mtime changed vs `bak_cache_key` → error (stale cache).
- Cached `master.dacpac` / `client.dacpac` missing → error.
- Live sides trust cached dacpacs.
- Output: `diff_<direction>_recompare.xml`, rewritten `<direction>/index.json`, and a `meta.recompares[]` entry `{direction, seconds}`.

### 7.4 SqlPackage profile (`config.COMPARE_PROFILE`)

Ignores whitespace/comments/keyword casing/semicolon-between-statements; **does not** ignore permissions, extended properties, role membership or column order; `DropObjectsNotInSource=true`; `AllowIncompatiblePlatform=true`; `ExcludeObjectTypes=Users`.

---

## 8. Engine modules reference

| Module | Responsibility |
|--------|----------------|
| `pipeline` | End-to-end compare, enrich, recompare |
| `compare` | SqlPackage DeployReport, exclusions, type categories |
| `diffing` | Normalization, programmable/column/settings diff |
| `diff_render` | Rich diff for UI |
| `statements` | Statement segmentation and alignment |
| `blocks` | ClientActive parse, scope, fingerprints |
| `classify` | R1–R6 ladder |
| `gatewrap` | Deterministic two-direction splice |
| `scriptgen` | Approved-only apply script |
| `executor` | Statement runner, rehearsal, msgno classification |
| `trimmer` | Single-proc trim API |
| `proc_lens` | Lenses on captured defs |
| `restore`, `convert`, `extract`, `docker_mgmt` | Scratch DB lifecycle |
| `inspect_objects`, `dependencies`, `changelog` | Catalog and attribution |
| `report_writer` | Folder tree + priority |
| `metrics` | Run scorecard |
| `ledger`, `profiles` | Audit + bookmarks |
| `ai`, `ai_merge`, `ai_common` | Advisory AI |
| `apply_session` | Interactive live apply state machine |
| `livescan`, `datacopy`, `webdeploy` | Auxiliary libraries (+ HTTP in `app.py`) |
| `preflight` | Auxiliary library, no HTTP route and not wired into `scriptgen` |
| `prepare_bench` | **Dev only:** builds `work/bench` ground-truth pair on scratch SQL |

---

## 9. HTTP API reference

Base URL: `http://127.0.0.1:5057` for both desktop and `python3.13 app.py` (Flask binds **127.0.0.1** only, never `0.0.0.0`). 47 route handlers, as implemented in `app.py`:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | UI shell (renders `index.html` with backups + `TYPE_CATEGORIES`) |
| GET | `/api/backups` | Discover `*.bak` anywhere under the monorepo root (`REPO_ROOT`, skips `.git`) |
| GET | `/api/browse?path=` | Directory listing jailed under `BACKUP_BROWSE_ROOT` (`work/`); hides dotfiles, `__pycache__`, `node_modules`; **400** outside root |
| GET | `/api/runs` | List runs from `OUTPUT_DIR` (newest first, with counts) |
| POST | `/api/compare` | Start compare job → `{ job_id }` |
| GET | `/api/stream/<job_id>` | SSE stream: `log` events, then `result` or `error`; **404** unknown job |
| GET | `/api/run/<run_id>` | Run meta + workspace indexes (works after restart) |
| GET | `/api/run/<run_id>/file?path=` | Serve a text artifact confined to the run dir; `optional=1` → **204** if missing |
| POST | `/api/run/<run_id>/recompare` | Fast recompare of one `direction` → `{ job_id }` (SSE) |
| GET | `/api/run/<run_id>/<dir>/richdiff/<finding_id>` | Rich diff payload |
| GET | `/api/run/<run_id>/<dir>/statements/<finding_id>` | Statement alignment |
| POST | `/api/run/<run_id>/<dir>/review` | Set review state (`pending`, `approved`, `skipped`, `needs_review`) |
| POST | `/api/run/<run_id>/<dir>/backfill` | Attach column backfill map (fresh run only) |
| POST | `/api/run/<run_id>/<dir>/apply` | Assemble apply script from approved rows (fresh run only; optional `include_deletions`) |
| POST | `/api/run/<run_id>/<dir>/classify_all` | Classify all findings; persists `classification` + `classification_counts` into `index.json` |
| POST | `/api/run/<run_id>/<dir>/gate_wrap` | Deterministic gate wrap (`client_to_105` only; needs `client_active_id`) |
| POST | `/api/run/<run_id>/<dir>/update_package` | Assemble + ledger entry → `{ script, manifest, script_name, ledger_entry }` (fresh run only) |
| POST | `/api/run/<run_id>/<dir>/rehearse` | Scratch rehearsal (`RUN_LIVE_DB`) → execution report + `verification` |
| POST | `/api/run/<run_id>/<dir>/apply_start` | Interactive apply to live client (`105_to_client` only) |
| POST | `/api/apply_session/<session_id>/decide` | `action` ∈ `skip`, `stop`, `bind_skip`, `bind_stop` (+ optional integer `msgno`) |
| POST | `/api/run/<run_id>/client_active_id` | Set scoping id on run (persisted to `meta.json`) |
| POST | `/api/run/<run_id>/<dir>/merge_propose/<finding_id>` | AI merge draft (`client_to_105` only; cached; `?refresh=1`) |
| POST | `/api/run/<run_id>/<dir>/merge_accept/<finding_id>` | Save `merged_def` as `.merged.sql` |
| POST | `/api/diff_preview` | Ad-hoc diff render of `left` / `right` (`view` = `split` default or `unified`) |
| GET | `/api/ai/test` | OpenRouter key + model chain smoke test |
| GET | `/api/ai_merge/test` | DeepSeek key smoke test |
| POST | `/api/run/<run_id>/<dir>/ai/<finding_id>` | AI triage one finding (cached `.ai.json`; `?refresh=1`, `?peek=1`) |
| POST | `/api/run/<run_id>/<dir>/ai_batch` | Batch triage of `finding_ids` (max **25**, `AI_BATCH_CAP`) → `{ job_id }` (SSE) |
| GET | `/api/run/<run_id>/metrics` | Metrics scorecard (`seed`, `sample_size`) |
| GET | `/api/download/<run_id>/<artifact>` | Download a `meta.artifacts` entry (`sql_master`, `sql_client`, `dacpac_master`, `dacpac_client`) |
| GET | `/api/run/<run_id>/<dir>/package.zip` | Zip bundle (`105_to_client` only) |
| GET | `/api/profiles` | List saved profiles |
| POST | `/api/profiles` | Save/update one profile |
| DELETE | `/api/profiles/<name>` | Delete profile (**404** if absent) |
| POST | `/api/live/databases` | List databases (live) |
| POST | `/api/livescan` | Quick compare two live sides |
| POST | `/api/trim` | Trimmer |
| POST | `/api/proc_lens` | Drift lenses |
| POST | `/api/datacopy/tables`, `/preview`, `/script`, `/apply` | Config data copy (4 routes; `dst_role: "client"` required) |
| POST | `/api/webdeploy/preview`, `/script`, `/apply` | Static site deploy (3 routes; roots under `work/`) |
| GET | `/api/desktop/chooser` | `{ ok }` — whether a native picker is registered |
| GET/POST | `/api/desktop/open_bak` | Native file chooser → `{ ok, path }`; **501** outside desktop, **400** on cancel |

**Compare body (summary):** `master`, `client` (paths) **or** `master_side`/`client_side` with `kind` (`bak` + `path`, or `live` + `server`, `database`, `user`, `password`); `directions[]`; optional `profile`, `type_filter`, `client_active_id`. Passwords are stripped from the persisted `meta.json`.

**Status codes that encode safety rules:** `apply_start` **403** for `client_to_105` and **403** when the client connection (server, port, database) matches a live master side; `package.zip` **403** for `client_to_105`; datacopy **403** without `dst_role: "client"`. `apply_start` also accepts `X-Batch: 1` (auto-stop on the first error that needs a decision) and an optional `client.port` (e.g. scratch `14330`).

---

## 10. Safety model

1. **`only_on_other` never scripted** by default (would imply DROP on target); only `/apply` with `include_deletions=true` emits DROPs.
2. **105 never interactive-apply target** — `apply_start` forbidden (403) for `client_to_105`, and for a client connection that matches the live master.
3. **Rehearsal** uses client `.bak` only (400 for a live client); scratch DB always dropped.
4. **Livescan** cannot emit apply SQL (`SCAN_ONLY`).
5. **AI** never auto-approves; keys server-side only.
6. **`review_client_extras.sql`** (written by `/apply` for client_to_105) starts with a `-- REVIEW ONLY` header.
7. **Webdeploy deletes** require explicit `allow_delete=True`; webdeploy roots are jailed under `work/`.
8. **Datacopy** refuses (403) any destination role other than `client`.
9. **Executor** benign msgnos logged, not hidden.
10. **Loopback only:** Flask binds `127.0.0.1`.

---

## 11. Configuration and secrets

**Single source:** `drift/config.py`.

| Symbol | Value |
|--------|-------|
| `ROOT` | `apps/drift-tool/` |
| `REPO_ROOT` | Monorepo root |
| `WORK_DIR` / `OUTPUT_DIR` | `work/`, `work/output/` |
| `EXCLUDE_FILE` | `exclude-from-drift.txt` |
| `CONTAINER_NAME` | `drift-tool-mssql` |
| `CONTAINER_IMAGE` | `mcr.microsoft.com/mssql/server:2022-latest` |
| `HOST_PORT` | `14330` |
| `SA_USER` / `SA_PASSWORD` | `sa` / from `DRIFT_MSSQL_SA_PASSWORD` (random per process if unset) |
| `HOST_MOUNT_SRC` → `CONTAINER_MOUNT_DST` | `work/` → `/host` (read-only) |
| `BACKUP_BROWSE_ROOT` | `work/` (browse + webdeploy jail) |
| `SQLPACKAGE_BIN` / `DOTNET_ROOT_FOR_SQLPACKAGE` | `~/.dotnet/tools/sqlpackage` / `~/.dotnet-8027` |
| `PYTHON_BIN` | `python3.13` |
| `OPENROUTER_BASE` / `OPENROUTER_MODEL` | `https://openrouter.ai/api/v1` / `qwen/qwen3-coder:free` (last entry of `ai.MODEL_CHAIN`) |
| `DEEPSEEK_BASE` / `DEEPSEEK_MODEL` | `https://api.deepseek.com` / `deepseek-chat` |

Importing `config` creates `work/` and `work/output/` if missing.

Secrets **only** from environment (also loadable via `.env` in desktop launcher):

- `DRIFT_MSSQL_SA_PASSWORD`
- `DEEPSEEK_API_KEY`
- `OPENROUTER_API_KEY`

---

## 12. On-disk artifacts and data contracts

### 12.1 Per-run (`work/output/<run_id>/`)

| File / dir | Content |
|------------|---------|
| `meta.json` | Sides (passwords stripped), directions, timings, `artifacts`, `bak_cache_key`, `type_filter`, `client_active_id`, encrypted objects, db options, dependency coverage, `recompares[]` |
| `master.dacpac`, `client.dacpac` | Extracted models (recompare cache) |
| `master__<name>.sql`, `client__<name>.sql` | Full DDL scripts |
| `diff_<direction>.xml`, `diff_<direction>_recompare.xml` | Raw DeployReport (initial / recompare) |
| `capture.json` | Recompare cache |
| `package/datacopy.sql` | Written by `POST /api/datacopy/script` when `run_id` is given; bundled into `package.zip` |
| `<direction>/index.json` | Finding index + review + classification (`classification_counts` after `classify_all`) |
| `<direction>/summary.md` | Human summary (partial-run banner when type-filtered) |
| `<direction>/01_added/`, `02_modified/`, `03_only_on_other/`, `04_formatting/`, `05_no_difference/` | Per-finding artifacts, each under a type subfolder: `procedures/`, `tables/`, `views/`, `functions/`, `triggers/`, `other/` |
| per finding `<safe_name>.*` | `.md`, `.diff`, `.master.sql`, `.client.sql`, `.columns.json`, `.statements.json` (as captured); later sidecars `.ai.json`, `.merge_proposal.json`, `.merged.sql` |
| `<direction>/apply/` | `add_update_on_105.sql` (client_to_105) or `add_update_on_client.sql` (105_to_client), `manifest.json`, `review_client_extras.sql` (client_to_105, `/apply` only), `backfill.json`, `execution_report.json` (after rehearse) |

Folder names come from `report_writer.write_workspace`; formatting-only and no-difference findings go to `04_`/`05_` regardless of role.

### 12.2 Global work files

| File | Purpose |
|------|---------|
| `work/ledger.jsonl` | Update-package audit trail (created on first `update_package`) |
| `work/profiles.json` | Named compare bookmarks (created on first save) |
| `~/.drift-tool-desktop.log` | Desktop host log (outside the repo) |

---

## 13. Validation program — how we know it works

**Command:** from `apps/drift-tool/`:

```bash
python3.13 -m pytest -q
```

**Layout:** `tests/test_*.py` (34 files), `conftest.py` adds the app root (`apps/drift-tool/`) + `drift/` to `sys.path`. **Hermetic default:** mocks/fakes; **integration** gated on `RUN_LIVE_DB=1`. Hermetic baseline: **335 passed, 1 skipped** (the skip is `test_bak_restore_inject.py`).

### 13.1 Validation matrix (capability → tests)

| Capability | Test module(s) | What is proven |
|------------|----------------|----------------|
| DeployReport parse, type filter, formatting/settings sweep | `test_compare.py` | XML roles, `passes_type_filter`, `find_formatting_only` |
| SqlPackage compare integration | `test_pipeline.py`, `test_bak_restore_inject.py` (live) | Enrich demotions, recompare guards, scope annotation |
| Programmable/column diff | `test_diffing.py` | param/body/settings; string literal edge cases |
| Rich diff UI payloads | `test_diff_render.py` | Collapse, word highlight, column grid |
| Statement alignment | `test_statements.py` | Segmentation contract |
| ClientActive blocks & scope | `test_blocks.py` | Conditions, irrelevant_to_client, heuristic tier |
| Nested IF battery | `test_nested_if_battery.py` | Fixture E2E through trimmer, diffing, proc_lens, Flask |
| Classify R1–R6 (+R4b) | `test_classify.py` | Rule order, RISK demotion, gated branch detection |
| Gate wrap directions | `test_gatewrap.py` | splice_up / preserve_down disaster guards |
| Scriptgen safety & D6 | `test_scriptgen.py` | No DROP default, backfill quoting, UDTT, scope skip |
| Executor msgno & rehearsal gate | `test_executor.py` | Benign classes; `RUN_LIVE_DB` docker guard |
| Apply session FSM | `test_apply_session.py` | Interactive decisions |
| Flask interactive apply API | `test_apply_api.py` | `apply_start` 403 for client_to_105 and client==master (incl. localhost aliases), `bind_skip` prompt flow, `X-Batch: 1` stop |
| Compare UI subtabs + guarded routes | `test_compare_subtabs.py` | Index markup/tab titles, desktop picker registration, backfill→assemble, backfill 400 on reloaded run, datacopy 403, `package.zip` 403/200, webdeploy path escape |
| Live compare API | `test_compare_live_api.py`, `test_extract_live.py`, `test_live_picker.py` | Live sides accepted without `.bak`, password redaction in `meta.json`, `review_client_extras.sql`, live extract uses caller server (not 14330), `/api/live/databases` |
| Trimmer + API | `test_trimmer.py` | `OT_SendSalesmanData` fixture, `/api/trim` |
| Proc lenses | `test_proc_lens.py` | Lenses, `ELSE` harvest append without `-- HARVEST` markers, copy SQL direction rules |
| Livescan triage-only | `test_livescan.py` | `SCAN_ONLY`, no script generators, quick_compare |
| Datacopy | `test_datacopy.py` | Keys, quoting, identity_insert |
| Webdeploy | `test_webdeploy.py` | Manifest, delete guard |
| Preflight | `test_preflight.py` | Column dependency plans (fake cursor) |
| Ledger durability | `test_ledger.py` | Append, corrupt line skip |
| Profiles | `test_profiles.py` | Save/load corruption tolerance |
| Report writer / priority | `test_report_writer.py` | Priority signal weights and `high`/`medium`/`low` bucket thresholds (folder layout itself is not asserted here) |
| Metrics | `test_metrics.py` | Scorecard from disk |
| Changelog attribution | `test_changelog.py` | Lost-fix detection logic |
| AI triage | `test_ai.py`, `test_ai_common.py` | Parsing boundaries |
| AI merge | `test_ai_merge.py` | Prompt, retries, no-key path |
| Restore docker cp | `test_restore_copy.py` | Restore stages via `docker cp`, not the browse-root mount |
| Inspect objects | `test_inspect_objects.py` | Parameterized name batches (1000/execute), `build_table_bundle` (PK, extras, dangling FK) |
| UI offline harness | `ui_check.html` (manual, not collected by pytest) | `app.js` DOM stubs; results in `#ubcheck` and page title `UBCHECK PASSED` / `UBCHECK FAILED` |

### 13.2 Live / bench tiers (optional)

| Tier | How to run | Ground truth |
|------|------------|--------------|
| Scratch integration | `RUN_LIVE_DB=1 python3.13 -m pytest tests/test_bak_restore_inject.py` | Hard-coded `BAK_PATH = /media/alaa/data/olives_pos/Olives_BO.bak`; skipped unless `RUN_LIVE_DB` is exactly `1` |
| Bench pair | `python3.13 drift/prepare_bench.py` | Plants P1–P5 scenarios; prints expected buckets |
| Fixtures | `fixtures/OT_NestedIfBattery_master.sql` / `_client.sql`, `fixtures/procedures/OT_SendSalesmanData.sql` | Deterministic proc gate matrix; real 769 KB proc for trimmer |

### 13.3 What is **not** fully automated

- Full 4-minute compare against every client `.bak` in the field (too heavy for CI).
- SqlPackage version upgrades (profile pinned; re-validate on toolchain bump).
- Desktop GTK/WebKit input (manual smoke via `run-desktop.sh`).
- OpenRouter/DeepSeek model behavior (tests mock HTTP; live keys optional).

---

## 14. Troubleshooting

| Symptom | Action |
|---------|--------|
| SQL login 18456 to scratch | Set `DRIFT_MSSQL_SA_PASSWORD` to match container or `docker rm -f drift-tool-mssql` |
| Cannot read `.bak` | `chmod 644` on file; or use desktop picker / docker cp path |
| Apply / update_package / backfill / gate_wrap refused after restart | Re-run compare (in-memory `findings` cache cold) |
| Review states reset to pending | `recompare` (manual or the auto re-verify inside `update_package` / `rehearse`) rewrites `index.json`; re-approve |
| Rehearse 400 live client | Rehearse needs client `.bak` path in `meta.bak_cache_key` |
| Rehearse 400 “assemble an apply script first” | Run `/apply` or `update_package` first |
| Rehearse skipped | Export `RUN_LIVE_DB=1` |
| Encrypted proc blocks compare | Add to `exclude-from-drift.txt` or decrypt |
| `verification.error` in rehearse response | Post-rehearsal recompare failed; the execution report is still valid. (`update_package` also re-verifies, but its response does **not** include `verification`) |
| Web pages 400 “outside the configured browse root” | `src_root` / `dst_root` must be under `work/` for the HTTP API |
| Datacopy 403 | Send `"dst_role": "client"` |
| Desktop picker 501 | Running via browser, not `run-desktop.sh`; use `/api/browse` |
| AI features disabled | Set `DEEPSEEK_API_KEY` / `OPENROUTER_API_KEY` |

---

## 15. Legacy and boundaries

- **`docs/legacy/sql-compare/`** — reverse-engineering notes for the old Windows tool; informs design history, not runtime behavior.
- **`prepare_bench.py`** — developer harness, not invoked from Flask.
- **Monorepo plans** under `docs/superpowers/` and `knowledge/planning/` — historical; superseded by this document for drift-tool behavior.

---

*Audited 2026-09-25 against: `app.py` (47 routes), `desktop.py`, `run-desktop.sh`, `run.sh`, `drift/config.py`, `drift/pipeline.py`, `drift/report_writer.py`, `drift/compare.py`, `drift/classify.py`, `drift/scriptgen.py`, `drift/executor.py`, `drift/livescan.py`, `drift/proc_lens.py`, `drift/blocks.py`, `drift/datacopy.py`, `drift/webdeploy.py`, `drift/ledger.py`, and all 34 `tests/test_*.py` (335 passed, 1 skipped).*
