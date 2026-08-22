# PLAN-V5 — Ultimate Beast: build plan, honest stack verdict, risk register

> Source: Drift_Tools_Comparison_and_Ultimate_Blueprint.md (cherry-picks C1–C8).
> This plan answers three questions: what edits matter, how they run in parallel,
> and where using this tool can hurt us.

---

## 1. Meaningful edits — five fully parallelizable lanes

Ownership rule: each lane owns disjoint files → zero merge conflicts. Integration
and full-suite runs happen only at the merge point, supervised centrally.

```
Lane A (data)      datacopy.py + test_datacopy.py          [new files only]
Lane B (live)      livescan.py + test_livescan.py           [new files only]
Lane C (scriptgen) backfill values + UDTT generator          [owns scriptgen.py]
Lane D (glue)      auto-reverify wiring + profiles.json      [owns pipeline.py/app.py glue]
Lane E (UI)        grid ergonomics + counters + scope badge  [owns static/, templates/]
        │ all five in parallel │
        ▼
Central integration: full suite → bench-pair rerun → PLAN/docs → commit
```

### Lane A — `datacopy.py` (C2, biggest field value)
Whitelist-driven config-table sync (`%menu%|%Programs|%Messag|%Massag|%Page%`, editable list).
Row-hash diff (only changed rows move), idempotent upsert emission
(`IF @@ROWCOUNT=0 INSERT … ELSE UPDATE` style, portable .sql artifact),
parameterized execution option, identity handling (IDENTITY_INSERT or seed repair).
Tests: apostrophe-survival property test; composite-key WHERE correctness;
identity-seed case; whitelist editability; row-count/checksum report shape.

### Lane B — `livescan.py` (C1)
Direct catalog scan of two LIVE connections: presence diff + column-shape diff +
`HASHBYTES` body-hash diff (catches modified procs the old tool never saw).
Hard-coded refusal to emit scripts — output is triage routing into the verified
.bak pipeline only. Tests: fake-cursor battery; parity spot-check vs bench pair.

### Lane C — scriptgen upgrades (C3 + C8)
Backfill: optional `backfill_value` per additive-column finding → ADD + typed
UPDATE (quoting matrix ported from old tool §8.3: numeric raw, strings quoted,
datatypes quoted; decided from captured type, never guessed). UDTT: generate
`CREATE TYPE … AS TABLE` from captured column metadata (kills another manual-review
category). Tests: quoting matrix table-test; UDTT DDL vs old tool output on 5 real types.

### Lane D — workflow glue (C4 + C5 + ledger baseline)
Auto-reverify: update_package/rehearse flows automatically end with `pipeline.recompare()`
residue report (machine-checked "did it land"). `profiles.json` in work/: {client_id,
master, client, exclusion snapshot, ClientActive id} + CLI `--profile`. Ledger gains
baseline query wired into compare request ("diff vs last ledger entry" summary).

### Lane E — UI ergonomics (C6/C7 render)
Filter persistence across reloads · bucket select-all · approved-row highlight ·
double-click viewer exists already, add: error-counter panel from execution_report.json ·
scope/irrelevant badge column · classification chips from classify_all. Static JS/templates only.

### Integration checklist (after all lanes)
1. full suite green (19 files today + 5 new)
2. bench-pair end-to-end rerun incl. one datacopy cycle + livescan parity check
3. TUTORIAL.md updated (new endpoints/flags)
4. VALIDATION.md appendix: what was live-tested vs unit-tested

---

## 2. Honest verdict — what tools we must actually use

| Decision | Call | Why (honestly) |
|---|---|---|
| Replace drift-tool with commercial Redgate SQL Compare/Data Compare? | **No.** | Per-seat cost, Windows-locked, closed. It cannot implement ClientActive scoping/gate-wrap — our core requirement is business-specific. Nothing on the market does it. |
| Keep Redgate as a second opinion? | **No — redundant.** | Our detection already cross-validates (sqlpackage vs difflib vs convert.py independent path vs planted batteries). Paying for another black box adds disagreement, not confidence. |
| Deep-compare engine | **Keep sqlpackage/DacFx.** | Proven at production scale, validated ~100% on samples. Rewriting with SMO/hand-catalog diff would burn innovation tokens for zero accuracy gain. |
| Quick-scan engine | **Raw catalog queries + HASHBYTES.** | Different job: speed over forensic depth. The two-engine split is deliberate — scan routes you INTO verification, never replaces it. |
| Execution/data access | **pymssql (keep).** | Known quirks (sql_variant decode) already worked around; swapping to Microsoft.Data.SqlClient means a dotnet sidecar for zero capability gain. |
| Data copy transport | **Generated upsert scripts first, parameterized execution second.** | Scripts stay portable/replayable customer-side (old tool's best idea); bulk APIs (bcp/BulkCopy) buy nothing on small config tables and kill portability. |
| AI layer | **DeepSeek only; retire the OpenRouter free-model fallback chain.** | Free models were rate-limited/leaky (measured, VALIDATION §11); DeepSeek measured working at ~1.5 s merges for pennies. Advisory boundary unchanged. |
| UI | **Keep Flask + vanilla JS.** | Internal single-user tool. A framework/build-chain is maintenance debt, not value. |
| Packaging | **python3.13 + documented setup; optional PyInstaller later.** | Desktop venv already exists; packaging is polish, not blocker. |
| Schema history/git-of-schema | **Skip (keep deferred).** | dacpac+capture.json per run already gives reproducibility; Tier-B history repo stays parked until a real trigger. |

One-sentence answer: **we must use our own tool, on the existing Python+DacFx+pymssql spine, adding livescan/datacopy as the only genuinely new machinery — no purchase, no framework change, no engine rewrite.**

---

## 3. Risk register — where using this tool can hurt us, and why

Ranked by expected damage × likelihood. Every risk lists its existing mitigation and
its honest residual.

### R1 — Rehearsal≠production (HIGH, medium likelihood)
Script proven safe against a restored image; the LIVE database may have drifted
since the `.bak` was cut (concurrent hotfixes, open transactions, triggers firing on
real writes that scratch never fires). Rehearsal proves syntax+catalog fit, not
production outcome.
Mitigation today: pre-apply human gate. Residual: real — close by running livescan
delta-check immediately before apply + applying in a maintenance window.

### R2 — Wrong ClientActive ID ⇒ wrong exclusions (HIGH, low-medium likelihood)
Scope resolution trusts the operator-typed ID. Typo `66`→`666` flips dead/live
branches: real changes hidden as "irrelevant", other clients' code spliced into 105.
Fingerprints prove text-equality, not ID-truthfulness.
Mitigation: conservative unknown-handling; literals only. Residual: operator error —
close with a confirmation banner (ID + excluded-branch preview + affected proc count)
before any package includes scoped decisions.

### R3 — Benign-error skipping masks real damage (MEDIUM-HIGH, medium)
executor.py deliberately continues past dependent/truncation/duplicate errors.
A skipped truncation on a backfill UPDATE = silent partial data loss; a skipped
duplicate_key may mean the sync silently didn't happen.
Mitigation: every skip logged in execution_report. Residual: reports must be READ —
add a mandatory sign-off field before an execution counts as done.

### R4 — Gate-wrap generates new code (MEDIUM, low-medium)
splice_up/preserve_down construct T-SQL that never existed before. A chain-rebuild
bug could break OTHER clients' branches on 105 when back-porting.
Mitigation: unit batteries + re-parse-before-emit + human Accept (merged defs are
proposals, never auto-approved). Residual: accepted-but-wrong merge reaching prod —
rehearsal catches syntax/catalog breaks, not semantic ones on other clients' branches.

### R5 — Resource exhaustion during restores (MEDIUM, high likelihood on weak hosts)
Host swap-death already observed firsthand (VALIDATION §7.5). Restoring two GB-scale
baks mid-workday can OOM the analyst's machine or the SQL container.
Residual until built: no pre-flight RAM/disk check — this should be Lane D's smallest item.

### R6 — Privilege blast radius (MEDIUM)
Apply requires db_owner/ddl_admin; teams will reuse the shared `cds` login. One tool,
one credential, full DDL rights on production. No per-action auditing beyond our ledger.
Close with named per-engineer logins + ledger recording login_name.

### R7 — Engine-version drift (LOW-MEDIUM)
Pinned sqlpackage binary; a silent upgrade could change DeployReport semantics
(TableRebuild precedent: real differences were once dropped silently until caught by
count reconciliation).
Mitigation: regression batteries re-run per version bump; pin exact version in config.

### R8 — Bus factor / coverage gaps (LOW-MEDIUM, chronic)
Single deep-maintainer; UI tested manually; extended-type scripting still manual-review;
heuristic tier exercised mainly by unit fixtures. Chronic, not acute — documentation
(TUTORIAL, VALIDATION) is the mitigation already in place.

### R9 — Secrets on workstation (LOW)
DeepSeek key + container SA password live in gitignored work/. Readable by anything
on the box; transcripts already saw the DeepSeek key once (rotate). No repo leakage
verified by check-ignore.

### R10 — Data copy, once built, points the wrong way (future)
Copy Data's whole danger is direction inversion (HQ overwritten by client).
Not yet built; when it is: profile pinning + direction banner + row-count preview +
per-table transaction are entry tickets, non-negotiable.

**Standing safety invariant across all of the above:** detection never trusts AI,
scripts never include deletions by default, execution never happens without rehearsal
plus a human, and everything an action touched lands in the ledger.
