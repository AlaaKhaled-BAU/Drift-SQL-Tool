# drift-tool — Update Engineer's Tutorial

Ship an Olives BO update from 105 to a client without breaking their customizations.

```
pick client.bak + 105.bak ──► detect every difference ──► scope to THIS client
        │                                                        │
        ▼                                                        ▼
review findings (exact diffs) ──► approve ──► update script ──► rehearse ──► apply
                                                                      │
                                                        ledger entry + webpage deploy
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
cd apps/drift-tool && python3.13 desktop.py    # desktop window
# or: python3.13 app.py                        # browser at http://127.0.0.1:5000
```

## 2. Basic flow — compare a client to 105

1. **Pick backups**: Master = `105/olives_bo.bak`, Client = `<client>/Olives_BO.bak` (Browse buttons navigate your disks).
2. **Run** direction *Client → 105* (what did the client change?) and/or *105 → Client* (what is the client missing?).
3. Wait ~4 min for full DBs (restore → extract → compare). Progress streams live.
4. Review findings — each has exact diff, blast radius (callers), priority score.
   Buckets: structural / formatting-only / documentation / cascading / excluded — nothing hidden, noise just separated.
5. **Approve** what should ship, then **Apply** → generates an add/update-only script (`CREATE OR ALTER`, additive columns; deletions opt-in, off by default).

## 3. ClientActive scoping (the killer feature)

Enter the run's **ClientActive ID** once (prompted on first use, or set before comparing via API §4).
Every procedure then gets scoped to what YOUR client actually executes:

- Branches gated to other clients (`IF @ClientActive = 165 ...`) are marked dead for this client.
- A finding whose ONLY differences live in dead branches gets flagged **irrelevant_to_client** — real drift, but not this client's problem.
- Mixed changes stay honestly relevant (never over-claims).

Engine tiers you'll see in logs: `structured` (full proof), `heuristic` (CURSOR procs — exclusions still trustworthy, equality never claimed), `opaque` (compare whole thing).

## 4. The update pipeline (API)

```bash
BASE=http://127.0.0.1:5000/api/run/<RUN_ID>/client_to_105

# 1. Classify everything deterministically (small / gated / major / cosmetic ...)
curl -X POST $BASE/classify_all

# 2. Fold client's gated customizations into 105 behind their gate
#    (deterministic splice; DeepSeek only as fallback for weird procs)
curl -X POST $BASE/gate_wrap

# 3. Approve in the UI (or POST review per finding), then build package + ledger entry
curl -X POST $BASE/update_package
# -> apply/add_update_on_105.sql + manifest.json + ledger.jsonl entry

# 4. REHEARSE: runs the script against a scratch restore of the CLIENT's own backup.
#    Measured pass/skip/fail facts BEFORE touching any real server.
RUN_LIVE_DB=1 curl -X POST $BASE/rehearse     # scratch DB always dropped after
```

Then a human runs the approved script on the real target (SSMS / sqlcmd). The tool never touches production directly.

## 5. Column alters (the boring job)

Additive columns are generated automatically. Retypes/drops get a **preflight plan**: dependent indexes/constraints/stats are dropped and recreated VERBATIM around the ALTER — killing the classic "dependent object" errors instead of skipping them. Anything without captured detail lands in `warnings`, never guessed SQL.

## 6. Webpages deploy

```python
from drift import webdeploy
from pathlib import Path

m = webdeploy.build_manifest(Path("olives web pages/Olives"), Path("/mnt/client/www/Olives"))
print(webdeploy.emit_robocopy(m, Path("olives web pages/Olives"), Path(r"\\client\www\Olives")))
# or let the tool copy (old files kept as .bak_<timestamp> sidecars):
print(webdeploy.apply_copy(m, Path("olives web pages/Olives"), Path("./staging"), allow_delete=False))
```
Deletes require explicit `allow_delete=True`. Same posture everywhere: deletions never happen by accident.

## 7. Audit trail ("what did we apply on client X?")

```python
from drift import ledger
ledger.read_entries(client_id="66")            # every package ever shipped to them
ledger.last_for_client("66")                   # their latest baseline -> next update diffs from here
```

## 8. Safety rules (why you can trust it)

- Detection is deterministic (sqlpackage parsed model + difflib) — validated 100% on ground-truth batteries; AI NEVER decides what differs.
- AI output is advisory/merged-draft only; human Accept required; diff always shown next to it.
- No DROP ever enters an apply script by default; deletions double-opt-in.
- Rehearsal touches only a throwaway restore of the client's own backup; always dropped.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| "Access is denied" reading a .bak | `chmod 644 <file>.bak` (container user reads it through the mount) |
| Backup/restore writes fail | `/host` mount is read-only BY DESIGN — write inside container then `docker cp` out |
| SQL Server login failed (18456) | stale container with old password: `docker rm -f drift-tool-mssql` and rerun |
| Apply button disabled | run was reloaded from disk after restart — re-run the comparison |
| Encrypted procs error (SQL74502) | one encrypted proc blocks reports when it DIFFERS — exclude or decrypt it |
| "no ProcedureChangeLog" | informational — attribution unavailable for that side, detection unaffected |

## 10. Quick-scan a LIVE server pair (seconds, triage only)

```python
from drift import livescan
a = livescan.scan(livescan.connect("10.0.10.105", "Olives_Images", "cds", input("pwd: ")))
b = livescan.scan(livescan.connect("CLIENTSERVER", "Olives_Images_AlMalaki", "user", "pwd"))
print(livescan.quick_compare(a, b)["summary"])   # missing / extra / body_changed / column drift
```
Triage routing ONLY -- the scan module physically cannot emit scripts; deep verification stays with the .bak pipeline.

## 11. Sync config tables (menus/pages/messages) safely

```python
from drift import datacopy
tables = datacopy.list_config_tables(cur_src)              # menu|Programs|Messag(e)|Page whitelist
keys   = datacopy.get_key_columns(cur_src, "OlivesMenu")
plan   = datacopy.diff_tables(datacopy.fetch_rows_hashed(cur_src, "OlivesMenu", keys),
                              datacopy.fetch_rows_hashed(cur_dst, "OlivesMenu", keys))
sql    = datacopy.emit_merge_script("OlivesMenu", cols, keys, plan)   # portable artifact, quotes doubled
rep    = datacopy.apply_plan(cur_dst, "OlivesMenu", keys, plan)       # parameterized path
```
Composite keys correct; apostrophes survive; identity handled. Review the emitted .sql before apply.

## 12. Profiles + auto re-verify

```bash
curl -X POST :5000/api/profiles -d '{"name":"almalak","master_path":"/…/105.bak","client_path":"/…/al.bak","client_active_id":"66"}'
curl -X POST :5000/api/run -d '{"profile":"almalak","directions":["client_to_105"]}'
# update_package / rehearse responses now carry "verification": {residue_counts} -- machine-checked proof it landed.
```

---

*Full design + validation history: PLAN.md, PLAN-V3, PLAN-V4, PLAN-V5, VALIDATION.md in this folder.*
