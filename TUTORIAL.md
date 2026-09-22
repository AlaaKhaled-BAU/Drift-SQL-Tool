# drift-tool — Update Engineer's Tutorial

Ship an Olives BO update from 105 to a client without breaking their customizations.

**UI tools (three tabs):**

| Tab | Purpose | HTTP |
|---|---|---|
| **Trimmer** | Paste one proc + ClientActive → reading view (runtime path + harvest list). Not the copy payload. | `POST /api/trim` |
| **SQL Compare** | Sub-tabs: **Schema** (`.bak` compare, backfill, assemble/rehearse/apply), **Live scan** (`SCAN_ONLY`), **Data copy** (`dst_role: client` only), **Web pages**, **Package** (profiles + `package.zip`). One `run_id` on Schema feeds Drift. | `/api/compare`, `/api/livescan`, `/api/datacopy/*`, `/api/webdeploy/*`, `/api/run/.../backfill`, `/api/run/.../package.zip` |
| **Drift tool** | Same `run_id` as Compare — three lenses on captured `.master.sql` / `.client.sql`. Preview in UI; **Copy ALTER** goes to the clipboard. | `POST /api/proc_lens` |

**Drift lenses** (`lens` on `/api/proc_lens`): `full` | `active_read` | `active_plus_else`. Radios transform captured text in memory only (no second restore, no live scan).

**Copy ALTER (client only):** Always paste onto the **client** database. `105_to_client` puts the master’s `CREATE OR ALTER` on the clipboard (push 105’s version to the client). `client_to_105` copies the client’s captured definition. `active_plus_else` may append commented `-- HARVEST` blocks for ELSE/other-client arms — still client-targeted paste. **Never write 105** from Drift copy or from apply.

Live scan never drives Drift lenses or SQL Compare apply; run a `.bak` compare first for procedure drift.

**Interactive apply:** Rehearse first (`POST .../rehearse`). Then **Apply to client (interactive)** on **105 → Client** calls:

```text
POST /api/run/<run_id>/105_to_client/apply_start   → { session_id, waiting, done, report }
POST /api/apply_session/<session_id>/decide      → { action, msgno }  (skip | stop | bind_skip | bind_stop)
```

`apply_start` is **403** for `client_to_105`. Optional `client.port` reaches scratch MSSQL (`14330`). `X-Batch: 1` stops on the first SQL error. Rehearsal still uses `executor.run_script` (continues past historically “benign” msgnos).

**D6:** added-column `ALTER TABLE` / backfill `UPDATE` / UDTT `TYPE_ID` use `[schema].[name]` from the finding, not a hard-coded `[dbo]`.

```
pick client.bak + 105.bak ──► detect every difference ──► scope to THIS client
        │                                                        │
        ▼                                                        ▼
classify ──► review (exact diffs) ──► approve ──► package ──► rehearse ──► apply
                                                                      │
                                            auto re-verify + ledger + webpage deploy
```

---

## 1. One-time setup

| Need | Check |
|---|---|
| Docker + MSSQL 2022 image | `docker ps` — tool creates `drift-tool-mssql` itself |
| sqlpackage | `~/.dotnet/tools/sqlpackage` (config.py points here) |
| Python deps | `pymssql`, `flask`, `pywebview` (desktop), `sqlglot` |
| DeepSeek key (AI merge, optional) | paste into `work/.deepseek_key` (gitignored) |

Start it:
```bash
cd apps/drift-tool && ./run-desktop.sh    # desktop window
# or: python3.13 app.py                     # browser at http://127.0.0.1:5057
```

## 2. Compare a client to 105

1. **Pick backups**: Master = `105/olives_bo.bak`, Client = `<client>/Olives_BO.bak` (Browse buttons navigate your disks). Or use a saved profile (§5).
2. **Run** direction *Client → 105* (what did the client change?) and/or *105 → Client* (what is the client missing?).
3. Wait ~4 min for full DBs (restore → extract → compare). Progress streams live.
4. Review findings — each has exact diff, blast radius (callers), priority score.
   Buckets: structural / formatting-only / documentation / cascading / excluded — nothing hidden, noise just separated.
5. **Approve** what should ship, then **Apply** → an add/update-only script (`CREATE OR ALTER`, additive columns; deletions opt-in, off by default).

## 3. ClientActive scoping (the killer feature)

Set the run's **ClientActive ID** once (prompted on first use, via §4 API, or stored in a profile).
Every procedure gets scoped to what THIS client actually executes:

- Branches gated to other clients (`IF @ClientActive = 165 ...`) are marked dead for your client.
- A finding whose ONLY differences live in dead branches is flagged **irrelevant_to_client** — real drift, not this client's problem (excluded from scripts by default).
- Mixed changes stay honestly relevant (never over-claims).

Engine tiers in logs: `structured` (full proof), `heuristic` (CURSOR procs — exclusions trustworthy, equality never claimed), `opaque` (compare whole thing).

## 4. The update pipeline (API)

```bash
BASE=http://127.0.0.1:5000/api/run/<RUN_ID>/client_to_105

# 1. Classify everything deterministically -> buckets small/gated_customization/major/cosmetic
curl -X POST $BASE/classify_all

# 2. Fold gated customizations into 105 behind their gate (deterministic splice;
#    output lands as .merged.sql -- the SAME artifact Apply consumes as AI merges)
curl -X POST $BASE/gate_wrap

# 3. Approve in the UI (bucket Select-All helps; see §6), then build package + ledger entry
curl -X POST $BASE/update_package
# -> apply/add_update_on_105.sql + manifest.json + ledger entry
#    response also carries "verification": {residue_counts}   <- auto re-compare proof

# 4. REHEARSE against a scratch restore of the CLIENT's own backup:
RUN_LIVE_DB=1 curl -X POST $BASE/rehearse     # scratch DB always dropped; response carries verification too
```

Then a human runs the approved script on the real target (SSMS/sqlcmd). The tool never touches production directly.
Note: `update_package`/rehearse need the run still in memory (fresh compare); a reloaded old run refuses politely instead of building an empty script.

## 5. Column alters, backfills, UDTTs (the boring job)

- **Additive columns**: generated automatically.
- **Backfill values**: attach `{"backfill": {"ColumnName": "value"}}` to an approved column finding and the script gains `UPDATE [T] SET [Col]=<typed literal> WHERE [Col] IS NULL` right after the ADD. Quoting follows the captured type (numbers raw, strings doubled-quote, datetimes quoted); unknown types become manifest warnings, never guessed SQL.
- **Retypes/drops**: **preflight plan** — dependent indexes/constraints/stats dropped and recreated VERBATIM around the ALTER, killing classic "dependent object" errors instead of skipping them. Missing detail → warnings, never guesses.
- **New table types (UDTT)**: added UDTTs emit guarded `IF TYPE_ID(...) IS NULL EXEC('CREATE TYPE ...')`; modified UDTTs stay manual (dependents must drop first).

## 6. What you'll see in the UI

| Feature | Behavior |
|---|---|
| Scope badge | gray-green pill on rows whose diffs live only in other clients' branches |
| Classification chips | colored by bucket after classify_all (small=green, gated=blue, major=orange), tooltip shows rule+confidence |
| Approved highlight | salmon rows = what will ship |
| Bucket Select All / None | approves/pends the currently filtered set — cosmetic & irrelevant rows are protected from mass actions |
| Error counters panel | appears once an execution report exists: ok / benign-skipped / fatal, per-statement messages |
| Filter persistence | your filters + page survive reloads |

## 7. Quick-scan a LIVE server pair (seconds, triage only)

```python
from drift import livescan
a = livescan.scan(livescan.connect("10.0.10.105", "Olives_Images", "cds", input("pwd: ")))
b = livescan.scan(livescan.connect("CLIENTSERVER", "Olives_Images_AlMalaki", "user", "pwd"))
r = livescan.quick_compare(a, b)
print(r["summary"])    # missing_in_b / extra_in_b / body_changed / column drift
```
Triage routing ONLY — the scan module physically cannot emit scripts; deep verification stays with the .bak pipeline. Use it right before applying to confirm the live DB hasn't drifted since the backup was cut.

## 8. Sync config tables (menus/pages/messages) safely

```python
from drift import datacopy
tables = datacopy.list_config_tables(cur_src)            # menu|Programs|Messag(e)|Page whitelist
keys   = datacopy.get_key_columns(cur_src, "OlivesMenu")
plan   = datacopy.diff_tables(datacopy.fetch_rows_hashed(cur_src, "OlivesMenu", keys),
                              datacopy.fetch_rows_hashed(cur_dst, "OlivesMenu", keys))
sql    = datacopy.emit_merge_script("OlivesMenu", cols, keys, plan)   # portable artifact
rep    = datacopy.apply_plan(cur_dst, "OlivesMenu", keys, plan)       # parameterized path
```
Composite keys correct (the old tool's mass-update bug is dead); apostrophes survive ('' doubled, never stripped); identity columns wrapped in IDENTITY_INSERT pairs. Always read the emitted .sql before running it anywhere.

## 9. Webpages deploy

```python
from drift import webdeploy
from pathlib import Path

m = webdeploy.build_manifest(Path("olives web pages/Olives"), Path("/mnt/client/www/Olives"))
print(webdeploy.emit_robocopy(m, Path("olives web pages/Olives"), Path(r"\\client\www\Olives")))
print(webdeploy.apply_copy(m, Path("olives web pages/Olives"), Path("./staging"), allow_delete=False))
```
Old files kept as `.bak_<timestamp>` sidecars; deletes require explicit `allow_delete=True`.

## 10. Audit trail + profiles ("what did we apply on client X?")

```python
from drift import ledger
ledger.read_entries(client_id="66")     # every package ever shipped
ledger.last_for_client("66")            # latest baseline
```

Profiles remember a client's setup:
```bash
curl -X POST :5000/api/profiles -d '{"name":"almalak","master_path":"/…/105.bak",
        "client_path":"/…/al.bak","client_active_id":"66"}'
curl -X POST :5000/api/run -d '{"profile":"almalak","directions":["client_to_105"]}'
curl -X DELETE :5000/api/profiles/almalak
```

## 11. Safety rules (why you can trust it)

- Detection is deterministic (sqlpackage parsed model + difflib) — validated 100% on ground-truth batteries; AI NEVER decides what differs.
- AI/gate-wrap merges are proposals: human Accept required, diff shown alongside.
- No DROP enters an apply script by default; deletions double-opt-in everywhere (DDL, data, webfiles).
- Rehearsal touches only a throwaway restore of the client's own backup; always dropped.
- Every package lands in the ledger; every execution produces a signed-off-able report.

## 12. Troubleshooting

| Symptom | Fix |
|---|---|
| "Access is denied" reading a .bak | `chmod 644 <file>.bak` (container user reads it through the mount) |
| Backup/restore writes fail | `/host` mount is read-only BY DESIGN — write inside container then `docker cp` out |
| SQL Server login failed (18456) | stale container with old password: `docker rm -f drift-tool-mssql` and rerun |
| Apply/package disabled ("reloaded from a prior session") | run lost its in-memory evidence after restart — re-run the comparison |
| Encrypted procs error (SQL74502) | one encrypted proc blocks reports when it DIFFERS — exclude or decrypt it |
| "no ProcedureChangeLog" | informational — attribution unavailable for that side, detection unaffected |
| verification.error in update_package/rehearse response | recompare couldn't run for that run (e.g., dacpacs cleaned) — package artifacts are safe; re-run compare if you need residue proof |

---

*Full design + validation history: PLAN.md, PLAN-V3–V5, VALIDATION.md, and `SQL Compare/Drift_Tools_Comparison_and_Ultimate_Blueprint.md` in this folder.*
