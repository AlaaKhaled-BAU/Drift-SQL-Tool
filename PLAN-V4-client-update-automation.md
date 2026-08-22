# PLAN-V4 — Client Update Automation ("the update button")

> Authoring stance: written from two hats — **Product Manager** (§A) and **AI Engineer** (§B). Grounded in a code audit of everything drift-tool v2/V3 already ships (PLAN.md, VALIDATION.md §1–16, PLAN-V3, PLAN-04 D3–D8) and the real update workflow the team described.
>
> **The workflow being automated:** ship an Olives BO update from master image 105 to a client without breaking that client's customizations, by (1) finding procedures changed since the last update, (2) comparing them to the client's copy, (3) reflecting *only* the differences back — small changes applied as-is, major changes/customizations wrapped under an `IF @ClientActive = <id>` block, never drop-create-everything — while excluding SAP/Alpha/Integ/ERP/customer-named procedures, (4) running the tedious column-alter work with known-benign errors skipped (`dependent`, `binary`, `unique`, duplicates), and (5) deploying the updated web pages to the client's IIS box.

---

## A. Product Manager view

### A.1 Who uses this and what job they hire it for

| Persona | Job-to-be-done | Today's pain |
|---|---|---|
| Update engineer (primary) | Ship an update to client X in hours, not days, with zero regressions | Manual proc-by-proc comparison after every update; edits get lost because they were made on 105 but the client's image predates them |
| Support engineer | Answer "did the update change X?" | No record of what was applied, when, or why |
| Team lead | Onboard a new employee onto updates safely | Process lives in one person's head |

### A.2 Story requirement → current state (audited, not assumed)

| # | Requirement from the field | Status today | Verdict |
|---|---|---|---|
| 1 | Find procedures modified since last update | Detection is complete (VALIDATION §3–4: ~100% sample accuracy, 12/12 + 13/13 planted batteries) but compares **full images**; "since last update" needs a persisted baseline | Partial |
| 2 | Compare to 105, reflect only differences | Two-way workspaces, add/update-only scripts, DropObjectsNotInSource report-only — the dangerous exact-copy path is gone by construction | **Done** |
| 3 | Major changes/customization → wrap under `IF @ClientActive` block | Exists as **AI merge** (DeepSeek, per-finding, human-accepted `merged_def`) + statement map that already parses `IF @ClientActive = 165` branches. But it's one-click-per-finding; no bulk classification into small/major/gated | Partial |
| 4 | Small things applied as-is if harmless | Human approves each finding manually; priority scoring exists (D6b) but nothing *classifies* small-vs-major deterministically | Gap |
| 5 | Never drop-create everything | Additive-by-construction scriptgen; deletions opt-in off; tested hardest (PLAN.md §8, §12) | **Done** |
| 6 | Long exception list: sap / alpha / integ / ERP / customer-named | `exclude-from-drift.txt` covers some customer names + SAP_Integ patterns; alpha/integ generic patterns and ERP names not all present; list is hand-edited | Partial |
| 7 | Column alters are boring as hell; skip `dependent`/`binary`/`unique`(+duplicates) errors | Scriptgen emits additive `ALTER TABLE ADD` only; drops/retypes → manual list. **No executor exists**, so there is nothing doing the boring job, let alone skipping benign errors | **Biggest gap** |
| 8 | Run the new updated webpages | Not in the tool at all. Deployment today = manual copy to IIS | Gap |
| 9 | Detect defects | Advisory AI triage per finding + batch (capped); caller blast radius (27.5% resolved); removed-WHERE/param-drop style risk flags in the AI schema | Done (advisory) |
| 10 | Generate fixing script | Programmables + additive columns; extended types captured but not scripted (disclosed §7.3) | Partial |
| 11 | Automate the full process | No orchestrator, no post-apply verification, no per-client ledger | Gap |

### A.3 What "standout" means here (positioning)

The tool's differentiator is **accuracy you can audit**: deterministic detection validated by ground-truth batteries, evidence on disk for every finding, AI never allowed to decide. Every feature below must preserve that. The standout moment we're building toward:

> Pick client `.bak` + 105 `.bak` → tool classifies all findings (small / gated-customization / excluded / needs-human) → builds the update script → **rehearses it on a scratch restore of the client's own database** → shows the rehearsal result → one approved click applies to the live target (or exports the script) → re-compares to prove convergence → deploys changed web pages → writes the ledger entry.

That is the entire manual day compressed into one supervised pipeline, with the human still signing off at exactly one gate.

### A.4 Scope decisions (PM calls)

1. **Human approval stays, but moves to one place.** Per-finding clicking doesn't scale to ~1000 findings. The classifier proposes; the human reviews the *classification exceptions* (major items, anything low-confidence), not every item.
2. **Rehearsal-before-production is non-negotiable.** We already restore client `.bak`s into scratch containers routinely (~4 min). Running the generated script against that same scratch DB converts "skip benign errors" from a gamble into a measured fact. This is the single biggest trust-builder and the cheapest safety win available.
3. **Live-connect executor AND script export both ship.** Same statement runner underneath; live mode just points pymssql at the real target. Field teams can adopt gradually.
4. **Webpage deploy is file-level, not clever.** Hash-compare the update package's `olives web pages/Olives` (+ `srv`) tree against the client's deployed folder → manifest of add/update/delete → backup + robocopy (or in-tool copy). No framework assumptions beyond IIS file layout.
5. **The exclusion list becomes data, not code.** Pattern registry (globs like `*_SAP_Integ*`, `*alpha*`, `*integ*`, ERP names, per-customer names) editable in UI, versioned with runs, so "why was X excluded?" always has an answer.

### A.5 Success metrics

| Metric | Baseline (manual) | Target |
|---|---|---|
| Wall-clock per client update | days (est.) | ≤ 1 hour supervised |
| Findings needing individual human attention | ~100% | ≤ 10% (classifier handles the rest; exceptions surfaced) |
| Post-update re-compare residue (should be zero real diffs left unaddressed) | unknown/unmeasured | 0, printed in the report |
| Column-alter statements executed without a human reading an error | 0% | ≥ 90% (rest correctly routed to manual with exact reason) |
| Audit trail ("what did we change on client X on date Y") | none | 100% of applies ledgered |

---

## B. AI Engineer view

### B.0 Boundary carried forward unchanged

```
DETECTION  = restore + sqlpackage + difflib + statements.py   → deterministic, validated, untouched
CLASSIFY   = deterministic rules first; AI only as labeled fallback
APPLY      = deterministic DDL + tolerant error runner; rehearsed on scratch first
AI         = merge-drafting (existing), defect triage (existing), classification fallback ONLY
```

### B.1 New module: `drift/classify.py` — small / gated / major / excluded

Deterministic, unit-tested, consumes what `_enrich()` already computes (change_kind, statement map, callers, columns).

**Eng-review decision (D3): classification runs INSIDE `pipeline._enrich()`**, not as a post-hoc disk pass — the full statement alignment exists only in memory there (compact summary goes to index.json, statement TEXT goes to separate `.statements.json` files, pipeline.py `_statement_map`). Classifying at enrich time means fresh runs and `recompare()` reloads carry identical verdicts; the verdict persists into the finding dict like every other enriched field.

| Rule (first match wins) | Class | Default action |
|---|---|---|
| Name matches exclusion registry | excluded | omit, logged |
| `category == formatting_only` | cosmetic | omit from script |
| Statement map shows only an added branch whose condition contains `@ClientActive`/ClientsActive reference | gated_customization | bring client's branch onto 105 inside its own gate (or keep 105's body + append gate) — deterministic text splice |
| `change_kind == 'param'` (defaults only) | small | CREATE OR ALTER as-is |
| Body-only, changed-statement count ≤ N, no risky token delta (no `WHERE`/`JOIN` predicate removal, no `<`→`<=`, no dropped `TOP`, no tran-scope change — reuse ai.py's risk vocabulary as a deterministic regex screen) | small | CREATE OR ALTER as-is |
| Everything else | major | route to AI-merge proposal (existing flow) or manual |

Every item carries `classification + confidence + which rule fired`. Low-confidence majors are exactly the short list the human reviews. Measure the classifier against human labels on the next real client pair before trusting thresholds (same honesty standard as D6b's priority tuning).

### B.2 New module: `drift/gatewrap.py` — deterministic IF-block wrapping (both directions)

The AI merge works but is per-finding, costs a call, and can hallucinate. For the common cases do it with scissors, not a model. **Eng-review finding A1: the two directions need DIFFERENT splices, and the plan originally specified only one.**

```
client_to_105  (back-port)      client body has gated branch 105 lacks
  → SPLICE-UP: append `ELSE IF @ClientActive = <id> BEGIN <client stmts> END`
    to 105's gate chain (or wrap whole 105 body when no chain exists).
    105's other-clients logic untouched by construction.

105_to_client  (push update)    105 changed shared logic; client has OWN gated
                                branches master lacks
  → PRESERVE-DOWN: take MASTER's new body, re-append every top-level
    `IF/ELSE IF @ClientActive = ...` branch found in the CLIENT's current
    body, verbatim, at the end of the chain. Plain CREATE OR ALTER with the
    raw master_def here would silently DELETE the client's customization --
    this is the exact disaster class the whole tool exists to prevent.
```

Mechanics for both: statements.py segmentation (70% real-data ok rate; cursor procs disclosed-fail), literal-safe anchor search via diffing.code_spans/mask_comments to find the chain and splice points, byte-preserved branch text. If segmentation returns `ok=false` → fall back to the existing DeepSeek merge proposal (human-reviewed as today). Unit tests mirror test_statements.py plus a **direction-matrix regression** (both directions × {chain-exists, no-chain, cursor-fallback}) — the D2 scriptgen direction bug is the precedent this test exists to prevent repeating.

### B.3 New module: `drift/preflight.py` — kill "dependent" errors before they happen

Most ALTER COLUMN failures are predictable from catalogs we already capture (inspect_objects: indexes, FKs, check/default constraints, statistics):

```
for each retyped/dropped column:
    find dependent objects (sys.indexes, sys.computed_columns, sys.check_constraints,
                            sys.default_constraints, sys.foreign_keys, stats)
    emit ordered script: DROP dependent → ALTER COLUMN → recreate dependent verbatim
```

This turns error-*skipping* into error-*avoidance* for the deterministic majority. What genuinely remains unfixable at generate time (data-dependent failures) goes to the runner's benign-skip classes.

### B.4 New module: `drift/executor.py` — the tolerant runner

One engine, two targets:

- **Rehearsal mode (new default):** restore client `.bak` into scratch (pipeline already does this), run the assembled script there first. Result = measured facts, not predictions: which statements pass, fail-benign, fail-real.
- **Live mode:** same statement stream via pymssql to the real target, after a rehearsal gate + explicit confirm (mirror of the assemble-confirm guard).

Error classification is a **config table**, seeded from the field:

| Class | Matches (message-text patterns, case-insensitive) | Action |
|---|---|---|
| dependent | `dependent on column`, `is dependent on object` | skip + log (preflight should have prevented most) |
| binary_truncation | `string or binary data would be truncated`, `arithmetic overflow` | skip + log |
| unique_duplicate | `duplicate key`, `unique index`, `cannot insert duplicate` (the "duplicate or something" fourth class — name confirmed in config, not guessed) | skip + log |
| statistics | `statistics '.*' is dependent` | skip + log |
| fatal | everything else | abort run, print statement number + full message |

Each statement executes individually (statements.py splitter), numbered PRINT-equivalent progress recorded, outcomes written to `execution_report.json` alongside the run. Skipped items appear in the final report with their messages — visible, never silent, matching the house rule that noise is bucketed, never buried.

### B.5 New module: `drift/webdeploy.py`

Input: update package web tree (repo's `olives web pages/{Olives,srv}`) + client's deployed path (live mode) or a zipped copy of it. Output: manifest `{add:[], update:[], delete:[]}` by SHA-256, then either emit a robocopy script with `-B` backup step, or perform the copy itself with automatic `.bak_<date>` sidecar backups. Deletes require explicit opt-in (same posture as DDL deletions).

### B.6 New module: `drift/ledger.py` — close requirement #1

Per client: `ledger.jsonl` in the run store — {client id, date, run_id, applied manifest, execution report, webpage manifest}. Next update against the same client reads the last entry as the **baseline**: "changed since last update" becomes a filter over the current comparison instead of tribal memory. This also finally gives the 3-way lost-fix question a data source.

### B.7 Orchestrator: `POST /api/run/<id>/update_pipeline`

Existing pieces, wired in order, each stage resumable and logged:

```
detect (exists) → classify (B.1) → auto-select smalls by policy flag
  → gate-wrap gated items (B.2) / AI-merge majors (exists)
  → preflight columns (B.3) → assemble script (exists)
  → REHEARSE on scratch (B.4a) → human gate: review rehearsal + exceptions
  → APPLY live or EXPORT script (B.4b) → recompare() verification (exists, 15× fast)
  → webpage manifest/deploy (B.5) → ledger entry (B.6)
```

Verification step reuses `pipeline.recompare()` — post-apply, the C→105 workspace should shrink to only intentionally-skipped items; anything else is printed as residue. That closes the loop on "we care about accuracy" with a machine-checked answer instead of an assurance.

### B.8 Exclusion registry upgrade

Move `exclude-from-drift.txt` content into `drift/exclusions.json`: `{glob_patterns[], sources[]}`, seeded with current lines plus `*alpha*`, `*integ*` variants, ERP tokens, and per-customer entries. UI editor + every run records the snapshot used. `is_excluded()` keeps its signature; only the loader changes. Backward compatible with the existing file (import once, mark migrated).

### B.9 Tests (non-negotiable, house standard)

- classify.py: each rule fires on synthetic findings mirroring the surgical batteries; exclusion beats everything; formatting never reaches a script.
- gatewrap.py: splice correctness on gated-chain, no-chain, cursor-fallback cases; byte-safety outside spans (code_spans discipline).
- preflight.py: column with index+default+check produces correct DROP→ALTER→RECREATE ordering; verbatim recreation text equality.
- executor.py: fake-cursor harness asserting benign classes skip+log, fatal aborts, report shape; rehearsal-mode wiring against the existing surgical `.bak` pair (extend prepare_v2.py with one deliberately failing statement).
- webdeploy.py: hash manifest correctness on a temp tree; delete opt-in off by default.
- Regression floor: full suite (currently 99/99) stays green; batteries reproduce identical counts.

### B.10 Honest limits, stated up front

- Statement segmentation covers ~70% of real procs (cursor disclosure stands); gate-wrap inherits that ceiling and falls back to AI-merge/manual.
- Dynamic-SQL callers remain invisible to blast radius (catalog limitation, disclosed since §8).
- Live mode still requires network reachability + credentials to client servers — deployment topology is a field decision, not a code problem.
- Rehearsal proves the script against the *image*, not concurrent live changes made after the `.bak` was cut; the pre-apply confirm banner must say so.

---

## C. Phasing

| Phase | Ships | Exit criterion |
|---|---|---|
| P0 — classify + exclusions | classify.py, gatewrap.py, exclusions.json + UI editor | On a real client pair, ≥80% of findings carry a correct proposed action (human-labeled spot check), exclusions answer "why?" |
| P1 — rehearse + column job | preflight.py, executor.py rehearsal mode, execution_report | Full generated script runs green-or-explained on scratch restore of the client `.bak`; column alters ≥90% hands-off |
| P2 — go-live | executor live mode, ledger, webdeploy, orchestrator endpoint + single-screen UI | One supervised end-to-end update executed on a real client; re-compare residue = 0; ledger entry written |

Sequencing rationale: P0 kills the per-finding clicking (biggest time sink), P1 kills the column drudgery *and* buys safety for P2's automation, P2 only automates what P1 proved.

## D. Implementation status (feature/client-update-automation)

### D.1 Shipped (validated)

| Item | Evidence |
|---|---|
| `drift/blocks.py` — block-scope engine | 3-state gate eval (`match`/`no_match`/`unknown`), chain branch-splitting on statements.py's scanner, nested composition, conservative unknowns |
| `drift/test_blocks.py` — deep battery | 26/26: eq/neq/reversed/IN/NOT-IN, AND/OR compounds, comment-masked gates, string-literal phantoms, CASE-END depth, dead-subtree containment, ELSE reachability, fingerprint semantics |
| Full regression suite | all 13 test files green (test_blocks included) |

### D.2 In flight — tiered scope modes (deep-test finding)

Real probe on `OT_SendCustomersInfo` (218 KB, 191 `@ClientActive` refs): proc contains a CURSOR → strict whole-body segmentation refuses → feature dead on exactly its target case. Fix, preserving the accuracy floor:

```
resolve_scope tiers:
  structured  full walk succeeded        -> strong claim: fingerprint equality
                                            proves "differs only in dead-for-C code"
  heuristic   segmentation failed, but N provably-dead cleanly-bounded branches
              were found                 -> weak claim: excluded list trustworthy;
                                            NO fingerprint emitted; trims review
                                            scope / AI-merge input only
  opaque      nothing decidable          -> ok=False, compare full definition
Heuristic exclusion rule: condition evaluates no_match for C AND BEGIN..END
bounds close cleanly on masked text AND span not nested in a prior accepted
span. Unbraced/unbounded gates are never excluded.
```

### D.3 Remaining queue (this branch)

1. Implement heuristic tier (D.2) + battery additions (cursor+gate, unbalanced-skip, outermost-wins nesting)
2. Real-data probes: per-client fingerprint distinctness on OT_SendCustomersInfo; mutation-invisibility (edit inside other-client branch must not move client 66's fingerprint); shared-code mutation must move it
3. Pipeline wiring: `_enrich()` computes scope fields when `meta.client_active_id` set; findings whose scoped fingerprints match both sides get visible bucket `irrelevant_to_client` (excluded from script by default, never hidden)
4. DeepSeek key live at `work/.deepseek_key` (gitignored ✓) — verify `ai_merge.test_connection()`
5. Commit sequence on branch

---


---

## E. Parallel-test results (2026-08-22, branch feature/client-update-automation)

Two lanes on a live benchmark pair (base.bak vs mod.bak built via prepare_bench.py,
6 planted changes incl. ClientActive-gated scenarios the old surgical battery never had):

| Planted change | Ground truth | Tool (Lane A) | Manual pass (Lane B) | Verdict |
|---|---|---|---|---|
| P1 edit inside @ClientActive=165 branch only | dead-for-66 code | folded into BenchDispatch finding; scope stats exclude the branch both sides | byte-verified in captured defs; scope match/no_match counts agree with hand-traced chain | correct |
| P2 shared-tail literal changed | real drift | BenchDispatch modified/body, irrelevant=False | byte-verified; statement map flags tail as changed | correct |
| P3 new `ELSE IF @ClientActive = 66` branch | gated customization | detected inside same finding | client-side scope match count 2->3 confirms branch seen | detection correct; classifier (auto-label) still future work |
| P4 BenchSmall created in MOD only | client-added proc | role=added SqlProcedure | tool right, original plan label wrong (planting bug) | correct |
| P5a new table BenchExtra | added table | role=added SqlTable | - | correct |
| P5b BenchItems.Reference column | added column | modified/columns, "1 column(s) added" | columns.json verified | correct |

**Accuracy: 6/6 planted changes correctly represented; 0 false positives; 0 false negatives.**
Scope annotation: composed case handled right — P1 noise present but P2/P3 relevant =>
irrelevant_to_client=False (never over-claims). Attribution worked (ProcedureChangeLog rows found).

**Speed:** 25.3s wall for full pipeline (restore x2 -> dacpac x2 -> compare -> capture -> scope)
on the tiny pair; real-scale reference ~240s per VALIDATION. Scope resolution itself:
0.75s on the 218KB OT_SendCustomersInfo, <0.01s on bench procs.

**Readiness verdict:** detection core + scope layer = production-usable today behind the
optional client_active_id input. Still to build before "the update button": classify.py
(auto small/major/gated), gatewrap.py (deterministic splice both directions), executor +
preflight, ledger, webdeploy, UI surface for the scope fields.

**Bench gotchas fixed en route (all previously documented classes):** stale container SA
password (recreate), read-only /host mount => backup inside container + docker cp out,
640-perm .bak after cp => chmod 644 (VALIDATION §11 bug #3 again).


---

## F. Build completion (2026-08-22)

All PLAN-V4 phases built on feature/client-update-automation. 19 test files, 191 tests green.

| Module | Tests | Notes |
|---|---|---|
| blocks.py (B.2a scope) | 30 | structured/heuristic/opaque tiers; real-probe validated |
| classify.py (B.1) | 15 | R1-R6 ladder + additive-column rule; read-only over findings |
| gatewrap.py (B.2) | 12 | splice_up / preserve_down, reachability-correct ELSE insertion, AI-merge fallback |
| preflight.py (B.3) | 7 | catalog-driven teardown->alter->rebuild plans, zero fabricated SQL |
| executor.py (B.4) | 12 | msgno error classes, rehearsal always-drops scratch DB |
| ledger.py (B.6) | 6 | jsonl audit per client |
| webdeploy.py (B.5) | 10 | hash manifests, sidecar backups, deletes opt-in |
| app.py orchestrator (B.7) | route smoke | classify_all / gate_wrap / update_package / rehearse |

Deviations, disclosed: exclusions registry stays as versioned txt (+new ERP/integ patterns)
-- JSON+UI editor deferred; UI surface for new endpoints is API/curl-first this pass
(GUI buttons deferred); update_package refuses disk-reloaded runs (needs in-memory defs)
instead of silently emitting empty scripts.
