# Drift Tools Comparison & The Ultimate Blueprint

**Subject:** in-house "SQL Compare" v2.2.0.0 (VB.NET/SQL-DMO, 2010) vs drift-tool (Python/DacFx, 2026)
**Basis:** full static teardown (`SQL_Compare_Reverse_Engineering_Report.md`) + drift-tool's own validation record (PLAN.md, PLAN-V4, VALIDATION.md §1–16).
**Goal:** one tool that does everything both do — with neither's flaws.

---

## 1. Executive verdict

They are near-opposites, which is why merging them is worth it:

- **SQL Compare** is a **fast, live, shallow** operator's tool: connects to two servers, answers "what exists here but not there" in seconds, pushes objects/columns/data directly — but **cannot see procedure body changes at all**, has zero safety rails (DROP+CREATE pairs, silent error swallowing), and corrupts data via quote-stripping.
- **drift-tool** is a **slow, deep, safe** engineer's tool: byte-exact detection validated by planted-change batteries, ClientActive scoping no other tool on earth has, rehearsal-before-production, audit ledger — but requires `.bak` restores (~minutes), never touches live servers for compare, and does **no data movement at all**.

**The beast = SQL Compare's speed/live-convenience/data-copy × drift-tool's depth/safety/multi-tenant brain.**

---

## 2. Head-to-head, every aspect

| Aspect | SQL Compare v2.2 | drift-tool | Edge |
|---|---|---|---|
| **Runtime** | Windows-only, 32-bit COM (SQL-DMO, removed after SQL 2008 R2), .NET 3.5, DevExpress 2012 | Python 3.13 + Docker scratch MSSQL; runs anywhere | SC (deployability ours: needs Docker) |
| **Connection model** | Two LIVE servers, UDP server browse, DB dropdown | Two .bak files restored into scratch containers | **SC** for speed/convenience; ours for reproducibility/offline safety |
| **Detection: presence** (object missing either side) | ✅ set-diff over sysobjects | ✅ sqlpackage DeployReport | tie |
| **Detection: procedure/function/view BODY changes** | ❌ **invisible — the fatal blind spot** (§8.1 of teardown: "an SP changed on one side will never appear") | ✅ byte-exact parsed diff + statement map | **drift-tool, by a mile** |
| **Detection: columns incl. type/length** | ✅ keyed tuple | ✅ + retypes with full rendered type | drift-tool slightly |
| **PK / FK compare** | ✅ dedicated tabs (report-only) | ✅ captured definitions, scripted when safe | drift-tool |
| **Indexes, checks, defaults, sequences, synonyms, UDTTs, settings (ANSI_NULLS)** | ❌ mostly absent | ✅ extended capture (VALIDATION §12) | drift-tool |
| **Formatting/comment noise** | n/a (wouldn't see it anyway) | separated buckets — 85% of raw signal silenced without hiding anything | drift-tool |
| **Accuracy evidence** | none documented | planted batteries 12/12, 13/13, 6/6; same-DB hallucination check 0 findings; metrics endpoint recomputes live | **drift-tool** |
| **Direction handling** | implicit (DB1→DB2) | two explicit workspaces + Master/Client labels + swap guard | drift-tool |
| **Multi-tenant awareness (@ClientActive)** | none — pushing an SP overwrites other clients' branches blindly | block-scope engine, splice-up/preserve-down wrapping, irrelevant_to_client bucket | **drift-tool, unique** |
| **Sync script safety** | DROP+CREATE pairs, no IF EXISTS guards, executes immediately | CREATE OR ALTER, additive-only default, deletions double-opt-in, manifest | **drift-tool** |
| **Column sync UX** | group-checkbox per table + free-text **backfill value** → ALTER+UPDATE in one gesture | generated ADDs; retypes/drops routed manual with plans | **SC for backfill workflow**; ours for dependency preflight |
| **Execution layer** | DMO ExecuteImmediate, silent try/catch swallow, errors→RTF counters | executor.py: msgno-classified benign/fatal, numbered progress, execution_report.json; **rehearsal on scratch restore first** | drift-tool |
| **Data copy** | ✅ menu/Programs/Messag(e)/Page tables, row-by-row INSERT + idempotent upsert scripts — **but strips apostrophes (data corruption) and breaks composite keys** | ❌ none (data-config drift was backlog item) | **SC concept, broken impl — rebuild properly** |
| **Post-sync verification** | auto re-compare after run | recompare() exists (15× fast) but not auto-wired post-apply | SC pattern to adopt, ours to power it |
| **Config persistence** | saved connections per project (**plaintext passwords in repo!**) | nothing comparable yet (run-scoped picks) | SC concept, secure re-impl |
| **Audit/history** | RTF error log only | ledger.jsonl per client + full run folders as reloadable evidence | drift-tool |
| **AI assist** | none | advisory triage + DeepSeek gate-aware merge drafting | drift-tool |
| **Automation/CLI** | none, GUI-thread only | every phase callable; endpoints; SSE logs | drift-tool |
| **Webpage deployment** | none | webdeploy.py manifests + robocopy emitter | drift-tool |
| **Security posture** | plaintext creds committed, injection surface (Value column), quote-stripping | secrets gitignored 600, parameterized queries, containment checks | drift-tool |
| **Speed on typical check** | **seconds** (two catalog queries) | ~4 min (1GB baks) / 15–17s re-compare | **SC** |

Score: drift-tool dominates everything about *correctness and safety*; SQL Compare keeps three real advantages: **live instant compare, config-table data copy, backfill-value column workflow** — plus small UX conveniences.

---

## 3. Cherry-pick list — what the beast inherits FROM SQL Compare

Ordered by value. Each entry: what, why the original is loved despite its bugs, and how the beast implements it right.

### C1. Live quick-scan mode ⭐ highest value
Old: pick two live servers, hit Compare, results in seconds.
Beast: new `livescan.py` — direct catalog queries (`sys.objects`, `sys.columns`, `OBJECT_DEFINITION`, `sys.foreign_keys`, `sys.table_types`) against two live connections; **presence + column-shape + BODY HASH** diff (hash catches modified procs the old tool never saw). Output labeled `quick_scan` — triage view only. Deep verification still goes through the .bak pipeline (evidence-on-disk guarantee). Reuses old tool's connection-picker concept as CLI flags + API params; credentials via env/prompted, never stored plaintext.
Safety rule carried forward: quick-scan NEVER generates apply scripts — it routes you into the verified pipeline.

### C2. Config-table data copy (menu/Programs/Messag(e)/Page) ⭐
Old: row-by-row INSERTs + upsert preamble (`IF @@ROWCOUNT=0 INSERT … else UPDATE`), clustered-key fallback; shipped to customers as portable .sql. Loved because Olives' menus/pages/messages ARE the deployment.
Original's three unforgivable bugs — the beast fixes all:
1. `value.Replace("'","")` destroyed text ("Al'Malak"→"AlMalak") → proper `''` doubling via parameterized reads;
2. composite-key WHERE builder overwrote accumulated predicates (mass-update hazard) → key tuple built correctly, tested on multi-column PKs;
3. identity seeds diverged (skipped identity cols, never CHECKIDENT) → optional IDENTITY_INSERT or seed repair step.
New module `datacopy.py`: same table whitelist regex (`%menu%|%Programs|%Messag|%Massag|%Page%`, editable), hash-based row diff (only changed rows move — old tool copied EVERYTHING), idempotent merge-script emission identical in spirit to the old Save Script artifact, row counts + checksums in the report. Runs against live pair (C1 mode) or restored scratch pair.

### C3. Column backfill value workflow
Old grid: tick new column, type default value → script gets `ALTER TABLE ADD` + `UPDATE … SET col=value`. Operators lived in that cell.
Beast: extend scriptgen's additive-column path with optional `backfill_value` per finding (API field + UI input); UPDATE emitted AFTER the ADD, parameterized; numeric vs string vs datetime quoting decided by captured type (port the old tool's §8.3 type matrix — it was correct). Preflight orders it before index rebuilds so backfill doesn't fight constraints.

### C4. Auto re-verify after apply
Old: sync loop ends → whole compare re-runs automatically. Genuinely good instinct.
Beast: wire existing `pipeline.recompare()` as automatic step N+1 of update_package/rehearse flows; residue report = machine-checked proof the update landed (already specced B.7; now sequenced).

### C5. Saved project profiles
Old: reopen the tool, your server/db pair is already there.
Beast: `profiles.json` in work/ (gitignored): named profiles {client_id, master path-or-server, client path-or-server, exclusion snapshot, ClientActive id}; CLI `--profile almalak`; UI dropdown. Secrets stay out (paths only for .bak mode; live mode prompts/env).

### C6. Grid ergonomics worth porting to the web UI
Filter persistence across re-compares · select-all/none per bucket · spacebar/row-click toggling · salmon highlight for approved rows · expand/collapse groups · double-click object viewer. Cheap HTML/JS ports of proven triage UX; the ErrorForm's per-type failure counters already exist in execution_report — render them.

### C7. Portable artifacts for customer-side replay
Old merge .sql could be emailed to a customer with no tool installed. Beast keeps this class of artifact: datacopy merge scripts + apply scripts are already standalone files — add the same idempotent upsert preamble style for any future data fixes.

### C8. UDTT scripting
Old hand-built `CREATE TYPE ... AS TABLE (...)` from metadata (the one thing it scripted better than us). Port the generator into scriptgen for `SqlUserDefinedTableType` findings using our already-captured per-column metadata — removes another "manual review" category.

---

## 4. What the beast keeps ONLY from drift-tool (non-negotiable core)

1. Body-level detection — the old tool literally cannot see the #1 thing that breaks updates.
2. Ground-truth accuracy culture — every claim backed by planted-change batteries and recomputable metrics.
3. ClientActive scoping + gate-wrap (splice_up / preserve_down) — multi-tenant safety nothing else has.
4. Safe-by-construction scripts (additive default, deletions double-opt-in, manifests).
5. Offline-first .bak comparison + rehearsal-before-production.
6. Blast radius, attribution, ledger, webpage deploy, excluded-bucket transparency.
7. Noise separation (85% silence without hiding).

And explicitly NOT inherited: DROP+CREATE sync pairs, silent exception swallowing, plaintext creds in repo, unquoted identifier interpolation, MAX-normalization inconsistency (−1 vs 0), dbo-only assumption where avoidable.

---

## 5. Build roadmap — "Ultimate Beast"

| Phase | Deliverable | Modules | Tests required |
|---|---|---|---|
| UB-P0 (quick wins) | backfill values (C3); UDTT generator (C8); auto-reverify wiring (C4); profiles.json (C5) | scriptgen, pipeline/app | backfill quoting matrix; UDTT DDL vs old tool's output on 5 real types; profile round-trip |
| UB-P1 (live scan) | livescan.py quick-scan over two live connections (C1) | livescan.py + app endpoints + CLI flag | fake-cursor battery; parity vs sqlpackage on bench pair (same changed-set, disclosed granularity limits); NO script generation from scan |
| UB-P2 (data copy) | datacopy.py fixed clone of Copy Data (C2) | datacopy.py + endpoint + tests | escaping property-test (apostrophes survive); composite-key upsert correctness; identity-seed handling; row-hash minimality; whitelist editable |
| UB-P3 (UX port) | grid ergonomics + error counters in web UI (C6/C7) | static/app.js, templates | DOM-level QA pass like VALIDATION §11 |

Effort note: P0 ≈ a day each item; P1/P2 are the real builds; P3 polish.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Live scan becomes a shortcut people trust for updates | scan outputs are triage-labeled, script generation stays behind the verified pipeline (hard-coded refusal) |
| Data copy touches business tables beyond config whitelist | whitelist explicit + confirm gate + row-count/checksum preview before execute |
| Backfill UPDATE hits more rows than intended | always paired to the exact added column, parameterized, rehearsed first |
| Feature creep erodes the accuracy boundary | every new module ships with its own battery; detection path stays AI-free and deterministic |

**Bottom line:** keep drift-tool's brain and conscience; graft on SQL Compare's hands and eyes. Nothing from the old tool enters without fixing its known bugs and passing the same ground-truth standard the rest of the beast lives by.
