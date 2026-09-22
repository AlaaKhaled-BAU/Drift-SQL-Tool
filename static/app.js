const logEl = document.getElementById("log");
const goBtn = document.getElementById("go");

let CURRENT_RUN_ID = null;
let CURRENT_WORKSPACES = {};       // direction -> index dict
let CURRENT_META = {};             // this run's meta.json (client_active_id lives here)
let ACTIVE_DIRECTION = null;
// "DEFAULT_CLIENT_HAS" (initial state + reapplied on every tab switch) means
// "added + modified, hide only_on_other" -- the tool's default daily job.
// null means "show everything" (explicit via a role card or Clear filters).
let ACTIVE_ROLE_FILTER = "DEFAULT_CLIENT_HAS";  // "added" | "modified" | "only_on_other" | "formatting_only" | "DEFAULT_CLIENT_HAS" | null
let ACTIVE_TYPE_FILTER = "";
let ACTIVE_SEARCH = "";
let SORT_COL = "priority", SORT_DIR = 1;
let SELECTED_FINDINGS = new Set();
const PAGE_SIZE = 200;
let CURRENT_PAGE = {};              // direction -> zero-based page index, independent per direction
let FILTERED_ROWS = {};             // direction -> full filtered+sorted findings (pre-pagination), for CSV export
// D4: persistent across findings/reloads -- reviewing 30 findings in a row
// shouldn't mean re-picking split/unified every single time.
let DIFF_VIEW_MODE = localStorage.getItem("driftDiffView") === "unified" ? "unified" : "split";
let ACTIVE_TOOL = "trimmer";
let IS_LIVE_SCAN = false;
let ACTIVE_COMPARE_SUBTAB = "schema";
let ACTIVE_CONSTRAINTS_ONLY = false;
let DATACOPY_TABLES = [];
let LAST_DRIFT_COPY_SQL = "";
let APPLY_INTERACTIVE_SESSION = null;
let APPLY_INTERACTIVE_WAITING = null;

const DIRECTION_LABEL = { client_to_105: "Client → 105", "105_to_client": "105 → Client" };
const ROLE_LABEL = {
  client_to_105: { added: "New on client", modified: "Changed on client", only_on_other: "Only on 105 (client behind)" },
  "105_to_client": { added: "Only on 105 (client missing it)", modified: "Changed", only_on_other: "New on client (not in 105)" },
};
const CHANGE_KIND_LABEL = {
  param: "Signature changed", body: "Logic changed", both: "Signature + logic changed",
  column: "Columns changed", formatting_only: "Formatting only", none: "No difference",
  settings: "Settings changed (ANSI_NULLS/QUOTED_IDENTIFIER)",
  structural: "Definition changed",
};
const REC_LABEL = {
  back_port: "Back-port", skip_likely_noise: "Likely noise — skip", needs_human_review: "Needs human review",
  client_customization_likely: "Likely client customization",
};
// Mirrors compare.PROGRAMMABLE_TYPES (Python) -- same hand-mirrored pattern
// already used for ROLE_LABEL/CHANGE_KIND_LABEL rather than fetching it.
const PROGRAMMABLE_TYPES_JS = new Set([
  "SqlProcedure", "SqlView", "SqlScalarFunction",
  "SqlInlineTableValuedFunction", "SqlMultiStatementTableValuedFunction",
  "SqlDmlTrigger", "SqlDatabaseDdlTrigger",
]);

function escapeHtml(s) {
  return (s ?? "").toString().replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
async function getJSON(url, opts) {
  const resp = await fetch(url, opts);
  const body = await resp.json();
  return { ok: resp.ok, body };
}

/* ============================== Lane E UI ergonomics (all ids/classes prefixed ub-) ============================== */

// classification buckets (drift/classify.py) -> chip color class
const UB_BUCKET_CLASS = {
  small: "ub-chip-small",
  gated_customization: "ub-chip-gated",
  major: "ub-chip-major",
  cosmetic: "ub-chip-cosmetic",
  irrelevant_to_client: "ub-chip-irrelevant",
};

function ubEscapeAttr(s) {
  return escapeHtml(s).replace(/"/g, "&quot;");
}

function ubScopeBadgeHtml(f) {
  const scope = f && f.scope;
  if (!scope || scope.irrelevant_to_client !== true) return "";
  const cid = scope.client_id === undefined || scope.client_id === null ? "?" : String(scope.client_id);
  const why = "differences live only in branches this client never executes";
  return `<span class="ub-scope-badge" tabindex="0" title="${ubEscapeAttr(why)}">irrelevant to client ${escapeHtml(cid)}</span>`;
}

function ubClassChipHtml(f) {
  const c = f && f.classification;
  if (!c || !c.bucket) return "";
  const conf = Number.isFinite(Number(c.confidence)) ? Number(c.confidence).toFixed(2) : String(c.confidence ?? "?");
  const tip = `bucket ${String(c.bucket)} · rule ${String(c.rule ?? "?")} · confidence ${conf}`;
  return `<span class="ub-class-chip ${UB_BUCKET_CLASS[c.bucket] || "ub-chip-irrelevant"}" title="${ubEscapeAttr(tip)}">${escapeHtml(String(c.bucket))}</span>`;
}

function ubGuardedRow(f) {
  const b = f && f.classification && f.classification.bucket;
  return b === "cosmetic" || b === "irrelevant_to_client";
}

function ubSaveFilters(direction) {
  if (!CURRENT_RUN_ID) return;
  try {
    sessionStorage.setItem(`${CURRENT_RUN_ID}:${direction}`, JSON.stringify({
      type: ACTIVE_TYPE_FILTER,
      search: ACTIVE_SEARCH,
      page: CURRENT_PAGE[direction] || 0,
      role: ACTIVE_ROLE_FILTER,
    }));
  } catch (_) { /* storage unavailable -- persistence silently off */ }
}

function ubLoadFilters(direction) {
  try {
    const raw = CURRENT_RUN_ID ? sessionStorage.getItem(`${CURRENT_RUN_ID}:${direction}`) : null;
    const v = raw ? JSON.parse(raw) : null;
    return v && typeof v === "object" ? v : {};
  } catch (_) { return {}; }
}

function ubClearSavedFilters(direction) {
  try { sessionStorage.removeItem(`${CURRENT_RUN_ID}:${direction}`); } catch (_) {}
}

async function ubBatchReview(direction, state) {
  const statusEl = document.getElementById(`ubStatus_${direction}`);
  const rows = FILTERED_ROWS[direction] || [];
  const targets = rows.filter(f => !ubGuardedRow(f));
  const guardedCount = rows.length - targets.length;
  if (!statusEl) return;
  if (!targets.length) {
    statusEl.textContent = guardedCount ? `${guardedCount} row(s), all guarded (cosmetic / irrelevant) — untouched` : "no rows in current filter";
    return;
  }
  const verb = state === "approved" ? "Approving" : "Clearing";
  let done = 0;
  for (const f of targets) {
    statusEl.textContent = `${verb}… ${done}/${targets.length}`;
    try {
      const resp = await fetch(`/api/run/${CURRENT_RUN_ID}/${direction}/review`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ finding_id: f.id, state }),
      });
      if (resp.ok) { f.review = state; done++; }
    } catch (_) { /* keep going; final count reports the shortfall */ }
    await new Promise(r => setTimeout(r, 25));
  }
  statusEl.textContent = `${verb} done: ${done}/${targets.length} → ${state}`
    + (guardedCount ? `, ${guardedCount} guarded row(s) skipped` : "");
  renderFindingsTable(direction);
}

function ubTruncate(s, n) {
  s = (s ?? "").toString();
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function ubRenderExecPanel(report) {
  const s = report.summary || {};
  const entries = Array.isArray(report.report) ? report.report : [];
  const benign = entries.filter(e => e.status === "benign");
  const fatal = entries.filter(e => e.status === "fatal");
  const entryRow = e => `<div class="ub-exec-row ${e.status === "fatal" ? "fatal" : "benign"}">
    <span class="ub-exec-class">${escapeHtml(String(e.class ?? "?"))}</span>
    <span class="ub-exec-msg" title="${ubEscapeAttr(String(e.msg ?? ""))}">${escapeHtml(ubTruncate(e.msg, 160))}</span>
  </div>`;
  return `
    <div class="ub-exec-head">
      <span class="ub-exec-title">Execution report</span>
      <span class="ub-exec-count ub-count-total"><b>${Number(s.total ?? entries.length)}</b> total</span>
      <span class="ub-exec-count ub-count-ok"><b>${Number(s.ok ?? 0)}</b> ok</span>
      <span class="ub-exec-count ub-count-benign"><b>${Number(s.benign ?? benign.length)}</b> benign-skipped</span>
      <span class="ub-exec-count ub-count-fatal"><b>${Number(s.fatal ?? fatal.length)}</b> fatal</span>
    </div>
    ${fatal.length ? `<div class="ub-exec-list">${fatal.map(entryRow).join("")}</div>` : ""}
    ${benign.length ? `<details class="ub-exec-detail">
      <summary>show ${benign.length} benign-skipped statement(s)</summary>
      <div class="ub-exec-list">${benign.map(entryRow).join("")}</div>
    </details>` : ""}
    ${!fatal.length && !benign.length ? `<div class="hint">${entries.length} statement(s) executed, nothing skipped or failed.</div>` : ""}`;
}

async function ubProbeExecReport(direction) {
  const el = document.getElementById(`ubExecPanel_${direction}`);
  if (!el || !CURRENT_RUN_ID) return;
  let body = null;
  try {
    const rel = direction + "/apply/execution_report.json";
    const url = `/api/run/${CURRENT_RUN_ID}/file?path=${encodeURIComponent(rel)}&optional=1`;
    const resp = await fetch(url);
    if (resp.ok && resp.status !== 204) {
      const parsed = JSON.parse(await resp.text());
      if (parsed && typeof parsed === "object" && parsed.summary) body = parsed;
    }
  } catch (_) { body = null; }
  if (!body) { el.style.display = "none"; el.innerHTML = ""; return; }
  el.innerHTML = ubRenderExecPanel(body);
  el.style.display = "block";
}

/* ============================== Run list (rail) ============================== */

async function loadRunList() {
  const { body } = await getJSON("/api/runs");
  const el = document.getElementById("runList");
  if (!body.length) { el.innerHTML = `<div class="rail-empty">No runs yet.</div>`; return; }
  el.innerHTML = body.map(r => {
    const c105 = r.counts.client_to_105, c105c = r.counts["105_to_client"];
    const summary = c105 ? `${c105.added + c105.modified + c105.only_on_other} finding(s)` :
                    (c105c ? `${c105c.added + c105c.modified + c105c.only_on_other} finding(s)` : "—");
    return `<div class="run-item" data-run="${r.run_id}">
      <div class="rn"><span>${escapeHtml(r.client)}</span><span class="kicker">${r.total_seconds ?? "?"}s</span></div>
      <div class="rd"><b>${summary}</b> vs ${escapeHtml(r.master)}</div>
    </div>`;
  }).join("");
  el.querySelectorAll(".run-item").forEach(item =>
    item.addEventListener("click", () => loadRun(item.dataset.run)));
}

async function loadRun(runId) {
  const { ok, body } = await getJSON(`/api/run/${runId}`);
  if (!ok) { appendLog("Could not load run: " + body.error, true); return; }
  IS_LIVE_SCAN = false;
  switchTool("compare");
  switchCompareSubtab("schema");
  document.getElementById("pickerSection").style.display = "none";
  document.getElementById("logSection").style.display = "none";
  document.getElementById("liveResults").style.display = "none";
  document.querySelectorAll(".run-item").forEach(el => el.classList.toggle("active", el.dataset.run === runId));
  renderResults(body.run_id, body.meta, body.workspaces);
  syncDriftFromRun();
}

document.getElementById("newRunBtn").addEventListener("click", () => {
  switchTool("compare");
  IS_LIVE_SCAN = false;
  document.getElementById("pickerSection").style.display = "block";
  document.getElementById("results").style.display = "none";
  document.getElementById("liveResults").style.display = "none";
  document.querySelectorAll(".run-item").forEach(el => el.classList.remove("active"));
  CURRENT_RUN_ID = null;
  updateCompareModeUi();
  syncDriftFromRun();
});

/* ============================== Picker ============================== */

const SELECTED_PATH = { master: null, client: null };
const BROWSE_STATE = { master: "", client: "" };

document.querySelectorAll(".picker-slot").forEach(slot => {
  const role = slot.dataset.role;
  slot.querySelectorAll(".picker-tab").forEach(tab => tab.addEventListener("click", () => {
    slot.querySelectorAll(".picker-tab").forEach(t => t.classList.toggle("active", t === tab));
    slot.querySelector(".picker-recent").style.display = tab.dataset.mode === "recent" ? "block" : "none";
    slot.querySelector(".picker-browse").style.display = tab.dataset.mode === "browse" ? "block" : "none";
    if (tab.dataset.mode === "browse") browseTo(role, BROWSE_STATE[role]);
  }));
  slot.querySelector(`#recent_${role}`).addEventListener("change", e => {
    if (e.target.value) selectFile(role, e.target.value, e.target.selectedOptions[0].textContent.trim());
  });
});

async function browseTo(role, path) {
  BROWSE_STATE[role] = path;
  const slot = document.getElementById(`slot_${role}`);
  const crumbEl = slot.querySelector(".browse-crumb");
  const listEl = slot.querySelector(".browse-list");
  listEl.innerHTML = `<div class="browse-empty">Loading…</div>`;

  const { ok, body } = await getJSON(`/api/browse?path=${encodeURIComponent(path)}`);
  if (!ok) { listEl.innerHTML = `<div class="browse-empty">${escapeHtml(body.error)}</div>`; return; }

  const parts = body.cwd ? body.cwd.split("/") : [];
  let acc = "";
  const crumbs = [`<span class="seg" data-p="">device root</span>`];
  parts.forEach(part => { acc = acc ? `${acc}/${part}` : part; crumbs.push(`<span class="seg" data-p="${escapeHtml(acc)}">${escapeHtml(part)}</span>`); });
  crumbEl.innerHTML = crumbs.join(" / ");
  crumbEl.querySelectorAll(".seg").forEach(seg => seg.addEventListener("click", () => browseTo(role, seg.dataset.p)));

  const rows = [];
  if (body.parent !== null) rows.push(`<div class="browse-row" data-nav="${escapeHtml(body.parent)}"><span class="ic">↰</span><span class="nm">.. (up)</span></div>`);
  body.dirs.forEach(d => {
    const p = body.cwd ? `${body.cwd}/${d}` : d;
    rows.push(`<div class="browse-row" data-nav="${escapeHtml(p)}"><span class="ic">📁</span><span class="nm">${escapeHtml(d)}</span></div>`);
  });
  body.baks.forEach(b => {
    rows.push(`<div class="browse-row bak" data-select="${escapeHtml(b.abs_path)}" data-label="${escapeHtml(b.name)} (${b.size_mb} MB)">
      <span class="ic">◇</span><span class="nm">${escapeHtml(b.name)}</span><span class="sz">${b.size_mb} MB</span></div>`);
  });
  listEl.innerHTML = rows.join("") || `<div class="browse-empty">No subfolders or .bak files here.</div>`;
  listEl.querySelectorAll("[data-nav]").forEach(r => r.addEventListener("click", () => browseTo(role, r.dataset.nav)));
  listEl.querySelectorAll("[data-select]").forEach(r => r.addEventListener("click", () => selectFile(role, r.dataset.select, r.dataset.label)));
}

function selectFile(role, path, label) {
  SELECTED_PATH[role] = path;
  const slot = document.getElementById(`slot_${role}`);
  const chip = slot.querySelector(".selected-chip");
  chip.style.display = "flex";
  chip.innerHTML = `<span>✓</span><span>${escapeHtml(label)}</span><span class="x" data-clear>✕</span>`;
  chip.querySelector("[data-clear]").addEventListener("click", (e) => {
    e.stopPropagation(); SELECTED_PATH[role] = null; chip.style.display = "none";
  });
}

/* ============================== Run a comparison ============================== */

function appendLog(text, isErr) {
  const line = document.createElement("div");
  line.className = isErr ? "log-line log-err" : "log-line";
  line.textContent = text;
  logEl.appendChild(line);
  logEl.scrollTop = logEl.scrollHeight;
}

goBtn.addEventListener("click", async () => {
  const master = SELECTED_PATH.master;
  const client = SELECTED_PATH.client;
  const directions = [];
  if (document.getElementById("dirC105").checked) directions.push("client_to_105");
  if (document.getElementById("dir105C").checked) directions.push("105_to_client");
  if (!master || !client) { alert("Pick both a Master (105) and a Client backup file."); return; }
  if (!directions.length) { alert("Pick at least one direction."); return; }

  // D5a: all-checked is sent as null (no filter, a clean full run) rather
  // than the full list -- keeps "no filter" unambiguous server-side instead
  // of relying on "happens to list every category" meaning the same thing.
  const allTypeBoxes = Array.from(document.querySelectorAll(".typeFilterBox"));
  const checkedTypes = allTypeBoxes.filter(b => b.checked).map(b => b.value);
  if (!checkedTypes.length) { alert("Select at least one object type to examine."); return; }
  const typeFilter = checkedTypes.length === allTypeBoxes.length ? null : checkedTypes;

  const cidEl = document.getElementById("compareClientActiveId");
  const clientActiveId = cidEl && cidEl.value ? cidEl.value : null;

  IS_LIVE_SCAN = false;
  logEl.innerHTML = "";
  document.getElementById("logSection").style.display = "block";
  document.getElementById("results").style.display = "none";
  document.getElementById("liveResults").style.display = "none";
  goBtn.disabled = true;
  goBtn.textContent = "Running…";

  const { ok, body } = await getJSON("/api/compare", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ master, client, directions, type_filter: typeFilter, client_active_id: clientActiveId }),
  });
  if (!ok) {
    appendLog("ERROR: " + body.error, true);
    goBtn.disabled = false; goBtn.textContent = "Compare";
    return;
  }

  const es = new EventSource(`/api/stream/${body.job_id}`);
  es.addEventListener("log", (e) => appendLog(JSON.parse(e.data)));
  es.addEventListener("result", (e) => {
    const result = JSON.parse(e.data);
    document.getElementById("pickerSection").style.display = "none";
    renderResults(result.run_id, result.meta, result.workspaces);
    syncDriftFromRun();
    es.close();
    goBtn.disabled = false; goBtn.textContent = "Compare";
    loadRunList();
  });
  es.addEventListener("error", (e) => {
    if (e.data) appendLog("FAILED: " + JSON.parse(e.data), true);
    es.close();
    goBtn.disabled = false; goBtn.textContent = "Compare";
  });
});

/* ============================== Results / workspace ============================== */

function renderResults(runId, meta, workspaces) {
  CURRENT_RUN_ID = runId;
  CURRENT_WORKSPACES = workspaces;
  CURRENT_META = meta || {};
  IS_LIVE_SCAN = false;
  document.getElementById("results").style.display = "block";
  updateCompareModeUi();

  renderRunWarnings(meta);

  const directions = Object.keys(workspaces);
  const tabs = document.getElementById("tabs");
  tabs.innerHTML = directions.map(d =>
    `<div class="tab" data-dir="${d}">${DIRECTION_LABEL[d] || d}</div>`).join("");
  tabs.querySelectorAll(".tab").forEach(t =>
    t.addEventListener("click", () => switchWorkspace(t.dataset.dir)));

  // D5d: the direction NOT yet computed for this run is a ~15-60s re-compare
  // away (cached .dacpac pair, no restore) rather than a full ~4min re-run --
  // offered right next to the tabs since "add the other direction" is the
  // single most common reason to want one.
  const missing = ["client_to_105", "105_to_client"].filter(d => !directions.includes(d));
  if (missing.length) {
    tabs.innerHTML += missing.map(d =>
      `<button class="tab-recompare" data-dir="${d}">+ ${DIRECTION_LABEL[d]} (re-compare, ~30s)</button>`).join("");
    tabs.querySelectorAll(".tab-recompare").forEach(btn =>
      btn.addEventListener("click", () => runRecompare(runId, btn.dataset.dir, btn)));
  }

  const wsRoot = document.getElementById("workspaces");
  wsRoot.innerHTML = directions.map(d => `<div class="workspace" id="ws_${d}"></div>`).join("");

  const links = [
    ["sql_master", "Master .sql"], ["sql_client", "Client .sql"],
    ["dacpac_master", "Master .dacpac"], ["dacpac_client", "Client .dacpac"],
  ];
  document.getElementById("downloads").innerHTML = links.map(([key, label]) =>
    `<a href="/api/download/${runId}/${key}" target="_blank">${label}</a>`).join("");

  switchWorkspace(directions[0]);
}

async function runRecompare(runId, direction, btn) {
  const originalLabel = btn.textContent;
  btn.disabled = true;
  btn.textContent = `Re-comparing ${DIRECTION_LABEL[direction] || direction}…`;
  document.getElementById("logSection").style.display = "block";
  appendLog(`--- re-compare ${DIRECTION_LABEL[direction] || direction}: reusing cached .dacpac pair, no restore ---`);

  const { ok, body } = await getJSON(`/api/run/${runId}/recompare`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ direction }),
  });
  if (!ok) {
    appendLog("ERROR: " + body.error, true);
    btn.disabled = false; btn.textContent = originalLabel;
    return;
  }

  const es = new EventSource(`/api/stream/${body.job_id}`);
  es.addEventListener("log", (e) => appendLog(JSON.parse(e.data)));
  es.addEventListener("result", (e) => {
    const result = JSON.parse(e.data);
    es.close();
    renderResults(result.run_id, result.meta, result.workspaces);
    switchWorkspace(direction);
    loadRunList();
  });
  es.addEventListener("error", (e) => {
    if (e.data) appendLog("FAILED: " + JSON.parse(e.data), true);
    es.close();
    btn.disabled = false; btn.textContent = originalLabel;
  });
}

function renderRunWarnings(meta) {
  const el = document.getElementById("runWarnings");
  const parts = [];
  const enc = meta.encrypted_objects || {};
  const encCount = (enc.master || []).length + (enc.client || []).length;
  if (encCount) {
    parts.push(`<div class="run-warning">⚠ ${encCount} encrypted object(s) found (${(enc.master||[]).length} master, ${(enc.client||[]).length} client) --
      definition is unreadable (WITH ENCRYPTION), so these cannot be verified as same/changed by this tool. Never treat them as "clean".</div>`);
  }
  const dbo = meta.db_options;
  if (dbo && dbo.match === false) {
    parts.push(`<div class="run-warning">⚠ Database options differ -- master: ${escapeHtml(JSON.stringify(dbo.master))},
      client: ${escapeHtml(JSON.stringify(dbo.client))}. Collation/compatibility-level drift changes runtime behavior
      even when object text matches.</div>`);
  }
  el.innerHTML = parts.join("");
}

function switchWorkspace(direction) {
  ACTIVE_DIRECTION = direction;
  ACTIVE_ROLE_FILTER = "DEFAULT_CLIENT_HAS";
  const saved = ubLoadFilters(direction);
  ACTIVE_TYPE_FILTER = saved.type || "";
  ACTIVE_SEARCH = saved.search || "";
  CURRENT_PAGE[direction] = Math.max(0, Number(saved.page) || 0);
  SELECTED_FINDINGS = new Set();
  document.querySelectorAll(".tab").forEach(t => t.classList.toggle("active", t.dataset.dir === direction));
  document.querySelectorAll(".workspace").forEach(w => w.classList.toggle("active", w.id === `ws_${direction}`));
  renderWorkspace(direction);
}

// D6: report_writer.py computes the additive score at write time now (so
// index.json carries it and metrics.py can reason about it) -- this just
// reads it. Falls back to the old crude rule only for a run written before
// D6 landed (no priority field in its index.json at all).
function priorityOf(f) {
  if (f.priority) return f.priority;
  if (f.category === "formatting_only" || f.category === "no_difference") return "low";
  const cf = f.columns_flags;
  if ((f.callers && f.callers.count > 5) || (cf && (cf.removed || cf.retyped))) return "high";
  return "medium";
}
function priorityTitle(f) {
  if (!f.priority_breakdown || !f.priority_breakdown.length) return `${priorityOf(f)} priority (score ${f.priority_score ?? "?"})`;
  const lines = f.priority_breakdown.map(([signal, pts]) => `${pts > 0 ? "+" : ""}${pts}  ${signal}`);
  return `${priorityOf(f)} priority — score ${f.priority_score}\n${lines.join("\n")}`;
}
const PRIO_RANK = { high: 0, medium: 1, low: 2 };

function renderWorkspace(direction) {
  const idx = CURRENT_WORKSPACES[direction];
  const c = idx.counts;
  const root = document.getElementById(`ws_${direction}`);
  const labels = ROLE_LABEL[direction] || {};

  const cardDefs = [
    ["added", labels.added || "Added", c.added], ["modified", labels.modified || "Modified", c.modified],
    ["only_on_other", labels.only_on_other || "Only on other side", c.only_on_other],
    ["formatting_only", "Formatting only", c.formatting_only],
    ["no_difference", "No difference", c.no_difference],
  ];
  const typeOptions = Object.keys(idx.by_type || {}).sort();
  // D5a: critical honesty requirement -- a type-filtered run must never be
  // mistakable for a clean full run, including (especially) when it also
  // happens to show zero findings for whatever WAS examined.
  const filterBanner = idx.type_filter
    ? `<div class="run-warning">⚠ PARTIAL RUN -- type filter active: examined ${idx.type_filter.join(", ")} only.
        ${c.filtered_out} object(s) not examined because of this filter. This is not a clean full comparison.</div>`
    : "";

  if (!idx.findings.length) {
    root.innerHTML = `${filterBanner}<div class="ub-exec-panel" id="ubExecPanel_${direction}" style="display:none;"></div><div class="empty-state">No structural drift in this direction. (${c.documentation} documentation-only, ${c.cascading} cascading, ${c.excluded} excluded — not shown as drift.)</div>`;
    ubProbeExecReport(direction);
    return;
  }

  root.innerHTML = `
    ${filterBanner}
    <div class="ub-exec-panel" id="ubExecPanel_${direction}" style="display:none;"></div>
    <div id="defaultFilterBanner_${direction}"></div>
    <div class="cards" id="cards_${direction}">
      ${cardDefs.map(([role, label, n]) =>
        `<div class="card" data-role="${role}"><div class="n">${n}</div><div class="l">${label}</div></div>`).join("")}
    </div>
    <div class="noise">Not counted above (shown separately, not drift): ${c.documentation} documentation-only,
      ${c.cascading} cascading refresh, ${c.excluded} known client-named object(s) excluded.</div>
    ${idx.lost_fixes && idx.lost_fixes.length ? renderLostFixes(idx.lost_fixes) : ""}
    <div class="batch-bar" id="batchBar_${direction}">
      <span><b id="batchCount_${direction}">0</b> selected</span>
      <button class="ai sm" id="batchAiBtn_${direction}">✦ Ask AI about selected</button>
      <button class="ghost sm" id="batchClearBtn_${direction}">Clear</button>
    </div>
    <div class="filters">
      <select id="typeFilter_${direction}"><option value="">All types</option>
        ${typeOptions.map(t => `<option value="${t}">${t} (${idx.by_type[t]})</option>`).join("")}</select>
      <input type="text" id="search_${direction}" placeholder="Search by name…">
      <button class="ghost sm" id="clearFilter_${direction}">Clear filters</button>
      <button class="ghost sm" id="exportCsvBtn_${direction}">Export filtered to CSV</button>
      <span class="ub-bucket-toolbar">
        <button class="ghost sm" id="ubSelectAll_${direction}" title="approve every row in the current filter (skips cosmetic / irrelevant-to-client rows)">Select All</button>
        <button class="ghost sm" id="ubSelectNone_${direction}" title="reset every row in the current filter to pending (skips cosmetic / irrelevant-to-client rows)">Select None</button>
        <span class="ub-bucket-status" id="ubStatus_${direction}"></span>
      </span>
      <span class="count" id="shownCount_${direction}"></span>
    </div>
    <table id="findingsTable_${direction}">
      <thead><tr>
        <th class="select-col" title="select multiple findings to batch-ask AI at once"></th>
        <th data-sort="priority">Priority</th>
        <th data-sort="role">Role</th>
        <th data-sort="type">Type</th>
        <th data-sort="name">Object</th>
        <th>Summary</th>
        <th data-sort="callers">Callers</th>
        <th data-sort="review">Review</th>
      </tr></thead>
      <tbody></tbody>
    </table>
    <div class="pagination" id="pagination_${direction}"></div>
    <div id="detail_${direction}"></div>
    <section>
      <h2>Assemble apply script (approved findings only, additive)</h2>
      <label style="display:inline-flex;align-items:center;gap:6px;font-weight:normal;font-size:12.5px;">
        <input type="checkbox" id="includeDeletions_${direction}"> include deletions (off by default — never drops the other side's objects unless checked)
      </label>
      <button class="ghost sm" id="assembleBtn_${direction}" style="margin-left:10px;">Assemble</button>
      <button class="ghost sm" id="rehearseBtn_${direction}" style="margin-left:6px;">Rehearse</button>
      <button class="ghost sm" id="copyApplyBtn_${direction}" style="margin-left:6px;display:none;">Copy script</button>
      ${direction === "105_to_client" ? `<button class="ghost sm" id="applyClientBtn_${direction}" style="margin-left:6px;display:none;">Apply to client (interactive)</button>` : ""}
      <div id="rehearseResidue_${direction}" class="hint"></div>
      <div id="applyLiveNote_${direction}" class="run-warning" style="display:none;margin-top:8px;">Apply disabled — live scan is preview-only. Run a <code>.bak</code> compare to assemble client-targeted scripts.</div>
      <div id="applyOut_${direction}"></div>
    </section>

    <section>
      <h2>Quality scorecard (computed from this run's own evidence, not self-reported)</h2>
      <button class="ghost sm" id="metricsBtn_${direction}">Compute metrics</button>
      <span class="hint" style="margin-left:10px;">re-draws an independent random sample each click — click again for a second opinion</span>
      <div id="metricsOut_${direction}"></div>
    </section>

    <section>
      <h2>AI connection</h2>
      <button class="ghost sm" id="testAiBtn_${direction}">Test AI connection</button>
      <span id="testAiOut_${direction}" class="hint" style="margin-left:10px;"></span>
    </section>
  `;

  root.querySelectorAll(".card").forEach(card => card.addEventListener("click", () => {
    ACTIVE_ROLE_FILTER = ACTIVE_ROLE_FILTER === card.dataset.role ? null : card.dataset.role;
    CURRENT_PAGE[direction] = 0;
    renderFindingsTable(direction);
  }));
  root.querySelectorAll("th[data-sort]").forEach(th => th.addEventListener("click", () => {
    const col = th.dataset.sort;
    SORT_DIR = (SORT_COL === col) ? -SORT_DIR : 1;
    SORT_COL = col;
    CURRENT_PAGE[direction] = 0;
    renderFindingsTable(direction);
  }));
  document.getElementById(`typeFilter_${direction}`).addEventListener("change", e => {
    ACTIVE_TYPE_FILTER = e.target.value; CURRENT_PAGE[direction] = 0; renderFindingsTable(direction);
  });
  document.getElementById(`search_${direction}`).addEventListener("input", e => {
    ACTIVE_SEARCH = e.target.value.toLowerCase(); CURRENT_PAGE[direction] = 0; renderFindingsTable(direction);
  });
  document.getElementById(`clearFilter_${direction}`).addEventListener("click", () => {
    ACTIVE_ROLE_FILTER = null; ACTIVE_TYPE_FILTER = ""; ACTIVE_SEARCH = "";
    document.getElementById(`typeFilter_${direction}`).value = "";
    document.getElementById(`search_${direction}`).value = "";
    CURRENT_PAGE[direction] = 0;
    ubClearSavedFilters(direction);
    renderFindingsTable(direction);
  });
  const assembleBtn = document.getElementById(`assembleBtn_${direction}`);
  assembleBtn.addEventListener("click", () => assembleApply(direction));
  document.getElementById(`rehearseBtn_${direction}`)?.addEventListener("click", () => runRehearse(direction));
  if (IS_LIVE_SCAN) {
    assembleBtn.disabled = true;
    const note = document.getElementById(`applyLiveNote_${direction}`);
    if (note) note.style.display = "block";
  }
  document.getElementById(`copyApplyBtn_${direction}`).addEventListener("click", () => {
    const pre = document.querySelector(`#applyOut_${direction} pre`);
    if (pre && pre.textContent) navigator.clipboard.writeText(pre.textContent);
  });
  const applyClientBtn = document.getElementById(`applyClientBtn_${direction}`);
  if (applyClientBtn) {
    applyClientBtn.addEventListener("click", () => startInteractiveApply(direction));
    if (IS_LIVE_SCAN) applyClientBtn.style.display = "none";
  }
  document.getElementById(`metricsBtn_${direction}`).addEventListener("click", () => computeMetrics(direction));
  document.getElementById(`testAiBtn_${direction}`).addEventListener("click", () => testAiConnection(direction));
  document.getElementById(`batchAiBtn_${direction}`).addEventListener("click", () => askAiBatch(direction));
  document.getElementById(`exportCsvBtn_${direction}`).addEventListener("click", () => exportFilteredCsv(direction));
  document.getElementById(`batchClearBtn_${direction}`).addEventListener("click", () => {
    SELECTED_FINDINGS = new Set(); renderFindingsTable(direction);
  });
  document.getElementById(`ubSelectAll_${direction}`).addEventListener("click", () => ubBatchReview(direction, "approved"));
  document.getElementById(`ubSelectNone_${direction}`).addEventListener("click", () => ubBatchReview(direction, "pending"));

  const savedFilters = ubLoadFilters(direction);
  if (savedFilters.type) ACTIVE_TYPE_FILTER = savedFilters.type;
  if (savedFilters.search) ACTIVE_SEARCH = savedFilters.search;
  if (savedFilters.role !== undefined) ACTIVE_ROLE_FILTER = savedFilters.role;
  document.getElementById(`typeFilter_${direction}`).value = ACTIVE_TYPE_FILTER || "";
  const searchInput = document.getElementById(`search_${direction}`);
  searchInput.value = ACTIVE_SEARCH || "";
  if (!Number.isNaN(Number(savedFilters.page))) CURRENT_PAGE[direction] = Math.max(0, Number(savedFilters.page) || 0);

  renderFindingsTable(direction);
  ubProbeExecReport(direction);
}

function renderLostFixes(lostFixes) {
  return `<div class="lostfix"><h3>⚠ Possible lost fixes</h3>` +
    lostFixes.map(f =>
      `<div>[${f.side}] ${f.object} — logged by ${f.logged_by} at ${f.logged_at}, but current definition no longer matches that logged change.</div>`
    ).join("") + `</div>`;
}

function renderFindingsTable(direction) {
  const idx = CURRENT_WORKSPACES[direction];
  let rows = idx.findings;
  if (ACTIVE_ROLE_FILTER === "DEFAULT_CLIENT_HAS") {
    rows = rows.filter(f => (f.role === "added" || f.role === "modified")
      && f.category !== "formatting_only" && f.category !== "no_difference");
  } else if (ACTIVE_ROLE_FILTER) {
    if (ACTIVE_ROLE_FILTER === "formatting_only") rows = rows.filter(f => f.category === "formatting_only");
    else if (ACTIVE_ROLE_FILTER === "no_difference") rows = rows.filter(f => f.category === "no_difference");
    else rows = rows.filter(f => f.role === ACTIVE_ROLE_FILTER && f.category !== "formatting_only" && f.category !== "no_difference");
  }
  if (ACTIVE_TYPE_FILTER) rows = rows.filter(f => f.type === ACTIVE_TYPE_FILTER);
  if (ACTIVE_CONSTRAINTS_ONLY) rows = rows.filter(f => (f.type || "").includes("Constraint"));
  if (ACTIVE_SEARCH) rows = rows.filter(f => f.bare_name.toLowerCase().includes(ACTIVE_SEARCH));

  const sortKey = f => {
    switch (SORT_COL) {
      case "priority": return PRIO_RANK[priorityOf(f)];
      case "role": return f.category === "formatting_only" ? "formatting" : f.category === "no_difference" ? "no_difference" : f.role;
      case "type": return f.type;
      case "name": return f.bare_name.toLowerCase();
      case "callers": return -(f.callers ? f.callers.count : 0);
      case "review": return f.review;
      default: return 0;
    }
  };
  rows = rows.slice().sort((a, b) => {
    const ka = sortKey(a), kb = sortKey(b);
    const cmp = ka < kb ? -1 : ka > kb ? 1 : a.bare_name.localeCompare(b.bare_name);
    return cmp * SORT_DIR;
  });

  document.querySelectorAll(`#cards_${direction} .card`).forEach(card =>
    card.classList.toggle("active-filter", ACTIVE_ROLE_FILTER === "DEFAULT_CLIENT_HAS"
      ? (card.dataset.role === "added" || card.dataset.role === "modified")
      : card.dataset.role === ACTIVE_ROLE_FILTER));

  const bannerEl = document.getElementById(`defaultFilterBanner_${direction}`);
  if (bannerEl) {
    bannerEl.innerHTML = ACTIVE_ROLE_FILTER === "DEFAULT_CLIENT_HAS"
      ? `<div class="run-warning">Showing what the client has that 105 doesn't (added + changed).
          <a href="#" data-show-all="${direction}">Show everything, including "only on 105"</a></div>`
      : "";
    bannerEl.querySelectorAll("[data-show-all]").forEach(a => a.addEventListener("click", (e) => {
      e.preventDefault();
      ACTIVE_ROLE_FILTER = null; CURRENT_PAGE[direction] = 0;
      renderFindingsTable(direction);
    }));
  }
  document.querySelectorAll(`#findingsTable_${direction} th[data-sort]`).forEach(th =>
    th.querySelector(".arrow")?.remove());
  const activeTh = document.querySelector(`#findingsTable_${direction} th[data-sort="${SORT_COL}"]`);
  if (activeTh) activeTh.insertAdjacentHTML("beforeend", `<span class="arrow">${SORT_DIR > 0 ? "▲" : "▼"}</span>`);

  // D6: real paging replaces the old flat rows.slice(0, 500) -- 552 of 1052
  // findings were unreachable on a real pair under that cap. FILTERED_ROWS
  // (the full filtered+sorted set, pre-pagination) is cached per direction
  // so exportFilteredCsv() reuses the exact same rows the table shows,
  // just without the page slice.
  FILTERED_ROWS[direction] = rows;
  const pageCount = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
  const page = Math.min(CURRENT_PAGE[direction] || 0, pageCount - 1);
  CURRENT_PAGE[direction] = page;
  const shown = rows.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);
  const tbody = document.querySelector(`#findingsTable_${direction} tbody`);
  tbody.innerHTML = shown.map(f => {
    const roleLabel = f.category === "formatting_only" ? "formatting" : f.category === "no_difference" ? "no difference" :
      ((ROLE_LABEL[direction] || {})[f.role] || f.role.replace(/_/g, " "));
    // no_difference reuses the "formatting" tag's neutral gray styling (same
    // meaning: flagged, but not real drift) rather than adding a new CSS class.
    const roleTag = f.category === "formatting_only" ? "formatting" : f.category === "no_difference" ? "formatting" : f.role;
    const prio = priorityOf(f);
    const callerTxt = f.callers && f.callers.count ? `${f.callers.count}` : "–";
    return `
    <tr class="finding-row ${SELECTED_FINDINGS.has(f.id) ? "selected-row" : ""} ${f.review === "approved" ? "row-approved" : ""}" data-id="${f.id}" data-dir="${direction}">
      <td class="select-col"><input type="checkbox" data-select-finding="${f.id}" ${SELECTED_FINDINGS.has(f.id) ? "checked" : ""}></td>
      <td><span class="prio ${prio}" title="${escapeHtml(priorityTitle(f))}"></span></td>
      <td><span class="tag ${roleTag}">${roleLabel}</span></td>
      <td>${escapeHtml(f.type)}</td>
      <td class="mono">${escapeHtml(f.bare_name)}${ubScopeBadgeHtml(f)}</td>
      <td>${ubClassChipHtml(f)}${escapeHtml(f.summary || (CHANGE_KIND_LABEL[f.change_kind] || ""))}</td>
      <td class="caller-badge">${callerTxt}</td>
      <td class="rev-${f.review}">${f.review}</td>
    </tr>`;
  }).join("") || (ACTIVE_ROLE_FILTER === "DEFAULT_CLIENT_HAS"
    ? `<tr><td colspan="8">No findings match this filter — client and 105 don't differ in anything the client
        added or changed. <a href="#" data-show-all="${direction}">Show everything, including "only on 105"</a></td></tr>`
    : `<tr><td colspan="8">No findings match this filter.</td></tr>`);

  const rangeStart = rows.length ? page * PAGE_SIZE + 1 : 0;
  ubSaveFilters(direction);
  const rangeEnd = Math.min((page + 1) * PAGE_SIZE, rows.length);
  document.getElementById(`shownCount_${direction}`).textContent =
    rows.length ? `Showing ${rangeStart}–${rangeEnd} of ${rows.length}` : "0 shown";

  const pager = document.getElementById(`pagination_${direction}`);
  if (pageCount > 1) {
    pager.style.display = "flex";
    pager.innerHTML = `
      <button class="ghost sm" id="prevPage_${direction}" ${page === 0 ? "disabled" : ""}>← Prev</button>
      <span>Page ${page + 1} of ${pageCount}</span>
      <button class="ghost sm" id="nextPage_${direction}" ${page >= pageCount - 1 ? "disabled" : ""}>Next →</button>`;
    document.getElementById(`prevPage_${direction}`).addEventListener("click", () => {
      CURRENT_PAGE[direction] = Math.max(0, page - 1);
      renderFindingsTable(direction);
    });
    document.getElementById(`nextPage_${direction}`).addEventListener("click", () => {
      CURRENT_PAGE[direction] = Math.min(pageCount - 1, page + 1);
      renderFindingsTable(direction);
    });
  } else {
    pager.style.display = "none";
    pager.innerHTML = "";
  }

  tbody.querySelectorAll("[data-show-all]").forEach(a => a.addEventListener("click", (e) => {
    e.preventDefault();
    ACTIVE_ROLE_FILTER = null; CURRENT_PAGE[direction] = 0;
    renderFindingsTable(direction);
  }));
  tbody.querySelectorAll("tr.finding-row").forEach(tr => {
    tr.addEventListener("click", (e) => {
      if (e.target.matches("[data-select-finding]")) return;
      showDetail(direction, tr.dataset.id);
    });
    tr.tabIndex = 0;
    tr.addEventListener("keydown", (e) => {
      if (e.code === "Space" && !e.target.matches("input,button,select,textarea")) {
        e.preventDefault();
        const cb = tr.querySelector("[data-select-finding]");
        if (!cb) return;
        cb.checked = !cb.checked;
        cb.dispatchEvent(new Event("change", { bubbles: true }));
        const id = cb.dataset.selectFinding;
        if (cb.checked) SELECTED_FINDINGS.add(id); else SELECTED_FINDINGS.delete(id);
        const bar = document.getElementById(`batchBar_${direction}`);
        bar.classList.toggle("show", SELECTED_FINDINGS.size > 0);
        document.getElementById(`batchCount_${direction}`).textContent = SELECTED_FINDINGS.size;
        tr.classList.toggle("selected-row", cb.checked);
      }
    });
    tr.querySelector("[data-select-finding]").addEventListener("click", (e) => {
      e.stopPropagation();
      const id = e.target.dataset.selectFinding;
      if (e.target.checked) SELECTED_FINDINGS.add(id); else SELECTED_FINDINGS.delete(id);
      const bar = document.getElementById(`batchBar_${direction}`);
      bar.classList.toggle("show", SELECTED_FINDINGS.size > 0);
      document.getElementById(`batchCount_${direction}`).textContent = SELECTED_FINDINGS.size;
      tr.classList.toggle("selected-row", e.target.checked);
    });
  });
}

async function runRehearse(direction) {
  if (IS_LIVE_SCAN || !CURRENT_RUN_ID) return;
  const residueEl = document.getElementById(`rehearseResidue_${direction}`);
  if (residueEl) residueEl.textContent = "Rehearsing…";
  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/rehearse`, { method: "POST" });
  if (!ok) {
    if (residueEl) residueEl.textContent = body.error || "rehearse failed";
    return;
  }
  const v = body.verification;
  if (residueEl) {
    if (v && v.residue_counts) {
      residueEl.textContent = `Post-rehearse residue counts: ${JSON.stringify(v.residue_counts)}`;
    } else if (v && v.error) {
      residueEl.textContent = `Rehearse done; reverify: ${v.error}`;
    } else {
      residueEl.textContent = "Rehearse finished (see execution report on disk).";
    }
  }
}

function _csvCell(v) {
  const s = (v ?? "").toString();
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function exportFilteredCsv(direction) {
  const rows = FILTERED_ROWS[direction] || [];
  const header = ["priority", "priority_score", "role", "category", "type", "object", "summary", "callers", "review"];
  const lines = [header.join(",")];
  for (const f of rows) {
    lines.push([
      priorityOf(f), f.priority_score ?? "", f.role, f.category, f.type, f.bare_name,
      f.summary || "", f.callers ? f.callers.count : 0, f.review,
    ].map(_csvCell).join(","));
  }
  const blob = new Blob([lines.join("\n")], { type: "text/csv" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${CURRENT_RUN_ID}_${direction}_findings.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

/* ============================== Detail pane + rich diff ============================== */

async function showDetail(direction, findingId) {
  const idx = CURRENT_WORKSPACES[direction];
  const f = idx.findings.find(x => x.id === findingId);
  const detailEl = document.getElementById(`detail_${direction}`);
  detailEl.style.display = "block";

  // Port-to-105 only for: client-to-105 direction, client actually changed the
  // body (modified+structural), and a programmable type (statements.py/
  // scriptgen.py's merge support). Not "added" (a wholly-new object already
  // gets a clean CREATE via the existing Apply flow -- nothing to merge into).
  const showPortButton = direction === "client_to_105" && f.role === "modified"
    && f.category === "structural" && PROGRAMMABLE_TYPES_JS.has(f.type);

  const roleLabel = f.category === "formatting_only" ? "formatting" : f.category === "no_difference" ? "no difference" :
    ((ROLE_LABEL[direction] || {})[f.role] || f.role);
  const attribHtml = (f.attribution || []).length
    ? `<div class="detail-meta"><b>Attribution:</b> ${f.attribution.map(a => `[${a.side}] ${a.event} by ${a.login || "?"} at ${a.when}`).join(" · ")}</div>`
    : "";
  const callersHtml = f.callers && f.callers.count
    ? `<div class="detail-meta"><b>Blast radius:</b> ${f.callers.count} caller(s) — ${f.callers.names.join(", ")}${f.callers.unresolved ? ` (+${f.callers.unresolved} unresolved)` : ""}</div>`
    : `<div class="detail-meta"><b>Blast radius:</b> no known callers found</div>`;

  detailEl.innerHTML = `
    <div class="detail-head">
      <span class="obj-name">${escapeHtml(f.name)}</span>
      <span class="tag ${f.category === "formatting_only" || f.category === "no_difference" ? "formatting" : f.role}">${roleLabel}</span>
      <span class="prio ${priorityOf(f)}" title="${escapeHtml(priorityTitle(f))}"></span>
    </div>
    <div class="detail-summary">${escapeHtml(f.summary || (CHANGE_KIND_LABEL[f.change_kind] || ""))}${f.change_kind ? ` — <i>${CHANGE_KIND_LABEL[f.change_kind] || f.change_kind}</i>` : ""}</div>
    ${attribHtml}${callersHtml}
    ${f.type !== "SqlTable" ? `<div class="diff-view-toggle">
      <button class="view-toggle-btn${DIFF_VIEW_MODE === "split" ? " active" : ""}" data-view="split">Split</button>
      <button class="view-toggle-btn${DIFF_VIEW_MODE === "unified" ? " active" : ""}" data-view="unified">Unified</button>
    </div>` : ""}
    ${f.statement_map ? `<div id="stmtMap_${direction}_${findingId}">Loading statement map…</div>` : ""}
    <div id="richdiff_${direction}_${findingId}">Loading diff…</div>
    <div id="aiSlot_${direction}_${findingId}"></div>
    ${showPortButton ? `<div class="port-105-row">
      <button class="ai" id="portTo105Btn_${direction}_${findingId}">⇒ Port to 105 (AI-assisted merge)</button>
      <span class="hint">sends this finding's changed statements to DeepSeek and proposes how to fold them into 105's current body as an @ClientActive branch — nothing is applied until you review and accept it below</span>
      <div id="mergeSlot_${direction}_${findingId}"></div>
    </div>` : ""}
    <div class="actions">
      <button data-state="approved">Approve</button>
      <button class="ghost" data-state="skipped">Skip</button>
      <button class="ghost" data-state="needs_review">Needs review</button>
      <button class="ai" id="askAiBtn_${findingId}">✦ Ask AI</button>
    </div>`;
  detailEl.querySelectorAll("button[data-state]").forEach(btn =>
    btn.addEventListener("click", () => setReview(direction, findingId, btn.dataset.state)));
  detailEl.querySelectorAll(".view-toggle-btn").forEach(btn => btn.addEventListener("click", () => {
    DIFF_VIEW_MODE = btn.dataset.view;
    localStorage.setItem("driftDiffView", DIFF_VIEW_MODE);
    detailEl.querySelectorAll(".view-toggle-btn").forEach(b => b.classList.toggle("active", b === btn));
    loadRichDiff(direction, findingId);
  }));
  document.getElementById(`askAiBtn_${findingId}`).addEventListener("click", () => askAiSingle(direction, findingId));
  if (showPortButton) {
    document.getElementById(`portTo105Btn_${direction}_${findingId}`).addEventListener("click", () => portToOneOhFive(direction, findingId));
  }
  document.getElementById("detail_" + direction).scrollIntoView({ behavior: "smooth", block: "nearest" });

  if (f.statement_map) loadStatementMap(direction, findingId, f.statement_map);
  loadRichDiff(direction, findingId);
  loadCachedAi(direction, findingId);
}

/* ============================== D7: statement-level change map ============================== */

async function loadStatementMap(direction, findingId, summary) {
  const el = document.getElementById(`stmtMap_${direction}_${findingId}`);
  if (!el) return;
  if (!summary.ok) {
    el.innerHTML = `<div class="stmt-map-unavailable">Statement structure unavailable (${escapeHtml(summary.reason)}) — showing text diff only.</div>`;
    return;
  }
  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/statements/${findingId}`);
  if (!ok || !body.ok) {
    el.innerHTML = `<div class="stmt-map-unavailable">Statement structure unavailable (${escapeHtml((body && body.reason) || "?")}) — showing text diff only.</div>`;
    return;
  }
  el.innerHTML = renderStatementMapHtml(body.aligned);
  el.querySelectorAll(".stmt-row").forEach(row => row.addEventListener("click", () => {
    scrollDiffToText(direction, findingId, row.dataset.searchText);
  }));
}

function renderStatementMapHtml(aligned) {
  const rows = aligned.map(a => {
    const stmt = a.client || a.master;  // prefer the current (client) shape; fall back for a pure removal
    const firstLine = (stmt.text || "").split("\n")[0].trim();
    const conditionChanged = a.tag === "changed" && a.master && a.client &&
      (a.master.condition !== null || a.client.condition !== null) &&
      a.master.condition !== a.client.condition;
    const conditionHtml = stmt.condition
      ? `<span class="stmt-condition${conditionChanged ? " condition-changed" : ""}">${escapeHtml(stmt.condition)}</span>`
      : "";
    const tagClass = a.tag === "equal" ? "formatting" : a.tag;
    return `<div class="stmt-row stmt-${a.tag}" data-search-text="${escapeHtml(firstLine)}">
      <span class="stmt-kind">${escapeHtml(stmt.kind)}</span>
      <span class="tag ${tagClass}">${a.tag}${conditionChanged ? " (condition)" : ""}</span>
      ${conditionHtml}
      <span class="stmt-text">${escapeHtml(firstLine)}</span>
    </div>`;
  }).join("");
  return `<div class="hint">each row is one T-SQL statement, aligned by content not position — click a row to jump to it in the diff below</div><div class="stmt-map">${rows}</div>`;
}

function scrollDiffToText(direction, findingId, searchText) {
  if (!searchText) return;
  const container = document.getElementById(`richdiff_${direction}_${findingId}`);
  if (!container) return;
  for (const el of container.querySelectorAll(".rdiff-line .txt, .rdiff-cell")) {
    if (el.textContent.includes(searchText)) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      el.classList.add("stmt-highlight");
      setTimeout(() => el.classList.remove("stmt-highlight"), 1500);
      return;
    }
  }
}

async function loadRichDiff(direction, findingId) {
  const el = document.getElementById(`richdiff_${direction}_${findingId}`);
  const view = DIFF_VIEW_MODE;  // captured now -- a toggle click while this is in flight re-calls loadRichDiff fresh
  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/richdiff/${findingId}?view=${view}`);
  if (!ok) { el.innerHTML = `<div class="hint">${escapeHtml(body.error)}</div>`; return; }
  const diffHint = body.kind === "columns" ? "" :
    `<div class="hint">red = removed, green = added; highlighted words show exactly what changed on a modified line</div>`;
  el.innerHTML = diffHint + (body.kind === "columns" ? renderColumnGrid(body)
    : body.view === "split" ? renderSplitDiffHtml(body) : renderRichDiffHtml(body));
  if (body.kind === "columns") mountBackfillInputs(direction, findingId, body);
  el.querySelectorAll(".rdiff-collapsed").forEach(marker => marker.addEventListener("click", () => {
    const omittedMsg = `<span class="txt hint">(context lines omitted for width — open the raw .diff download if needed)</span>`;
    marker.outerHTML = marker.classList.contains("rdiff-collapsed-split")
      ? `<div class="rdiff-row equal"><div class="rdiff-cell left equal">${omittedMsg}</div><div class="rdiff-cell right equal"></div></div>`
      : `<div class="rdiff-line equal"><span class="gut"></span>${omittedMsg}</div>`;
  }));
}

function renderWords(words) {
  return words.map(w => w.changed ? `<span class="rdiff-word changed">${escapeHtml(w.text)}</span>` : escapeHtml(w.text)).join("");
}

function renderRichDiffHtml(body) {
  let html = `<div class="rdiff">`;
  for (const hunk of body.hunks) {
    if (hunk.collapsed) {
      html += `<div class="rdiff-collapsed">⋯ ${hunk.count} unchanged line(s) ⋯</div>`;
      continue;
    }
    for (const op of hunk.lines) {
      if (op.tag === "equal") html += `<div class="rdiff-line equal"><span class="gut"> </span><span class="txt">${escapeHtml(op.text)}</span></div>`;
      else if (op.tag === "delete") html += `<div class="rdiff-line delete"><span class="gut">−</span><span class="txt">${escapeHtml(op.text)}</span></div>`;
      else if (op.tag === "insert") html += `<div class="rdiff-line insert"><span class="gut">+</span><span class="txt">${escapeHtml(op.text)}</span></div>`;
      else if (op.tag === "replace") {
        html += `<div class="rdiff-line replace-old"><span class="gut">−</span><span class="txt">${renderWords(op.master_words)}</span></div>`;
        html += `<div class="rdiff-line replace-new"><span class="gut">+</span><span class="txt">${renderWords(op.client_words)}</span></div>`;
      }
    }
  }
  return html + `</div>`;
}

/* D4: two-column split view. Same hunk/collapsed shape as the unified
 * renderer above (server reuses _group_into_hunks verbatim) -- each row is
 * {tag, left: {...}|None, right: {...}|None}. .rdiff-row uses
 * `display: contents` (style.css) so its two .rdiff-cell children become
 * direct children of the .rdiff-split grid -- that's what keeps every row's
 * left/right pair aligned into the same two columns without any JS-side
 * width math. */
function renderSplitDiffHtml(body) {
  let html = `<div class="rdiff-split">`;
  for (const hunk of body.hunks) {
    if (hunk.collapsed) {
      html += `<div class="rdiff-collapsed rdiff-collapsed-split">⋯ ${hunk.count} unchanged line(s) ⋯</div>`;
      continue;
    }
    for (const row of hunk.lines) {
      html += `<div class="rdiff-row ${row.tag}">${renderSplitCell(row.left, row.tag, "left")}${renderSplitCell(row.right, row.tag, "right")}</div>`;
    }
  }
  return html + `</div>`;
}

function renderSplitCell(side, tag, pos) {
  if (side === null) return `<div class="rdiff-cell ${pos} empty"></div>`;
  const content = side.words ? renderWords(side.words) : escapeHtml(side.text);
  const cellTag = tag === "replace" ? (pos === "left" ? "replace-old" : "replace-new") : tag;
  return `<div class="rdiff-cell ${pos} ${cellTag}">${content}</div>`;
}

function renderColumnGrid(body) {
  const rows = body.rows.map(r => {
    if (r.status === "retyped") return `<div class="colgrid-row retyped"><span class="colgrid-tag">retyped</span><span>${escapeHtml(r.name)}:</span><span>${escapeHtml(r.master)}</span><span class="colgrid-arrow">→</span><span>${escapeHtml(r.client)}</span></div>`;
    if (r.status === "added") return `<div class="colgrid-row added"><span class="colgrid-tag">added</span><span>${escapeHtml(r.client)}</span></div>`;
    if (r.status === "removed") return `<div class="colgrid-row removed"><span class="colgrid-tag">removed</span><span>${escapeHtml(r.master)}</span></div>`;
    return `<div class="colgrid-row same"><span class="colgrid-tag">same</span><span>${escapeHtml(r.client)}</span></div>`;
  }).join("");
  return `<div class="colgrid">${rows}</div><div class="hint" style="margin-top:6px;">${escapeHtml(body.summary)}</div>`;
}

/* ============================== AI triage ============================== */

function aiLoadingHtml() {
  return `<div class="ai-card"><div class="ai-loading"><span class="spinner"></span> Asking AI…</div></div>`;
}

function renderAiCardHtml(result) {
  if (!result.ok) return `<div class="ai-card"><div class="ai-explain">AI unavailable right now: ${escapeHtml(result.error)}</div></div>`;
  if (result.unstructured) {
    return `<div class="ai-card">
      <div class="ai-card-head"><span class="ai-badge">AI suggestion — verify</span><span class="ai-model">${escapeHtml(result.model)} (unstructured)</span></div>
      <div class="ai-explain mono" style="white-space:pre-wrap;">${escapeHtml(result.raw_text)}</div>
    </div>`;
  }
  const s = result.suggestion;
  const flags = (s.risk_flags || []).filter(f => f && f.toLowerCase() !== "none");
  // D8: the server only checks that the model's JSON has an
  // "equivalence_guess" KEY, not that its VALUE is the {is_likely_equivalent,
  // confidence, reasoning} object the prompt asks for -- a model that emits
  // "equivalence_guess": null (schema-adjacent, not malformed enough to trip
  // ai.py's _REQUIRED_KEYS gate) would otherwise throw here and blank the
  // whole card. Omit the line rather than fabricate a verdict the model
  // never actually gave.
  const eq = (s.equivalence_guess && typeof s.equivalence_guess === "object") ? s.equivalence_guess : null;
  return `<div class="ai-card">
    <div class="ai-card-head"><span class="ai-badge">AI suggestion — verify</span><span class="ai-model">${escapeHtml(result.model)}</span></div>
    <div class="ai-explain">${escapeHtml(s.explanation)}</div>
    ${flags.length ? `<div class="ai-flags">${flags.map(f => `<span class="ai-flag">⚠ ${escapeHtml(f)}</span>`).join("")}</div>` : ""}
    <div class="ai-rec">
      <span class="ai-rec-badge ${s.recommendation}">${REC_LABEL[s.recommendation] || s.recommendation}</span>
      <span>${escapeHtml(s.recommendation_reasoning)}</span>
    </div>
    ${eq ? `<div class="ai-equiv">Equivalence guess: ${eq.is_likely_equivalent ? "likely equivalent" : "likely NOT equivalent"} (${escapeHtml(eq.confidence)} confidence) — ${escapeHtml(eq.reasoning)}</div>` : ""}
  </div>`;
}

async function loadCachedAi(direction, findingId) {
  // ?peek=1 returns the cached card if one exists and NEVER triggers a new
  // AI call otherwise -- reopening a finding shows what was already asked
  // without silently re-asking (or silently hiding) anything.
  const slot = document.getElementById(`aiSlot_${direction}_${findingId}`);
  const { body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/ai/${findingId}?peek=1`, { method: "POST" });
  if (body && body.cached !== false) slot.innerHTML = renderAiCardHtml(body);
}

async function askAiSingle(direction, findingId) {
  const slot = document.getElementById(`aiSlot_${direction}_${findingId}`);
  slot.innerHTML = aiLoadingHtml();
  const { body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/ai/${findingId}`, { method: "POST" });
  slot.innerHTML = renderAiCardHtml(body);
}

async function askAiBatch(direction) {
  const ids = Array.from(SELECTED_FINDINGS);
  if (!ids.length) return;
  const bar = document.getElementById(`batchBar_${direction}`);
  bar.innerHTML = `<span class="ai-loading"><span class="spinner"></span> Asking AI about ${ids.length} finding(s)…</span>`;

  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/ai_batch`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ finding_ids: ids }),
  });
  if (!ok) { bar.innerHTML = `<span class="log-err">${escapeHtml(body.error)}</span>`; return; }

  const es = new EventSource(`/api/stream/${body.job_id}`);
  const lines = [];
  es.addEventListener("log", (e) => { lines.push(JSON.parse(e.data)); bar.innerHTML = `<span class="hint">${escapeHtml(lines[lines.length - 1])}</span>`; });
  es.addEventListener("result", (e) => {
    es.close();
    bar.innerHTML = `<span>Done — ${ids.length} finding(s) triaged. Open a finding to see its AI card.</span> <button class="ghost sm" id="batchClearBtn2_${direction}">Clear selection</button>`;
    document.getElementById(`batchClearBtn2_${direction}`).addEventListener("click", () => {
      SELECTED_FINDINGS = new Set(); renderFindingsTable(direction);
    });
  });
  es.addEventListener("error", (e) => {
    es.close();
    bar.innerHTML = `<span class="log-err">Batch failed: ${e.data ? escapeHtml(JSON.parse(e.data)) : "unknown error"}</span>`;
  });
}

async function testAiConnection(direction) {
  const out = document.getElementById(`testAiOut_${direction}`);
  out.textContent = "Testing…";
  const { body } = await getJSON("/api/ai/test");
  out.textContent = body.ok ? `✓ ${body.model} answered: ${body.sample}` : `✗ ${body.error}`;
  out.style.color = body.ok ? "var(--green)" : "var(--red)";
}

/* ============================== Port to 105 (AI-assisted merge) ============================== */

// Ask once per run, reuse silently -- native prompt() is proportional here
// (one string field, once per run, not a recurring screen; see PLAN's
// design-review decision). Resolves to null if the user cancels.
async function ensureClientActiveId(runId) {
  if (CURRENT_META.client_active_id) return CURRENT_META.client_active_id;
  const id = prompt("Enter this client's ClientActive ID (asked once per run, then reused automatically):");
  if (!id || !id.trim()) return null;
  const { ok, body } = await getJSON(`/api/run/${runId}/client_active_id`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_active_id: id.trim() }),
  });
  if (!ok) { alert("Could not save ClientActive ID: " + body.error); return null; }
  CURRENT_META.client_active_id = body.client_active_id;
  return body.client_active_id;
}

async function portToOneOhFive(direction, findingId) {
  const clientActiveId = await ensureClientActiveId(CURRENT_RUN_ID);
  if (!clientActiveId) return;

  const slot = document.getElementById(`mergeSlot_${direction}_${findingId}`);
  slot.innerHTML = `<div class="ai-card"><div class="ai-loading"><span class="spinner"></span> Asking DeepSeek to propose a merge (this can take up to a minute)…</div></div>`;

  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/merge_propose/${findingId}`, { method: "POST" });
  if (!ok) { slot.innerHTML = `<div class="ai-card"><div class="ai-explain">Merge proposal unavailable: ${escapeHtml(body.error)}</div></div>`; return; }
  if (body.unstructured) {
    slot.innerHTML = `<div class="ai-card"><div class="ai-explain">AI response didn't parse as the expected merge shape — raw output below, not usable directly.</div>
      <pre class="mono" style="white-space:pre-wrap;">${escapeHtml(body.raw_text)}</pre></div>`;
    return;
  }
  renderMergeProposal(direction, findingId, body);
}

function renderMergeProposal(direction, findingId, result) {
  const slot = document.getElementById(`mergeSlot_${direction}_${findingId}`);
  const sanity = result.sanity_check || {};
  slot.innerHTML = `
    <div class="ai-card">
      <div class="ai-card-head"><span class="ai-badge">AI-proposed merge — verify before accepting</span></div>
      <div class="hint">this is a PROPOSAL only — nothing is applied yet. Review the diff, edit the text if needed, then Accept or Discard.</div>
      ${result.warning ? `<div class="ai-flags"><span class="ai-flag">⚠ ${escapeHtml(result.warning)}</span></div>` : ""}
      ${!sanity.looks_ok ? `<div class="ai-flags"><span class="ai-flag">⚠ this proposal failed a basic sanity check (BEGIN/END count looks unbalanced, or empty) — review VERY carefully before accepting</span></div>` : ""}
      <div class="ai-rec"><span>Approach: ${escapeHtml(result.approach)}</span></div>
      <div id="mergeDiff_${direction}_${findingId}">Loading diff…</div>
      <div class="hint" style="margin-top:8px;">Editable proposed text (edit here if the AI got something wrong, then Accept):</div>
      <textarea id="mergeEdit_${direction}_${findingId}" class="merge-textarea mono">${escapeHtml(result.proposed_master_def)}</textarea>
      <div class="actions">
        <button id="mergeAcceptBtn_${direction}_${findingId}">Accept merge</button>
        <button class="ghost" id="mergeDiscardBtn_${direction}_${findingId}">Discard</button>
      </div>
    </div>`;
  renderMergeDiff(direction, findingId, result.master_def || "", result.proposed_master_def);
  document.getElementById(`mergeAcceptBtn_${direction}_${findingId}`).addEventListener("click", () => acceptMerge(direction, findingId));
  document.getElementById(`mergeDiscardBtn_${direction}_${findingId}`).addEventListener("click", () => { slot.innerHTML = ""; });
}

async function renderMergeDiff(direction, findingId, masterDef, proposedDef) {
  const el = document.getElementById(`mergeDiff_${direction}_${findingId}`);
  const { ok, body } = await getJSON("/api/diff_preview", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ left: masterDef, right: proposedDef }),
  });
  el.innerHTML = ok ? renderSplitDiffHtml(body) : `<div class="hint">diff preview unavailable</div>`;
}

async function acceptMerge(direction, findingId) {
  const text = document.getElementById(`mergeEdit_${direction}_${findingId}`).value;
  const btn = document.getElementById(`mergeAcceptBtn_${direction}_${findingId}`);
  const originalLabel = btn.textContent;
  btn.disabled = true; btn.textContent = "Saving…";

  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/merge_accept/${findingId}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ merged_def: text }),
  });
  const slot = document.getElementById(`mergeSlot_${direction}_${findingId}`);
  if (!ok) {
    slot.insertAdjacentHTML("beforeend", `<div class="log-err">Could not save: ${escapeHtml(body.error)}</div>`);
    btn.disabled = false; btn.textContent = originalLabel;
    return;
  }
  slot.innerHTML = `<div class="ai-card"><div class="ai-explain">✓ Merge accepted and saved. It will be used automatically when you Approve this finding and Assemble the apply script.</div></div>`;
}

/* ============================== Review / apply / metrics ============================== */

async function setReview(direction, findingId, state) {
  await fetch(`/api/run/${CURRENT_RUN_ID}/${direction}/review`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ finding_id: findingId, state }),
  });
  const idx = CURRENT_WORKSPACES[direction];
  const f = idx.findings.find(x => x.id === findingId);
  if (f) f.review = state;
  renderFindingsTable(direction);
}

async function assembleApply(direction) {
  if (IS_LIVE_SCAN) return;
  const includeDeletions = document.getElementById(`includeDeletions_${direction}`).checked;
  const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/apply`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ include_deletions: includeDeletions }),
  });
  const out = document.getElementById(`applyOut_${direction}`);
  const copyBtn = document.getElementById(`copyApplyBtn_${direction}`);
  const applyClientBtn = document.getElementById(`applyClientBtn_${direction}`);
  if (!ok) {
    out.innerHTML = `<div class="log-err">${escapeHtml(body.error)}</div>`;
    if (copyBtn) copyBtn.style.display = "none";
    if (applyClientBtn) applyClientBtn.style.display = "none";
    return;
  }
  out.innerHTML = `
    <div class="noise">${body.manifest.included.length} statement(s) included, ${body.manifest.manual_review.length} need manual review.
    ${direction === "105_to_client" ? "Script targets the <b>client</b> database only." : "Review direction before applying — never run client scripts against 105 without intent."}</div>
    <pre>${escapeHtml(body.script)}</pre>
    ${body.manifest.manual_review.length ? "<b>Manual review needed:</b><pre>" +
      escapeHtml(JSON.stringify(body.manifest.manual_review, null, 1)) + "</pre>" : ""}
  `;
  if (copyBtn) copyBtn.style.display = "inline-block";
  if (applyClientBtn && direction === "105_to_client" && !IS_LIVE_SCAN) {
    applyClientBtn.style.display = "inline-block";
  }
}

function hideApplyErrorModal() {
  const modal = document.getElementById("applyErrorModal");
  if (modal) modal.hidden = true;
}

function showApplyErrorModal(waiting) {
  const modal = document.getElementById("applyErrorModal");
  if (!modal || !waiting) return;
  APPLY_INTERACTIVE_WAITING = waiting;
  document.getElementById("applyErrorMsgno").textContent = `SQL Server error ${waiting.msgno}`;
  document.getElementById("applyErrorPreview").textContent = waiting.sql_preview || "";
  document.getElementById("applyErrorMessage").textContent = waiting.msg || "";
  modal.hidden = false;
}

function renderApplyInteractiveStatus(direction, payload) {
  const out = document.getElementById(`applyOut_${direction}`);
  if (!out) return;
  const stopped = payload.stopped ? " <b>(stopped)</b>" : "";
  const rows = (payload.report || []).map(r =>
    `${r.index}: [${r.status}] ${r.msgno ? r.msgno + " " : ""}${escapeHtml(r.msg || r.sql_preview || "")}`
  ).join("<br>");
  out.innerHTML += `<div class="noise" style="margin-top:10px;">Interactive apply${stopped}: ${payload.done ? "finished" : "paused"}</div><div class="ub-exec">${rows}</div>`;
}

async function handleApplyInteractivePayload(direction, payload) {
  APPLY_INTERACTIVE_SESSION = payload.session_id;
  renderApplyInteractiveStatus(direction, payload);
  if (payload.waiting) {
    showApplyErrorModal(payload.waiting);
    return;
  }
  hideApplyErrorModal();
  APPLY_INTERACTIVE_SESSION = null;
}

async function startInteractiveApply(direction) {
  if (IS_LIVE_SCAN || !CURRENT_RUN_ID || direction !== "105_to_client") return;
  const client = liveClientConnPayload();
  if (!client.server || !client.database) {
    alert("Enter the client SQL Server (server + database) under “Client SQL connection” or Live servers.");
    return;
  }
  if (!confirm("Apply the assembled script to the live CLIENT database? 105 is never modified. Errors will pause for your decision.")) return;
  const applyBtn = document.getElementById(`applyClientBtn_${direction}`);
  if (applyBtn) { applyBtn.disabled = true; applyBtn.textContent = "Applying…"; }
  try {
    const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/apply_start`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ client }),
    });
    if (!ok) {
      const out = document.getElementById(`applyOut_${direction}`);
      if (out) out.innerHTML += `<div class="log-err">${escapeHtml(body.error)}</div>`;
      return;
    }
    await handleApplyInteractivePayload(direction, body);
  } finally {
    if (applyBtn) { applyBtn.disabled = false; applyBtn.textContent = "Apply to client (interactive)"; }
  }
}

async function applyInteractiveDecide(action) {
  if (!APPLY_INTERACTIVE_SESSION) return;
  const pending = APPLY_INTERACTIVE_WAITING;
  if (!pending) return;
  const msgno = pending.msgno;
  hideApplyErrorModal();
  APPLY_INTERACTIVE_WAITING = null;
  const { ok, body } = await getJSON(`/api/apply_session/${APPLY_INTERACTIVE_SESSION}/decide`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, msgno }),
  });
  if (!ok) {
    alert(body.error || "Apply decision failed");
    return;
  }
  await handleApplyInteractivePayload("105_to_client", body);
}

document.getElementById("applyErrSkip")?.addEventListener("click", () => applyInteractiveDecide("skip"));
document.getElementById("applyErrStop")?.addEventListener("click", () => applyInteractiveDecide("stop"));
document.getElementById("applyErrBindSkip")?.addEventListener("click", () => applyInteractiveDecide("bind_skip"));
document.getElementById("applyErrBindStop")?.addEventListener("click", () => applyInteractiveDecide("bind_stop"));
document.getElementById("applyErrorBackdrop")?.addEventListener("click", hideApplyErrorModal);

async function computeMetrics(direction) {
  const btn = document.getElementById(`metricsBtn_${direction}`);
  const out = document.getElementById(`metricsOut_${direction}`);
  btn.disabled = true; btn.textContent = "Computing…";
  const seed = Math.floor(Math.random() * 100000);
  try {
    const { ok, body: m } = await getJSON(`/api/run/${CURRENT_RUN_ID}/metrics?seed=${seed}`);
    if (!ok) { out.innerHTML = `<div class="log-err">${m.error}</div>`; return; }
    out.innerHTML = renderMetricsHtml(m, direction);
  } finally {
    btn.disabled = false; btn.textContent = "Recompute (new random sample)";
  }
}

function renderMetricsHtml(m, direction) {
  const cov = m.coverage[direction], noise = m.noise_separation[direction], acc = m.accuracy[direction];
  const blastAll = m.blast_radius, blastDir = m.blast_radius[direction];
  const attribAll = m.attribution, attribDir = m.attribution[direction];
  const rt = m.runtime;
  const accColor = acc.accuracy_pct_of_checkable === null ? "var(--text-faint)" : (acc.accuracy_pct_of_checkable >= 95 ? "var(--green)" : acc.accuracy_pct_of_checkable >= 80 ? "var(--amber)" : "var(--red)");

  return `
  <div class="cards" style="margin-top:12px;">
    <div class="card"><div class="n" style="color:${accColor}">${acc.accuracy_pct_of_checkable ?? "n/a"}%</div><div class="l">Sample accuracy (seed ${acc.seed})</div></div>
    <div class="card"><div class="n">${noise.signal_pct}%</div><div class="l">Real signal</div></div>
    <div class="card"><div class="n">${cov.detail_coverage_pct ?? "n/a"}%</div><div class="l">Findings w/ full detail</div></div>
    <div class="card"><div class="n">${blastAll.caller_resolution_pct ?? "n/a"}%</div><div class="l">Callers resolved</div></div>
    <div class="card"><div class="n">${attribDir.attribution_coverage_pct ?? "n/a"}%</div><div class="l">Attribution coverage</div></div>
    <div class="card"><div class="n">${rt.total_seconds ?? "n/a"}s</div><div class="l">Total run time</div></div>
  </div>
  <table>
    <tbody>
      <tr><th>Accuracy sample</th><td>${acc.sample_size} findings independently re-checked against captured evidence &mdash;
        <b>${acc.confirmed} confirmed</b>, <b style="color:${acc.anomaly ? 'var(--red)' : 'var(--green)'}">${acc.anomaly} anomaly</b>,
        ${acc.limitation_uncaptured_type} not independently checkable (non-captured object type, e.g. FK/constraint)</td></tr>
      ${acc.anomaly_details.length ? `<tr><th>Anomalies</th><td>${acc.anomaly_details.map(a => `${a.name}: ${a.issue}`).join('<br>')}</td></tr>` : ''}
      <tr><th>Noise breakdown</th><td>${noise.raw_differences_seen} raw diffs seen &rarr; ${noise.real_signal} real (${noise.signal_pct}%).
        Not drift: ${noise.noise_breakdown.formatting_only} formatting, ${noise.noise_breakdown.documentation} doc-only,
        ${noise.noise_breakdown.cascading} cascading, ${noise.noise_breakdown.excluded_client_named} excluded</td></tr>
      <tr><th>Detail coverage</th><td>${cov.total_structural_findings} structural findings, ${cov.with_full_detail} with byte-exact diff/column detail.
        By type: ${Object.entries(cov.by_type).map(([t,c]) => `${t} ${c.detailed}/${c.total}`).join(', ')}</td></tr>
      <tr><th>Blast radius</th><td>${blastAll.changed_objects} changed objects, callers resolved for ${blastAll.objects_with_any_caller_found}.
        Modified findings: avg ${blastDir.avg_callers} callers, max ${blastDir.max_callers},
        ${blastDir.high_blast_radius_gt5} with &gt;5 callers, ${blastDir.with_zero_known_callers} with none found.
        ${blastAll.dynamic_sql_procs_in_db} proc(s) use dynamic SQL (caveat: caller counts are a floor, not a proof)</td></tr>
      <tr><th>Attribution</th><td>ProcedureChangeLog present: master=${attribAll.trigger_present.master}, client=${attribAll.trigger_present.client}.
        ${attribDir.with_attribution}/${attribDir.modified_findings} modified findings attributed, ${attribDir.lost_fixes_found} possible lost fix(es)</td></tr>
      <tr><th>Runtime</th><td>${rt.total_seconds}s total &mdash; ${Object.entries(rt.by_phase).map(([p,s]) => `${p}: ${s}s`).join(', ')}</td></tr>
    </tbody>
  </table>`;
}

/* ============================== Tool tabs (Trimmer / SQL Compare / Drift) ============================== */

function switchTool(tool) {
  if (!tool) return;
  ACTIVE_TOOL = tool;
  document.querySelectorAll("#toolTabs .tool-tab").forEach(btn => {
    const on = btn.dataset.tool === tool;
    btn.classList.toggle("active", on);
    btn.setAttribute("aria-selected", on ? "true" : "false");
  });
  document.querySelectorAll(".tool-pane").forEach(pane => {
    const on = pane.dataset.tool === tool;
    pane.hidden = !on;
  });
  const shell = document.getElementById("appShell");
  if (shell) shell.classList.toggle("rail-hidden-on-trimmer", tool === "trimmer");
  if (tool === "compare") switchCompareSubtab(ACTIVE_COMPARE_SUBTAB);
  if (tool === "drift") syncDriftFromRun();
}

document.querySelectorAll("#toolTabs .tool-tab").forEach(btn =>
  btn.addEventListener("click", () => switchTool(btn.dataset.tool)));

function switchCompareSubtab(sub) {
  ACTIVE_COMPARE_SUBTAB = sub;
  document.querySelectorAll(".compare-subtab").forEach(btn => {
    const on = btn.dataset.compareSub === sub;
    btn.classList.toggle("active", on);
    btn.setAttribute("aria-selected", on ? "true" : "false");
  });
  document.querySelectorAll(".compare-subpane").forEach(pane => {
    pane.hidden = pane.dataset.compareSub !== sub;
  });
  const shared = document.getElementById("sharedLiveConn");
  if (shared) shared.hidden = !(sub === "livescan" || sub === "datacopy");
  if (sub === "schema") {
    IS_LIVE_SCAN = false;
    syncDriftFromRun();
  }
  updateCompareModeUi();
}

document.querySelectorAll(".compare-subtab").forEach(btn =>
  btn.addEventListener("click", () => switchCompareSubtab(btn.dataset.compareSub)));

function updateCompareModeUi() {
  const driftLive = document.getElementById("driftLiveBanner");
  if (driftLive) driftLive.hidden = !IS_LIVE_SCAN;
  document.querySelectorAll("[id^=applyLiveNote_]").forEach(el => {
    el.style.display = IS_LIVE_SCAN ? "block" : "none";
  });
  document.querySelectorAll("[id^=assembleBtn_]").forEach(btn => { btn.disabled = IS_LIVE_SCAN; });
}

function liveMasterConnPayload() {
  return {
    server: document.getElementById("liveMasterServer")?.value?.trim() || "",
    database: document.getElementById("liveMasterDb")?.value?.trim() || "",
    user: document.getElementById("liveMasterUser")?.value?.trim() || "",
    password: document.getElementById("liveMasterPass")?.value || "",
  };
}

function liveClientConnPayload() {
  const applyServer = document.getElementById("applyTargetServer")?.value?.trim();
  if (applyServer && ACTIVE_COMPARE_SUBTAB === "schema") {
    const portRaw = document.getElementById("applyTargetPort")?.value?.trim();
    return {
      server: applyServer,
      port: portRaw ? Number(portRaw) : undefined,
      database: document.getElementById("applyTargetDb")?.value?.trim() || "",
      user: document.getElementById("applyTargetUser")?.value?.trim() || "",
      password: document.getElementById("applyTargetPass")?.value || "",
    };
  }
  return {
    server: document.getElementById("liveClientServer")?.value?.trim() || "",
    database: document.getElementById("liveClientDb")?.value?.trim() || "",
    user: document.getElementById("liveClientUser")?.value?.trim() || "",
    password: document.getElementById("liveClientPass")?.value || "",
  };
}

function datacopyBody(extra = {}) {
  return {
    dst_role: "client",
    source: liveMasterConnPayload(),
    destination: liveClientConnPayload(),
    ...extra,
  };
}

async function mountBackfillInputs(direction, findingId, colBody) {
  const idx = CURRENT_WORKSPACES[direction];
  const f = idx?.findings?.find(x => x.id === findingId);
  if (!f || f.type !== "SqlTable" || f.role !== "modified") return;
  const added = (colBody.rows || []).filter(r => r.status === "added").map(r => r.name);
  if (!added.length) return;
  const detailEl = document.getElementById(`detail_${direction}`);
  if (!detailEl || detailEl.querySelector(".backfill-panel")) return;
  const panel = document.createElement("div");
  panel.className = "backfill-panel block";
  panel.innerHTML = `<div class="hint">Optional backfill for new columns (saved for assemble):</div>` +
    added.map(c => `<label>${escapeHtml(c)} <input class="backfill-in" data-col="${escapeHtml(c)}" placeholder="optional backfill"></label>`).join("");
  const saveBtn = document.createElement("button");
  saveBtn.type = "button";
  saveBtn.textContent = "Save backfill values";
  saveBtn.addEventListener("click", async () => {
    const backfill = {};
    panel.querySelectorAll(".backfill-in").forEach(inp => {
      if (inp.value.trim()) backfill[inp.dataset.col] = inp.value.trim();
    });
    const { ok, body } = await getJSON(`/api/run/${CURRENT_RUN_ID}/${direction}/backfill`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ finding_id: findingId, backfill }),
    });
    saveBtn.textContent = ok ? "Saved" : (body.error || "failed");
  });
  panel.appendChild(saveBtn);
  detailEl.insertBefore(panel, detailEl.querySelector(".actions"));
}

document.getElementById("pkFkChip")?.addEventListener("click", () => {
  ACTIVE_CONSTRAINTS_ONLY = !ACTIVE_CONSTRAINTS_ONLY;
  ACTIVE_TYPE_FILTER = "";
  document.getElementById("pkFkChip")?.classList.toggle("active", ACTIVE_CONSTRAINTS_ONLY);
  const dir = ACTIVE_DIRECTION || Object.keys(CURRENT_WORKSPACES)[0];
  if (dir) renderFindingsTable(dir);
});

document.getElementById("datacopyLoadTables")?.addEventListener("click", async () => {
  const { ok, body } = await getJSON("/api/datacopy/tables", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(datacopyBody()),
  });
  const el = document.getElementById("datacopyTableList");
  if (!ok) { if (el) el.textContent = body.error; return; }
  DATACOPY_TABLES = body.tables || [];
  if (el) el.innerHTML = DATACOPY_TABLES.map(t =>
    `<label><input type="checkbox" class="dc-table" value="${escapeHtml(t)}" checked> ${escapeHtml(t)}</label>`).join("");
});

function selectedDatacopyTables() {
  return [...document.querySelectorAll(".dc-table:checked")].map(cb => cb.value);
}

document.getElementById("datacopyPreview")?.addEventListener("click", async () => {
  const tables = selectedDatacopyTables();
  const { ok, body } = await getJSON("/api/datacopy/preview", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(datacopyBody({ tables })),
  });
  const out = document.getElementById("datacopyOut");
  if (!ok) { if (out) out.textContent = body.error; return; }
  if (out) out.textContent = JSON.stringify(body.tables, null, 2);
});

document.getElementById("datacopySaveScript")?.addEventListener("click", async () => {
  const tables = selectedDatacopyTables();
  const { ok, body } = await getJSON("/api/datacopy/script", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(datacopyBody({ tables, run_id: CURRENT_RUN_ID, direction: ACTIVE_DIRECTION || "105_to_client" })),
  });
  const out = document.getElementById("datacopyOut");
  if (!ok) { if (out) out.textContent = body.error; return; }
  if (out) out.textContent = body.script;
});

document.getElementById("datacopyApply")?.addEventListener("click", async () => {
  if (!confirm("Apply data copy to the CLIENT database? This never targets 105.")) return;
  const tables = selectedDatacopyTables();
  const { ok, body } = await getJSON("/api/datacopy/apply", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(datacopyBody({ tables })),
  });
  const out = document.getElementById("datacopyOut");
  if (!ok) { if (out) out.textContent = body.error || JSON.stringify(body); return; }
  if (out) out.textContent = JSON.stringify(body, null, 2);
});

document.getElementById("webPreviewBtn")?.addEventListener("click", async () => {
  const payload = { src_root: document.getElementById("webSrcRoot").value, dst_root: document.getElementById("webDstRoot").value };
  const { ok, body } = await getJSON("/api/webdeploy/preview", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload),
  });
  const out = document.getElementById("webOut");
  if (!ok) { if (out) out.textContent = body.error; return; }
  if (out) out.textContent = JSON.stringify(body, null, 2);
});

document.getElementById("webScriptBtn")?.addEventListener("click", async () => {
  const payload = { src_root: document.getElementById("webSrcRoot").value, dst_root: document.getElementById("webDstRoot").value };
  const { ok, body } = await getJSON("/api/webdeploy/script", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload),
  });
  const out = document.getElementById("webOut");
  if (!ok) { if (out) out.textContent = body.error; return; }
  if (out) out.textContent = body.script;
});

document.getElementById("webApplyBtn")?.addEventListener("click", async () => {
  const payload = { src_root: document.getElementById("webSrcRoot").value, dst_root: document.getElementById("webDstRoot").value };
  const { ok, body } = await getJSON("/api/webdeploy/apply", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload),
  });
  const out = document.getElementById("webOut");
  if (!ok) { if (out) out.textContent = body.error; return; }
  if (out) out.textContent = JSON.stringify(body, null, 2);
});

document.getElementById("pkgSaveProfile")?.addEventListener("click", async () => {
  const name = document.getElementById("pkgProfileName")?.value?.trim();
  if (!name) return;
  const masterSel = document.getElementById("recent_master");
  const clientSel = document.getElementById("recent_client");
  const { ok, body } = await getJSON("/api/profiles", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name,
      master_path: masterSel?.value || "",
      client_path: clientSel?.value || "",
      client_active_id: document.getElementById("compareClientActiveId")?.value || null,
      master_live: liveMasterConnPayload(),
      client_live: liveClientConnPayload(),
    }),
  });
  const out = document.getElementById("pkgOut");
  if (out) out.textContent = ok ? `Saved profile ${name}` : (body.error || "failed");
});

document.getElementById("pkgDeleteProfile")?.addEventListener("click", async () => {
  const name = document.getElementById("pkgProfileName")?.value?.trim();
  if (!name) return;
  const r = await fetch(`/api/profiles/${encodeURIComponent(name)}`, { method: "DELETE" });
  const body = await r.json();
  const out = document.getElementById("pkgOut");
  if (out) out.textContent = r.ok ? `Deleted ${name}` : (body.error || "failed");
});

document.getElementById("pkgDownloadZip")?.addEventListener("click", () => {
  const dir = ACTIVE_DIRECTION || "105_to_client";
  if (!CURRENT_RUN_ID) {
    document.getElementById("pkgOut").textContent = "Run a .bak compare first.";
    return;
  }
  window.location.href = `/api/run/${CURRENT_RUN_ID}/${dir}/package.zip`;
});

document.getElementById("trimRunBtn")?.addEventListener("click", async () => {
  const r = await fetch("/api/trim", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      definition: document.getElementById("trimSource").value,
      client_active_id: document.getElementById("trimClientId").value
        ? Number(document.getElementById("trimClientId").value)
        : null,
    }),
  });
  const data = await r.json();
  document.getElementById("trimOut").textContent = data.ok ? data.trimmed_sql : (data.reason || "failed");
  document.getElementById("trimUnknown").hidden = !data.unknown_kept;
  document.getElementById("trimHarvest").textContent =
    (data.harvest || []).map(h => `${h.kind || ""} ${h.condition || ""}\n${h.body || ""}`).join("\n---\n");
});

function driftProcFindings(direction) {
  const idx = CURRENT_WORKSPACES[direction];
  if (!idx) return [];
  return idx.findings.filter(f => f.role === "modified" && PROGRAMMABLE_TYPES_JS.has(f.type));
}

function syncDriftFromRun() {
  const bakBanner = document.getElementById("driftBakBanner");
  const controls = document.getElementById("driftControls");
  const disabled = IS_LIVE_SCAN || !CURRENT_RUN_ID;
  if (bakBanner) bakBanner.hidden = !disabled;
  if (controls) controls.hidden = disabled;
  if (disabled) return;

  const dirSel = document.getElementById("driftDirection");
  const directions = Object.keys(CURRENT_WORKSPACES);
  if (dirSel && directions.length) {
    dirSel.innerHTML = directions.map(d => `<option value="${d}">${DIRECTION_LABEL[d] || d}</option>`).join("");
    dirSel.value = ACTIVE_DIRECTION && directions.includes(ACTIVE_DIRECTION) ? ACTIVE_DIRECTION : directions[0];
  }
  const cid = CURRENT_META.client_active_id || document.getElementById("compareClientActiveId")?.value;
  const cidInput = document.getElementById("driftClientActiveId");
  if (cidInput && cid) cidInput.value = cid;

  refreshDriftFindingList();
}

function refreshDriftFindingList() {
  const dir = document.getElementById("driftDirection")?.value || ACTIVE_DIRECTION;
  const sel = document.getElementById("driftFinding");
  if (!sel) return;
  const rows = driftProcFindings(dir);
  if (!rows.length) {
    sel.innerHTML = `<option value="">No modified procedures in this direction</option>`;
    document.getElementById("driftPreview").textContent = "";
    document.getElementById("driftCopyBtn").disabled = true;
    return;
  }
  sel.innerHTML = rows.map(f => `<option value="${escapeHtml(f.id)}">${escapeHtml(f.name)}</option>`).join("");
  runDriftLens();
}

document.getElementById("driftDirection")?.addEventListener("change", refreshDriftFindingList);
document.getElementById("driftFinding")?.addEventListener("change", runDriftLens);
document.querySelectorAll('input[name="driftLens"]').forEach(r => r.addEventListener("change", runDriftLens));
document.getElementById("driftClientActiveId")?.addEventListener("change", runDriftLens);

async function runDriftLens() {
  if (!CURRENT_RUN_ID || IS_LIVE_SCAN) return;
  const findingId = document.getElementById("driftFinding")?.value;
  const direction = document.getElementById("driftDirection")?.value;
  const lens = document.querySelector('input[name="driftLens"]:checked')?.value || "full";
  const clientActiveId = document.getElementById("driftClientActiveId")?.value || null;
  if (!findingId) return;

  const preview = document.getElementById("driftPreview");
  const copyBtn = document.getElementById("driftCopyBtn");
  const meta = document.getElementById("driftMeta");
  const warn = document.getElementById("driftWarn");
  preview.textContent = "Loading lens preview…";
  copyBtn.disabled = true;

  const { ok, body } = await getJSON("/api/proc_lens", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      run_id: CURRENT_RUN_ID,
      finding_id: findingId,
      direction,
      lens,
      client_active_id: clientActiveId ? Number(clientActiveId) : null,
    }),
  });
  if (!ok) {
    preview.textContent = body.reason || body.error || "proc_lens failed";
    if (meta) meta.textContent = "";
    return;
  }
  const show = body.diff_unified || body.preview_right || body.preview_left || "(no diff text)";
  preview.textContent = show;
  if (meta) meta.textContent = body.identical ? "Identical under this lens." : "Definitions differ under this lens.";
  if (warn) {
    if (body.warning) { warn.textContent = body.warning; warn.hidden = false; }
    else warn.hidden = true;
  }
  const kindEl = document.getElementById("driftCopyKind");
  if (kindEl) {
    kindEl.textContent = `copy_kind: ${body.copy_kind || "none"} — paste onto client (${body.copy_side || "client"} CREATE OR ALTER)`;
  }
  LAST_DRIFT_COPY_SQL = body.copy_sql || "";
  copyBtn.disabled = !LAST_DRIFT_COPY_SQL || body.copy_kind === "none";
}

document.getElementById("driftCopyBtn")?.addEventListener("click", async () => {
  if (!LAST_DRIFT_COPY_SQL) return;
  await navigator.clipboard.writeText(LAST_DRIFT_COPY_SQL);
  const toast = document.getElementById("driftCopyToast");
  if (toast) { toast.hidden = false; setTimeout(() => { toast.hidden = true; }, 2000); }
});

function renderLiveScanResults(body) {
  const el = document.getElementById("liveResults");
  const c = body.compare || {};
  const sum = body.summary || c.summary || {};
  const listBlock = (title, items, fmt = x => x) =>
    `<details><summary>${title} (${items.length})</summary><ul class="live-scan-list">` +
    (items.length ? items.map(x => `<li class="mono">${escapeHtml(fmt(x))}</li>`).join("") : "<li class='hint'>None</li>") +
    "</ul></details>";
  const col = c.columns || {};
  const colLines = [
    ...(col.added || []).map(x => `+ ${x}`),
    ...(col.removed || []).map(x => `- ${x}`),
    ...(col.altered || []).map(x => `~ ${typeof x === "string" ? x : JSON.stringify(x)}`),
  ];
  el.style.display = "block";
  el.innerHTML = `
    <h2>Live scan results <span class="hint">(SCAN_ONLY — routing triage, not apply)</span></h2>
    <div class="cards">
      <div class="card"><div class="n">${sum.missing_in_b ?? c.missing_in_b?.length ?? 0}</div><div class="l">Missing on client</div></div>
      <div class="card"><div class="n">${sum.extra_in_b ?? c.extra_in_b?.length ?? 0}</div><div class="l">Extra on client</div></div>
      <div class="card"><div class="n">${colLines.length}</div><div class="l">Column deltas</div></div>
      <div class="card"><div class="n">${sum.body_changed ?? c.body_changed?.length ?? 0}</div><div class="l">Body changed</div></div>
    </div>
    ${listBlock("Objects missing on client (in 105, not client)", c.missing_in_b || [])}
    ${listBlock("Extra on client (not on 105)", c.extra_in_b || [])}
    ${listBlock("Column shape changes", colLines)}
    ${listBlock("Module body changed", c.body_changed || [])}
  `;
}

document.getElementById("liveScanBtn")?.addEventListener("click", async () => {
  const payload = { master: liveMasterConnPayload(), client: liveClientConnPayload() };
  IS_LIVE_SCAN = true;
  CURRENT_RUN_ID = null;
  const results = document.getElementById("results");
  if (results) results.style.display = "none";
  updateCompareModeUi();
  syncDriftFromRun();
  const btn = document.getElementById("liveScanBtn");
  btn.disabled = true;
  btn.textContent = "Scanning…";
  const { ok, body } = await getJSON("/api/livescan", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  btn.disabled = false;
  btn.textContent = "Run live scan";
  if (!ok) {
    document.getElementById("liveResults").style.display = "block";
    document.getElementById("liveResults").innerHTML = `<div class="log-err">${escapeHtml(body.error)}</div>`;
    return;
  }
  renderLiveScanResults(body);
});

/* ============================== Init ============================== */

switchTool("trimmer");
switchCompareSubtab("schema");
updateCompareModeUi();
loadRunList();
