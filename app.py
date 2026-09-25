"""Master(105)-vs-Client DB drift tool. Flask + SSE log stream + a two-workspace
(Client->105 / 105->Client) compare, drill-down, review, and safe apply-script flow.
See docs/ARCHITECTURE.md."""
import io
import json
import queue
import threading
import time
import uuid
import zipfile
from pathlib import Path

import pymssql

from flask import Flask, Response, jsonify, render_template, request, send_file

from drift import (ai, ai_merge, blocks, classify, compare, config, datacopy, diff_render, diffing,
                   executor, gatewrap, ledger, livescan, metrics, pipeline, profiles, proc_lens,
                   scriptgen, statements, webdeploy)
from drift.apply_session import ApplySession, Decision
from drift.trimmer import handle_trim

app = Flask(__name__)

JOBS: dict[str, dict] = {}
# run_id -> {"run_dir": Path, "meta": dict, "workspaces": {direction: index_dict}, "findings": {direction: [...]}}
# In-memory cache, kept for the life of the process. `findings` (the full
# enriched records with master_def/client_def) is only ever populated for a
# run computed in THIS process lifetime -- see _load_run()/_finding_full()
# for how richdiff/AI/metrics work on a run reloaded from a prior process too.
RUNS: dict[str, dict] = {}
# Interactive live apply (client target only): session_id -> runtime bundle.
APPLY_SESSIONS: dict[str, dict] = {}

AI_BATCH_CAP = 25

REVIEW_CLIENT_EXTRAS_HEADER = (
    "-- REVIEW ONLY. This tool will not execute this script. Do not apply from the UI."
)


def find_backups() -> list[dict]:
    seen, out = set(), []
    for p in sorted(config.REPO_ROOT.rglob("*.bak")):
        if ".git" in p.parts:
            continue
        if p in seen:
            continue
        seen.add(p)
        out.append({
            "path": str(p),
            "label": f"{p.relative_to(config.REPO_ROOT)}  ({p.stat().st_size / 1_048_576:.0f} MB)",
        })
    return out


def _load_run(run_id: str):
    """RUNS.get(run_id), falling back to reconstructing from disk (meta.json +
    each direction's index.json) if the run finished in a prior process
    lifetime. `findings` stays {} on a disk-reloaded run -- only apply-script
    assembly needs that in-memory-only field; richdiff/AI/metrics/review/
    download all work from `workspaces`/`meta`/`run_dir` alone, so they work
    identically either way."""
    run = RUNS.get(run_id)
    if run:
        return run
    run_dir = config.OUTPUT_DIR / run_id
    meta_path = run_dir / "meta.json"
    if not meta_path.is_file():
        return None
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    workspaces = {}
    for d in meta.get("directions", []):
        idx_path = run_dir / d / "index.json"
        if idx_path.is_file():
            try:
                workspaces[d] = json.loads(idx_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
    if not workspaces:
        return None
    run = {"run_dir": run_dir, "meta": meta, "workspaces": workspaces, "findings": {}}
    RUNS[run_id] = run
    return run


def _finding_full(run: dict, direction: str, finding_id: str):
    """Reconstruct one finding's full content (diff lines / columns / callers /
    attribution) straight from its on-disk artifacts, given only its
    index.json summary row. Works for a fresh or a disk-reloaded run alike --
    richdiff and AI triage never depend on the in-memory-only full-findings
    cache that apply-script assembly still uses."""
    idx = run["workspaces"].get(direction)
    if not idx:
        return None
    row = next((f for f in idx["findings"] if f["id"] == finding_id), None)
    if not row:
        return None

    base = run["run_dir"] / direction / row["path"]
    f = dict(row)

    diff_path = base.with_suffix(".diff")
    if diff_path.is_file():
        f["diff"] = diff_path.read_text(encoding="utf-8", errors="replace").splitlines()

    cols_path = Path(str(base) + ".columns.json")
    if cols_path.is_file():
        try:
            cols = json.loads(cols_path.read_text(encoding="utf-8"))
            f["master_columns"] = cols.get("master_columns", [])
            f["client_columns"] = cols.get("client_columns", [])
            f["columns"] = diffing.diff_columns(f["master_columns"], f["client_columns"])
        except (json.JSONDecodeError, OSError):
            pass

    master_sql = Path(str(base) + ".master.sql")
    client_sql = Path(str(base) + ".client.sql")
    if master_sql.is_file():
        f["master_def"] = master_sql.read_text(encoding="utf-8", errors="replace")
    if client_sql.is_file():
        f["client_def"] = client_sql.read_text(encoding="utf-8", errors="replace")

    merged_sql = Path(str(base) + ".merged.sql")
    if merged_sql.is_file():
        f["merged_def"] = merged_sql.read_text(encoding="utf-8", errors="replace")

    return f


@app.get("/")
def index():
    return render_template("index.html", backups=find_backups(), type_categories=compare.TYPE_CATEGORIES)


@app.get("/api/backups")
def api_backups():
    return jsonify(find_backups())


@app.get("/api/browse")
def api_browse():
    """Server-side directory browser under BACKUP_BROWSE_ROOT -- the real
    device file picker. A browser <input type=file> can't give back a real
    filesystem path, and this tool needs one (RESTORE FROM DISK runs inside
    the scratch container against the mounted path), so this replaces that
    idea entirely rather than uploading multi-GB .bak files through Flask."""
    root = config.BACKUP_BROWSE_ROOT.resolve()
    req_path = request.args.get("path", "")
    target = (root / req_path).resolve() if req_path else root
    if target != root and root not in target.parents:
        return jsonify({"error": "path outside the configured browse root"}), 400
    if not target.is_dir():
        return jsonify({"error": "not a directory"}), 400

    try:
        entries = sorted(target.iterdir(), key=lambda p: p.name.lower())
    except OSError as e:
        return jsonify({"error": f"cannot read this directory: {e}"}), 400

    dirs, baks = [], []
    _skip_dirs = {"__pycache__", "node_modules", ".git"}
    for p in entries:
        try:
            if p.name.startswith(".") or p.name in _skip_dirs:
                continue
            if p.is_dir():
                dirs.append(p.name)
            elif p.is_file() and p.suffix.lower() == ".bak":
                st = p.stat()
                baks.append({
                    # abs_path is what the client sends back to /api/compare -- a
                    # browse-selected file is relative to BACKUP_BROWSE_ROOT, which
                    # is a *different* (broader) root than the CWD-relative paths
                    # the "recent in repo" dropdown uses, so only an absolute path
                    # is unambiguous regardless of which picker mode was used.
                    "name": p.name, "path": str(p.relative_to(root)), "abs_path": str(p),
                    "size_mb": round(st.st_size / 1_048_576, 1), "mtime": st.st_mtime,
                })
        except OSError:
            continue  # unreadable entry (permissions, broken symlink) -- skip, don't 500 the listing

    cwd = "" if target == root else str(target.relative_to(root))
    parent = None if target == root else ("" if target.parent == root else str(target.parent.relative_to(root)))
    return jsonify({"root": str(root), "cwd": cwd, "parent": parent, "dirs": dirs, "baks": baks})


@app.get("/api/runs")
def api_runs():
    """Disk-backed run list -- survives server restarts, unlike RUNS. Powers
    the run-list sidebar so a finished run reloads instantly instead of being
    lost the moment the process restarts."""
    if not config.OUTPUT_DIR.is_dir():
        return jsonify([])
    out = []
    for run_dir in sorted(config.OUTPUT_DIR.iterdir(), reverse=True):
        if not run_dir.is_dir():
            continue
        meta_path = run_dir / "meta.json"
        if not meta_path.is_file():
            continue
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        counts = {}
        for d in meta.get("directions", []):
            idx_path = run_dir / d / "index.json"
            if idx_path.is_file():
                try:
                    counts[d] = json.loads(idx_path.read_text(encoding="utf-8"))["counts"]
                except (json.JSONDecodeError, OSError, KeyError):
                    pass
        out.append({
            "run_id": meta.get("run_id", run_dir.name),
            "master": Path(meta.get("master_path", "?")).name,
            "client": Path(meta.get("client_path", "?")).name,
            "directions": meta.get("directions", []),
            "counts": counts,
            "total_seconds": meta.get("timings", {}).get("total"),
        })
    return jsonify(out)


@app.post("/api/trim")
def api_trim():
    data, status = handle_trim(request.get_json(silent=True) or {})
    return jsonify(data), status


# desktop.py runs as __main__, so `import desktop` is a second module with
# CHOOSER_ENABLED still False. Register the picker from the running process.
_bak_picker = None


def register_bak_picker(fn):
    global _bak_picker
    _bak_picker = fn


@app.get("/api/desktop/chooser")
def api_desktop_chooser_status():
    return jsonify({"ok": _bak_picker is not None})


@app.route("/api/desktop/open_bak", methods=["GET", "POST"])
def api_desktop_open_bak():
    if _bak_picker is None:
        return jsonify({"ok": False, "error": "use the desktop app"}), 501
    path = _bak_picker()
    if not path:
        return jsonify({"ok": False, "error": "cancelled or unavailable"}), 400
    return jsonify({"ok": True, "path": path})


@app.post("/api/proc_lens")
def api_proc_lens():
    """Compare two captured procedure defs under a drift lens (in-memory only)."""
    body = request.get_json(silent=True) or {}
    lens = body.get("lens") or "full"
    client_active_id = body.get("client_active_id")

    left_def = body.get("left_def")
    right_def = body.get("right_def")
    run_id = body.get("run_id")
    finding_id = body.get("finding_id")
    direction = body.get("direction")

    if run_id:
        run = _load_run(str(run_id))
        if not run:
            return jsonify({"ok": False, "reason": "unknown run_id"}), 404
        if direction not in run.get("workspaces", {}):
            return jsonify({"ok": False, "reason": "unknown direction"}), 400
        if not finding_id:
            return jsonify({"ok": False, "reason": "finding_id required with run_id"}), 400
        f = _finding_full(run, direction, finding_id)
        if not f:
            return jsonify({"ok": False, "reason": "unknown finding_id"}), 404
        left_def = f.get("master_def") or ""
        right_def = f.get("client_def") or ""
        if client_active_id is None:
            client_active_id = run["meta"].get("client_active_id")
    elif left_def is None or right_def is None:
        return jsonify({"ok": False, "reason": "provide left_def+right_def or run_id+finding_id+direction"}), 400

    if client_active_id is None and lens != "full":
        return jsonify({"ok": False, "reason": "client_active_id required for active_read / active_plus_else"}), 400

    client_settings = body.get("client_settings")
    master_settings = body.get("master_settings")
    if run_id:
        client_settings = client_settings or f.get("client_settings")
        master_settings = master_settings or f.get("master_settings")
        if not direction:
            direction = "client_to_105"

    result = proc_lens.compare_procs(
        left_def or "",
        right_def or "",
        client_active_id,
        lens,
        client_settings=client_settings,
        master_settings=master_settings,
        direction=direction or "client_to_105",
    )
    return jsonify(result), (200 if result.get("ok") else 400)


def _conn_params(side: dict, label: str) -> tuple[str, str, str, str] | None:
    server = (side.get("server") or "").strip()
    database = (side.get("database") or "").strip()
    user = (side.get("user") or "").strip()
    password = side.get("password") or ""
    if not server or not database:
        return None
    return server, database, user, password


def _sql_connect(side: dict):
    """Client/live connect. Optional port is for scratch MSSQL (HOST_PORT);
    omitted so production hosts keep default 1433 (livescan contract)."""
    params = _conn_params(side, "client")
    if not params:
        return None
    server, database, user, password = params
    port = side.get("port")
    if port in (None, "", 0, "0"):
        return livescan.connect(server, database, user or None, password or None)
    return pymssql.connect(
        server=server,
        port=int(port),
        database=database,
        user=user or None,
        password=password or None,
        timeout=60,
        login_timeout=10,
    )


def _sql_connect_for_list(side: dict):
    """List databases on a server; connects to ``master`` when database omitted."""
    if not (side.get("server") or "").strip():
        return None
    connect_side = dict(side)
    if not (connect_side.get("database") or "").strip():
        connect_side["database"] = "master"
    return _sql_connect(connect_side)


def _redact_side(side: dict | None) -> dict | None:
    if not side:
        return side
    return {k: v for k, v in side.items() if k != "password"}


def _conn_key(side: dict) -> tuple:
    server = (side.get("server") or "").strip().lower()
    if server in {"localhost", "127.0.0.1", "::1", "0.0.0.0"}:
        server = "localhost"
    port = int(side.get("port") or 1433)
    database = (side.get("database") or "").strip().lower()
    return server, port, database


def _redact_run_meta(meta: dict) -> dict:
    if meta.get("master_side"):
        meta["master_side"] = _redact_side(meta["master_side"])
    if meta.get("client_side"):
        meta["client_side"] = _redact_side(meta["client_side"])
    return meta


def _persist_redacted_meta(run_dir: Path, meta: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")


def _start_compare_job(compare_callable):
    job_id = uuid.uuid4().hex[:12]
    q: queue.Queue = queue.Queue()
    JOBS[job_id] = {"queue": q, "result": None, "error": None, "done": False, "kind": "compare"}

    def log(msg: str):
        print(f"[{job_id}] {msg}", flush=True)
        q.put(msg)

    def worker():
        try:
            result = compare_callable(log)
            meta = _redact_run_meta(result["meta"])
            result["meta"] = meta
            _persist_redacted_meta(Path(result["run_dir"]), meta)
            JOBS[job_id]["result"] = result
            RUNS[result["run_id"]] = {
                "run_dir": Path(result["run_dir"]),
                "meta": meta,
                "workspaces": result["workspaces"],
                "findings": result["_findings"],
            }
        except Exception as e:  # noqa: BLE001 - surface every failure to the GUI, don't swallow
            JOBS[job_id]["error"] = str(e)
            log(f"FAILED: {e}")
        finally:
            JOBS[job_id]["done"] = True
            q.put(None)

    threading.Thread(target=worker, daemon=True).start()
    return job_id


_BACKFILL_RERUN_MSG = (
    "this run was reloaded from a prior session and no longer has the full "
    "in-memory record apply-script assembly needs -- re-run the comparison "
    "to enable Apply for this run."
)


def _datacopy_dst_guard(body) -> tuple[dict | None, tuple]:
    """Refuse any datacopy call that does not explicitly target the client role."""
    if body.get("dst_role") != "client":
        return None, (jsonify({"error": "datacopy requires dst_role: \"client\" (never master/105)"}), 403)
    return body, ()


def _webdeploy_roots(body) -> tuple[Path, Path] | tuple[None, tuple]:
    src_raw, dst_raw = body.get("src_root"), body.get("dst_root")
    if not src_raw or not dst_raw:
        return None, (jsonify({"error": "src_root and dst_root required"}), 400)
    root = config.BACKUP_BROWSE_ROOT.resolve()
    src = Path(src_raw).resolve()
    dst = Path(dst_raw).resolve()
    for label, p in (("src_root", src), ("dst_root", dst)):
        if p != root and root not in p.parents:
            return None, (jsonify({"error": f"{label} outside the configured browse root"}), 400)
    return (src, dst), ()


def _datacopy_table_plan(src_conn, dst_conn, table: str, include_delete: bool) -> dict:
    src_cur = src_conn.cursor(as_dict=True)
    dst_cur = dst_conn.cursor(as_dict=True)
    keys = datacopy.get_key_columns(src_cur, table)
    src_rows = datacopy.fetch_rows_hashed(src_cur, table, keys)
    dst_rows = datacopy.fetch_rows_hashed(dst_cur, table, keys)
    plan = datacopy.diff_tables(src_rows, dst_rows)
    if not include_delete:
        plan = {**plan, "delete": []}
    if src_rows:
        cols = next(iter(src_rows.values()))["cols"]
    elif dst_rows:
        cols = next(iter(dst_rows.values()))["cols"]
    else:
        cols = []
    return {"table": table, "key_cols": keys, "cols": cols, "plan": plan,
            "counts": {k: len(plan[k]) for k in ("insert", "update", "delete")}}


@app.post("/api/livescan")
def api_livescan():
    """Live catalog quick-scan (SCAN_ONLY — no script generation)."""
    body = request.get_json(force=True)
    master = _conn_params(body.get("master") or {}, "master")
    client = _conn_params(body.get("client") or {}, "client")
    if not master or not client:
        return jsonify({"error": "master and client each need server + database"}), 400

    def _scan(server, database, user, password):
        conn = livescan.connect(server, database, user or None, password or None)
        try:
            cur = conn.cursor(as_dict=True)
            return livescan.scan(cur)
        finally:
            conn.close()

    try:
        snap_master = _scan(*master)
        snap_client = _scan(*client)
    except Exception as e:  # noqa: BLE001 - surface connection/scan failures to UI
        return jsonify({"error": str(e), "scan_only": livescan.SCAN_ONLY}), 400

    diff = livescan.quick_compare(snap_master, snap_client)
    oversized = sorted(set(
        (snap_master.get("oversized_modules") or [])
        + (snap_client.get("oversized_modules") or [])
    ))
    return jsonify({
        "scan_only": livescan.SCAN_ONLY,
        "compare": diff,
        "summary": diff.get("summary") or {},
        "oversized_modules": oversized,
        "module_text_warn": bool(oversized),
    })


@app.post("/api/live/databases")
def api_live_databases():
    side = request.get_json(silent=True) or {}
    if not (side.get("server") or "").strip():
        return jsonify({"error": "server required"}), 400
    try:
        conn = _sql_connect_for_list(side)
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": str(e)}), 400
    if conn is None:
        return jsonify({"error": "could not connect (check server, user, password)"}), 400
    try:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name")
        names = [row[0] for row in cur.fetchall()]
    finally:
        conn.close()
    return jsonify({"ok": True, "databases": names})


@app.post("/api/compare")
def api_compare():
    body = request.get_json(force=True)
    master_side = body.get("master_side")
    client_side = body.get("client_side")
    use_sides = master_side is not None and client_side is not None

    master_path, client_path = body.get("master"), body.get("client")
    # PLAN-V5 Lane D / blueprint C5: optional named-profile defaults. A profile
    # is a saved bookmark of (master, client, client_active_id); when given and
    # found it fills ONLY the fields this request didn't explicitly provide --
    # an explicit body value always wins, so "same profile, different client
    # just this once" stays a one-field override. Unknown name -> 400 (a typo'd
    # profile silently running a full default compare would look identical to a
    # correct run while comparing the wrong pair of databases).
    prof_name = body.get("profile")
    if prof_name:
        prof = profiles.get_profile(str(prof_name))
        if prof is None:
            return jsonify({"error": f"unknown profile: {prof_name}"}), 400
        master_path = master_path or prof.get("master_path") or ""
        client_path = client_path or prof.get("client_path") or ""
    directions = body.get("directions") or ["client_to_105"]

    if use_sides:
        for label, side in (("master_side", master_side), ("client_side", client_side)):
            kind = side.get("kind", "bak")
            if kind == "bak":
                path = side.get("path")
                if not path or not Path(path).is_file():
                    return jsonify({"error": f"{label}: not a file: {path}"}), 400
            elif kind == "live":
                if not (side.get("server") or "").strip() or not (side.get("database") or "").strip():
                    return jsonify({"error": f"{label}: live side needs server and database"}), 400
            else:
                return jsonify({"error": f"{label}: kind must be live or bak"}), 400
    else:
        if not master_path or not client_path:
            return jsonify({"error": "pick both Master (105) and Client"}), 400
        for p in (master_path, client_path):
            if not Path(p).is_file():
                return jsonify({"error": f"not a file: {p}"}), 400

    # D5a: null/absent = no filter (a clean full run). A non-empty list is
    # validated against the real category names -- a typo'd/forged category
    # must fail loudly, never silently match nothing (which would look
    # identical to "type filter selected everything, filtered out zero").
    type_filter = body.get("type_filter")
    if type_filter:
        bad = set(type_filter) - set(compare.TYPE_CATEGORIES)
        if bad:
            return jsonify({"error": f"unknown object type categor{'y' if len(bad) == 1 else 'ies'}: {sorted(bad)}"}), 400
        type_filter = set(type_filter)

    # PLAN-V4 B.2a: optional ClientActive scoping. Digits only -- it becomes a
    # gate-condition operand, and a non-numeric id would silently turn every
    # gate "unknown" (kept, but useless). Absent/null = unscoped run.
    client_active_id = body.get("client_active_id")
    # Profile fallback for ClientActive too -- deliberately placed BEFORE the
    # digit validation below so a profile-sourced id walks the exact same
    # validation path as a hand-typed one (no second, weaker check to forget).
    if client_active_id is None and prof_name:
        client_active_id = prof.get("client_active_id")
    if client_active_id is not None:
        client_active_id = str(client_active_id).strip()
        if not client_active_id.isdigit():
            return jsonify({"error": "client_active_id must be a number"}), 400

    if use_sides:
        def compare_callable(log):
            return pipeline.run_compare_sides(
                master_side, client_side, directions, log,
                type_filter=type_filter, client_active_id=client_active_id,
            )
    else:
        def compare_callable(log):
            return pipeline.run_compare(
                master_path, client_path, directions, log,
                type_filter=type_filter, client_active_id=client_active_id,
            )

    job_id = _start_compare_job(compare_callable)
    return jsonify({"job_id": job_id})


@app.get("/api/profiles")
def api_list_profiles():
    """PLAN-V5 Lane D / C5: saved compare profiles. Pure disk read; {} when
    none saved yet (or the file is corrupt -- profiles.py degrades, never 500s)."""
    return jsonify(profiles.list_profiles())


@app.post("/api/profiles")
def api_save_profile():
    """Save/update one named profile {name, master_path?, client_path?,
    client_active_id?}. Name is the only required field -- a bookmark may
    legitimately hold just the paths, with ClientActive asked per-run as today."""
    body = request.get_json(force=True)
    name = str(body.get("name") or "").strip()
    if not name:
        return jsonify({"error": "profile name must be non-empty"}), 400
    saved = profiles.save_profile(
        name,
        master_path=body.get("master_path") or "",
        client_path=body.get("client_path") or "",
        client_active_id=body.get("client_active_id"),
        master_live=body.get("master_live"),
        client_live=body.get("client_live"),
    )
    return jsonify(saved)


@app.delete("/api/profiles/<name>")
def api_delete_profile(name):
    if not profiles.delete_profile(name):
        return jsonify({"error": f"no profile named {name!r}"}), 404
    return jsonify({"ok": True})


@app.post("/api/run/<run_id>/recompare")
def api_recompare(run_id):
    """D5d: re-enter the pipeline at the compare phase for an existing run,
    reusing its cached .dacpac pair -- no restore/script/extract. Same
    threaded+SSE job shape as /api/compare so the GUI's existing log-stream
    handling works unchanged; the result payload is reshaped to the same
    {run_id, meta, workspaces} shape /api/compare's stream sends, just for
    one direction, so the frontend's result handler needs no branching."""
    body = request.get_json(force=True, silent=True) or {}
    direction = body.get("direction")
    if direction not in pipeline.DIRECTIONS:
        return jsonify({"error": f"direction must be one of {pipeline.DIRECTIONS}"}), 400

    job_id = uuid.uuid4().hex[:12]
    q: queue.Queue = queue.Queue()
    JOBS[job_id] = {"queue": q, "result": None, "error": None, "done": False, "kind": "compare"}

    def log(msg: str):
        print(f"[{job_id}] {msg}", flush=True)
        q.put(msg)

    def worker():
        try:
            r = pipeline.recompare(run_id, direction, log)
            run = _load_run(run_id)
            if not run:
                raise RuntimeError(f"run {run_id!r} not found on disk after recompare -- unexpected")
            run["meta"] = r["meta"]
            run["workspaces"][direction] = r["index"]
            run["findings"][direction] = r["findings"]
            JOBS[job_id]["result"] = {
                "run_id": run_id, "meta": r["meta"],
                "workspaces": run["workspaces"],  # full set (old + this recompare), not just this direction
            }
        except Exception as e:  # noqa: BLE001 - surface every failure to the GUI, don't swallow
            JOBS[job_id]["error"] = str(e)
            log(f"FAILED: {e}")
        finally:
            JOBS[job_id]["done"] = True
            q.put(None)

    threading.Thread(target=worker, daemon=True).start()
    return jsonify({"job_id": job_id})


@app.get("/api/stream/<job_id>")
def api_stream(job_id):
    job = JOBS.get(job_id)
    if not job:
        return jsonify({"error": "unknown job"}), 404

    def gen():
        q = job["queue"]
        while True:
            line = q.get()
            if line is None:
                break
            yield f"event: log\ndata: {json.dumps(line)}\n\n"
        if job["error"]:
            yield f"event: error\ndata: {json.dumps(job['error'])}\n\n"
        elif job.get("kind") == "ai_batch":
            yield f"event: result\ndata: {json.dumps(job['result'])}\n\n"
        else:
            # don't ship _findings (full definitions, can be MBs) over the wire --
            # the browser only needs run_id + per-workspace index/counts to render.
            payload = {"run_id": job["result"]["run_id"], "meta": job["result"]["meta"],
                       "workspaces": job["result"]["workspaces"]}
            yield f"event: result\ndata: {json.dumps(payload)}\n\n"

    return Response(gen(), mimetype="text/event-stream")


@app.get("/api/run/<run_id>")
def api_run(run_id):
    """Reload a finished run without re-running it -- works even after a
    server restart (see _load_run)."""
    run = _load_run(run_id)
    if not run:
        return jsonify({"error": "unknown run"}), 404
    return jsonify({"run_id": run_id, "meta": run["meta"], "workspaces": run["workspaces"]})


@app.get("/api/run/<run_id>/file")
def api_run_file(run_id):
    """Serve a raw artifact (a .diff/.md/.sql under this run's own folder). Path-
    confined to the run's directory -- no arbitrary filesystem access."""
    run = _load_run(run_id)
    if not run:
        return jsonify({"error": "unknown run"}), 404
    rel = request.args.get("path", "")
    target = (run["run_dir"] / rel).resolve()
    if run["run_dir"].resolve() not in target.parents and target != run["run_dir"].resolve():
        return jsonify({"error": "path outside run directory"}), 400
    if not target.is_file():
        if request.args.get("optional") == "1":
            return Response(status=204)
        return jsonify({"error": "not found"}), 404
    return Response(target.read_text(encoding="utf-8", errors="replace"), mimetype="text/plain")


@app.get("/api/run/<run_id>/<direction>/richdiff/<finding_id>")
def api_richdiff(run_id, direction, finding_id):
    """GitHub-style rich diff for a finding: word-level highlighted text diff
    for programmable objects, or a structured column grid for tables. Pure
    presentation over already-classified evidence -- never recomputes
    change_kind, never touches the detection path."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    f = _finding_full(run, direction, finding_id)
    if not f:
        return jsonify({"error": "unknown finding_id"}), 404

    if f["type"] == "SqlTable":
        if "master_columns" not in f:
            return jsonify({"error": "no column detail captured for this finding"}), 404
        grid = diff_render.render_column_grid(f.get("master_columns", []), f.get("client_columns", []))
        return jsonify({"kind": "columns", **grid})

    if "master_def" in f or "client_def" in f:
        # D4: split is the default for text findings -- ?view=unified opts back
        # into the single-column GitHub-style stream. Same evidence, same
        # SequenceMatcher walk either way (diff_render.py never recomputes
        # change_kind); this only picks which presentation shape to return.
        view = request.args.get("view", "split")
        renderer = diff_render.render_split_diff if view == "split" else diff_render.render_rich_diff
        rich = renderer(f.get("master_def") or "", f.get("client_def") or "")
        return jsonify({"kind": "text", "view": view, **rich})

    return jsonify({"error": "no body/column detail captured for this object type "
                              "(permissions, role membership, and other security objects "
                              "get correct role/name but no body-level capture)"}), 404


@app.get("/api/run/<run_id>/<direction>/statements/<finding_id>")
def api_statements(run_id, direction, finding_id):
    """D7: the aligned statement map for a finding, read from its
    .statements.json (written by report_writer.py, never embedded in
    index.json -- see that module's own comment). A finding whose
    statement_map.ok is False was never given a .statements.json file at
    all -- the client must render this as "structure unavailable
    (<reason>)", never as "no statement changes"."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    idx = run["workspaces"][direction]
    row = next((f for f in idx["findings"] if f["id"] == finding_id), None)
    if not row:
        return jsonify({"error": "unknown finding_id"}), 404

    sm = row.get("statement_map")
    if not sm or not sm.get("ok"):
        return jsonify({"ok": False, "reason": (sm or {}).get("reason", "no statement map for this finding")})

    path = Path(str(run["run_dir"] / direction / row["path"]) + ".statements.json")
    if not path.is_file():
        return jsonify({"ok": False, "reason": "statement map file missing on disk"})
    aligned = json.loads(path.read_text(encoding="utf-8"))
    return jsonify({"ok": True, "counts": sm["counts"], "total": sm["total"], "aligned": aligned})


@app.post("/api/run/<run_id>/<direction>/review")
def api_review(run_id, direction):
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    body = request.get_json(force=True)
    finding_id, state = body.get("finding_id"), body.get("state")
    if state not in ("pending", "approved", "skipped", "needs_review"):
        return jsonify({"error": f"bad state {state}"}), 400

    index = run["workspaces"][direction]
    for f in index["findings"]:
        if f["id"] == finding_id:
            f["review"] = state
            break
    else:
        return jsonify({"error": "unknown finding_id"}), 404

    (run["run_dir"] / direction / "index.json").write_text(json.dumps(index, indent=1), encoding="utf-8")
    return jsonify({"ok": True})


@app.post("/api/run/<run_id>/<direction>/backfill")
def api_backfill(run_id, direction):
    run = _load_run(run_id)
    if not run or direction not in run.get("workspaces", {}):
        return jsonify({"error": "unknown run or direction"}), 404
    if direction not in run.get("findings", {}):
        return jsonify({"error": _BACKFILL_RERUN_MSG}), 400
    body = request.get_json(force=True)
    finding_id = body.get("finding_id")
    backfill = body.get("backfill")
    if not finding_id or not isinstance(backfill, dict):
        return jsonify({"error": "finding_id and backfill object required"}), 400
    idx = run["workspaces"][direction]
    row = next((f for f in idx["findings"] if f["id"] == finding_id), None)
    if row is None:
        return jsonify({"error": "unknown finding_id"}), 404
    full_list = run["findings"][direction]
    pos = idx["findings"].index(row)
    if pos >= len(full_list):
        return jsonify({"error": "unknown finding_id"}), 404
    target = full_list[pos]
    target["backfill"] = {str(k): str(v) for k, v in backfill.items()}
    apply_dir = run["run_dir"] / direction / "apply"
    apply_dir.mkdir(exist_ok=True)
    sidecar = apply_dir / "backfill.json"
    existing = {}
    if sidecar.is_file():
        try:
            existing = json.loads(sidecar.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            existing = {}
    existing[finding_id] = target["backfill"]
    sidecar.write_text(json.dumps(existing, indent=1), encoding="utf-8")
    return jsonify({"ok": True, "backfill": target["backfill"]})


@app.post("/api/run/<run_id>/<direction>/apply")
def api_apply(run_id, direction):
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    if direction not in run.get("findings", {}):
        return jsonify({"error": _BACKFILL_RERUN_MSG}), 400
    include_deletions = (request.get_json(force=True, silent=True) or {}).get("include_deletions", False)

    index = run["workspaces"][direction]
    # index["findings"] and run["findings"][direction] are the same list, same
    # order (report_writer enumerates exactly what pipeline.py handed it) --
    # so position maps id -> the full (with master_def/client_def/columns) record.
    id_to_full = {idx_f["id"]: run["findings"][direction][i]
                  for i, idx_f in enumerate(index["findings"])}
    approved_rows = [f for f in index["findings"] if f["review"] == "approved"]
    approved_full = [id_to_full[f["id"]] for f in approved_rows]

    # AI-merge feature: approved_full comes from the in-memory pipeline cache
    # (run["findings"]) and does NOT carry "path" (that's an index.json-only
    # field report_writer.py assigns) -- so .merged.sql lookup must use each
    # row's own path, not full["path"] (measured live: raises KeyError).
    # approved_rows/approved_full are the same objects id_to_full holds, so
    # mutating `full` here is visible to scriptgen.assemble() below.
    for row, full in zip(approved_rows, approved_full):
        merged_path = Path(str(run["run_dir"] / direction / row["path"]) + ".merged.sql")
        if merged_path.is_file():
            full["merged_def"] = merged_path.read_text(encoding="utf-8", errors="replace")

    target_label = "105 (master)" if direction == "client_to_105" else "client"
    # D2: direction decides which captured side (client_def/master_def) is
    # the wanted version -- was previously inferred nowhere (always
    # client_def), which made this endpoint's 105_to_client output either a
    # no-op or empty. `direction` is already this route's own URL param.
    result = scriptgen.assemble(approved_full, target_label, direction, include_deletions=include_deletions)

    apply_dir = run["run_dir"] / direction / "apply"
    apply_dir.mkdir(exist_ok=True)
    script_name = "add_update_on_105.sql" if direction == "client_to_105" else "add_update_on_client.sql"
    (apply_dir / script_name).write_text(result["script"], encoding="utf-8")
    if direction == "client_to_105":
        extras = REVIEW_CLIENT_EXTRAS_HEADER + "\n" + result["script"]
        (apply_dir / "review_client_extras.sql").write_text(extras, encoding="utf-8")
    (apply_dir / "manifest.json").write_text(json.dumps(result["manifest"], indent=1), encoding="utf-8")

    return jsonify({"script": result["script"], "manifest": result["manifest"], "script_name": script_name})


@app.post("/api/run/<run_id>/<direction>/classify_all")
def api_classify_all(run_id, direction):
    """PLAN-V4 B.1: bulk deterministic classification of every finding in one
    workspace. Persists each verdict into index.json (visible in UI/reload)
    and returns bucket counts + per-finding actions. Advisory to the human:
    nothing here changes review state -- it proposes, you decide."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    index = run["workspaces"][direction]
    full_by_id = {i: f for i, f in enumerate(run.get("findings", {}).get(direction, []))}
    buckets, actions = {}, {}
    for i, row in enumerate(index["findings"]):
        full = full_by_id.get(i) or {}
        merged = {**row, **{k: full[k] for k in ("scope", "statement_alignment", "change_kind") if k in full}}
        c = classify.classify_finding(merged)
        row["classification"] = c
        buckets.setdefault(c["bucket"], []).append(row["bare_name"])
        actions[row["bare_name"]] = {"action": c["action"], "rule": c["rule"], "confidence": c["confidence"]}
        if i in full_by_id:
            full_by_id[i]["classification"] = c
    index["classification_counts"] = {k: len(v) for k, v in buckets.items()}
    (run["run_dir"] / direction / "index.json").write_text(json.dumps(index, indent=1), encoding="utf-8")
    return jsonify({"ok": True, "counts": index["classification_counts"], "buckets": buckets, "actions": actions})


@app.post("/api/run/<run_id>/<direction>/gate_wrap")
def api_gate_wrap(run_id, direction):
    """PLAN-V4 B.2: deterministic ClientActive wrapping for gated_customization
    findings. splice_up folds the client's changed statements into 105's body
    behind this client's gate; accepted output lands as .merged.sql -- the
    SAME artifact the AI-merge flow produces, so Apply consumes it unchanged.
    Deterministic scissors first; DeepSeek stays the fallback, not the default."""
    run = _load_run(run_id)
    if not run or direction not in run.get("findings", {}):
        return jsonify({"error": "unknown run or direction"}), 404
    if direction != "client_to_105":
        return jsonify({"error": "splice-up is a client_to_105 action"}), 400
    cid = run["meta"].get("client_active_id")
    if not cid:
        return jsonify({"error": "no client_active_id set for this run yet"}), 400
    results = {}
    for f in run["findings"][direction]:
        cls = (f.get("classification") or {}).get("bucket")
        if cls != "gated_customization" or direction != "client_to_105":
            continue
        if not (f.get("master_def") and f.get("client_def") and f.get("statement_alignment")):
            continue
        merged = gatewrap.splice_up(f["master_def"], f["statement_alignment"], cid)
        results[f["bare_name"]] = {"ok": bool(merged), "mode": "deterministic_splice"}
        if merged:
            f["merged_def"] = merged
            # persist next to the finding so reloads keep it (Apply reads these)
            idx = run["workspaces"][direction]
            for row in idx["findings"]:
                if row["id"] == f.get("id") or row["bare_name"] == f["bare_name"]:
                    mp = Path(str(run["run_dir"] / direction / row["path"]) + ".merged.sql")
                    mp.parent.mkdir(parents=True, exist_ok=True)
                    mp.write_text(merged, encoding="utf-8")
                    break
    return jsonify({"ok": True, "results": results})


@app.post("/api/run/<run_id>/<direction>/update_package")
def api_update_package(run_id, direction):
    """PLAN-V4 B.7: one call = classify -> assemble approved (+gates already
    accepted) -> write script/manifest -> LEDGER entry. The human approval
    step from /apply is preserved: only approved rows enter the package."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    if direction not in run.get("findings", {}):
        return jsonify({"error": "this run was reloaded from a prior session and no longer has the "
                                  "full in-memory record package assembly needs -- re-run the "
                                  "comparison to build an update package."}), 400
    index = run["workspaces"][direction]
    approved_rows = [f for f in index["findings"] if f.get("review") == "approved"]
    id_to_full = {idx_f["id"]: run["findings"][direction][i]
                  for i, idx_f in enumerate(index["findings"])
                  if direction in run.get("findings", {}) and i < len(run["findings"][direction])}
    approved_full = [id_to_full[f["id"]] for f in approved_rows if f["id"] in id_to_full]
    target_label = "105 (master)" if direction == "client_to_105" else "client"
    result = scriptgen.assemble(approved_full, target_label, direction,
                                include_deletions=False, include_irrelevant=True)
    apply_dir = run["run_dir"] / direction / "apply"
    apply_dir.mkdir(exist_ok=True)
    script_name = "add_update_on_105.sql" if direction == "client_to_105" else "add_update_on_client.sql"
    (apply_dir / script_name).write_text(result["script"], encoding="utf-8")
    (apply_dir / "manifest.json").write_text(json.dumps(result["manifest"], indent=1), encoding="utf-8")
    entry = ledger.append_entry(
        client_id=str(run["meta"].get("client_active_id") or "unset"),
        run_id=run_id, kind="update_package",
        payload={"direction": direction, "target": target_label,
                 "included": result["manifest"]["included"],
                 "skipped_irrelevant": result["manifest"]["skipped_irrelevant_to_client"],
                 "manual_review_count": len(result["manifest"]["manual_review"])})

    # PLAN-V5 Lane D / C4 auto-reverify: machine-check "did it land" by
    # re-entering the pipeline at compare phase (cached dacpacs -- no restore).
    # Best-effort BY DESIGN: verification failure must NEVER fail the package
    # response -- the artifacts above are already written and the ledger entry
    # already exists; a failed residue check is information, not an error.
    # Note recompare() rebuilds index.json fresh (review states reset), the
    # same accepted tradeoff as the existing manual /recompare endpoint --
    # and here it runs only after the package is fully assembled + persisted.
    verification = None
    try:
        rec = pipeline.recompare(run_id, direction, lambda m: print(f"[reverify] {m}"))
        # pipeline.recompare() returns a PER-DIRECTION payload ({run_id, meta,
        # index, findings}), NOT the multi-workspace {workspaces: {direction:
        # index_dict}} shape /api/compare's stream sends -- reading only
        # "workspaces" here would make residue_counts permanently None, so fall
        # back to its own "index" key (same counts dict either way).
        ws = rec.get("workspaces", {}).get(direction) or rec.get("index") or {}
        verification = {"recompare_run_id": rec.get("run_id"),
                        "residue_counts": ws.get("counts")}
    except Exception as e:
        verification = {"error": f"{type(e).__name__}: {e}"}
    return jsonify({"script": result["script"], "manifest": result["manifest"],
                    "script_name": script_name, "ledger_entry": entry})


@app.post("/api/run/<run_id>/<direction>/rehearse")
def api_rehearse_endpoint(run_id, direction):
    """PLAN-V4 B.4 rehearsal mode: runs the CURRENT assembled apply script
    against a scratch restore of the CLIENT backup -- measured facts, not
    predictions. The real target is never touched; the scratch DB always drops.
    Requires RUN_LIVE_DB=1 env (hermetic default refuses politely)."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    script_name = "add_update_on_105.sql" if direction == "client_to_105" else "add_update_on_client.sql"
    script_path = run["run_dir"] / direction / "apply" / script_name
    if not script_path.is_file():
        return jsonify({"error": "assemble an apply script first (Apply button)"}), 400
    batches = [b.strip() for b in script_path.read_text(encoding="utf-8").split("\nGO") if b.strip()]
    bak_path = ((run["meta"].get("bak_cache_key") or {}).get("client") or {}).get("path") or ""
    bak = Path(bak_path) if bak_path else Path()
    if not bak_path or not bak.is_file():
        return jsonify({
            "error": "rehearse is not available for a live client — restore a client .bak to scratch, or apply on a staging copy",
        }), 400
    report = executor.rehearse(bak, batches, lambda m: print(f"[rehearse] {m}"))
    out = run["run_dir"] / direction / "apply" / "execution_report.json"
    out.write_text(json.dumps(report, indent=1, default=str), encoding="utf-8")

    # PLAN-V5 Lane D / C4 auto-reverify -- identical shape to update_package's:
    # recompare the cached dacpac pair so the response carries what STILL
    # differs after this rehearsal (honest framing: rehearsal ran against a
    # scratch DB that is now dropped, so residue here = "not yet landed on
    # any real target"). Best-effort: never fail the report for a failed check.
    verification = None
    try:
        rec = pipeline.recompare(run_id, direction, lambda m: print(f"[reverify] {m}"))
        ws = rec.get("workspaces", {}).get(direction) or rec.get("index") or {}
        verification = {"recompare_run_id": rec.get("run_id"),
                        "residue_counts": ws.get("counts")}
    except Exception as e:
        verification = {"error": f"{type(e).__name__}: {e}"}
    return jsonify({**report, "verification": verification})


def _apply_waiting_prompt(session: ApplySession) -> dict | None:
    pending = session._pending  # noqa: SLF001 — HTTP layer mirrors apply_session prompt shape
    if not pending:
        return None
    return {
        "msgno": pending["msgno"],
        "msg": pending["msg"],
        "sql_preview": pending["sql_preview"],
        "index": pending["index"],
        "class": pending.get("class", "fatal"),
    }


def _apply_payload(session_id: str, session: ApplySession) -> dict:
    return {
        "session_id": session_id,
        "waiting": _apply_waiting_prompt(session),
        "done": session.done,
        "stopped": session.stopped,
        "report": session.report,
    }


def _close_apply_rec(rec: dict) -> None:
    conn = rec.get("conn")
    if conn is not None:
        try:
            conn.close()
        except Exception:  # noqa: BLE001 — best-effort close
            pass
    rec["conn"] = None
    rec["cur"] = None


def _drive_apply_session(rec: dict, decision: Decision | None = None) -> dict:
    """Run statements until paused for operator decision or finished."""
    session: ApplySession = rec["session"]
    cur = rec["cur"]
    batch_stop = rec.get("batch_stop_on_error", False)

    if decision is not None:
        session.decide(decision)

    while not session.done and session._pending is None:
        sql = session.current_statement()
        if not sql:
            break
        result = executor.run_statement(cur, sql)
        prompt = session.feed_result(result)
        if prompt and prompt.get("need_decision"):
            if batch_stop:
                session.decide(Decision(action="stop"))
                continue
            break

    if session.done:
        _close_apply_rec(rec)
    return _apply_payload(rec["session_id"], session)


@app.post("/api/run/<run_id>/<direction>/apply_start")
def api_apply_start(run_id, direction):
    """Interactive apply to the live client DB only (never 105)."""
    if direction == "client_to_105":
        return jsonify({"error": "apply to 105 is forbidden — use client_to_105 review scripts manually if intended"}), 403
    if direction != "105_to_client":
        return jsonify({"error": "unknown direction"}), 400

    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404

    body = request.get_json(force=True, silent=True) or {}
    client_side = body.get("client") or {}
    if not _conn_params(client_side, "client"):
        return jsonify({"error": "client needs server and database"}), 400

    master_side = run["meta"].get("master_side") or {}
    if master_side.get("kind") == "live" and _conn_key(client_side) == _conn_key(master_side):
        return jsonify({
            "error": "apply forbidden: client connection matches master (105) server and database",
        }), 403

    script_path = run["run_dir"] / direction / "apply" / "add_update_on_client.sql"
    if not script_path.is_file():
        return jsonify({"error": "assemble an apply script first (Apply button)"}), 400

    batches = [b.strip() for b in script_path.read_text(encoding="utf-8").split("\nGO") if b.strip()]
    try:
        conn = _sql_connect(client_side)
    except Exception as e:  # noqa: BLE001 — connection failure to caller
        return jsonify({"error": str(e)}), 400
    if conn is None:
        return jsonify({"error": "client needs server and database"}), 400

    session = ApplySession(batches)
    session_id = uuid.uuid4().hex
    rec = {
        "session_id": session_id,
        "session": session,
        "conn": conn,
        "cur": conn.cursor(),
        "run_id": run_id,
        "direction": direction,
        "batch_stop_on_error": request.headers.get("X-Batch") == "1",
        "on_error": body.get("on_error"),
    }
    APPLY_SESSIONS[session_id] = rec
    payload = _drive_apply_session(rec)
    if payload["done"]:
        APPLY_SESSIONS.pop(session_id, None)
    return jsonify(payload)


@app.post("/api/apply_session/<session_id>/decide")
def api_apply_session_decide(session_id):
    rec = APPLY_SESSIONS.get(session_id)
    if not rec:
        return jsonify({"error": "unknown or expired apply session"}), 404

    body = request.get_json(force=True, silent=True) or {}
    action = body.get("action")
    if action not in ("skip", "stop", "bind_skip", "bind_stop"):
        return jsonify({"error": f"bad action {action!r}"}), 400

    msgno = body.get("msgno")
    try:
        decision = Decision(action=action, msgno=int(msgno) if msgno is not None else None)
    except (TypeError, ValueError):
        return jsonify({"error": "msgno must be an integer when provided"}), 400

    try:
        payload = _drive_apply_session(rec, decision)
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

    if payload["done"]:
        APPLY_SESSIONS.pop(session_id, None)
    return jsonify(payload)


@app.post("/api/run/<run_id>/client_active_id")
def api_set_client_active_id(run_id):
    """Ask once per run, reuse silently: the frontend prompts for this the
    first time any 'Port to 105' action fires in a given run, then caches it
    client-side AND here -- a page reload or a second teammate opening the
    same run both see it via GET /api/run/<run_id>'s existing full `meta`."""
    run = _load_run(run_id)
    if not run:
        return jsonify({"error": "unknown run"}), 404
    body = request.get_json(force=True)
    client_active_id = body.get("client_active_id")
    if not client_active_id or not str(client_active_id).strip():
        return jsonify({"error": "client_active_id must be non-empty"}), 400
    run["meta"]["client_active_id"] = str(client_active_id).strip()
    (run["run_dir"] / "meta.json").write_text(json.dumps(run["meta"], indent=1), encoding="utf-8")
    return jsonify({"ok": True, "client_active_id": run["meta"]["client_active_id"]})


@app.post("/api/run/<run_id>/<direction>/merge_propose/<finding_id>")
def api_merge_propose(run_id, direction, finding_id):
    """AI-assisted merge proposal for a modified/structural/programmable
    finding: reuses statements.py's alignment (never re-implemented) to find
    the client's added/changed statements, then asks ai_merge to fold them
    into 105's CURRENT master_def. Cached per (run, direction, finding) to a
    `.merge_proposal.json` sidecar -- same convention as the existing
    per-finding `.ai.json` triage cache -- since master_def is fixed for the
    life of a run, a cached proposal can't go stale until a recompare, which
    writes a new run anyway. `?refresh=1` forces a fresh call."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    if direction != "client_to_105":
        return jsonify({"error": "merge proposal only applies to the client_to_105 direction"}), 400
    f = _finding_full(run, direction, finding_id)
    if not f:
        return jsonify({"error": "unknown finding_id"}), 404
    if f["role"] != "modified" or f["category"] != "structural" or f["type"] not in compare.PROGRAMMABLE_TYPES:
        return jsonify({"error": "port-to-105 only applies to modified, structural, programmable-object findings"}), 400

    cache_path = run["run_dir"] / direction / (f["path"] + ".merge_proposal.json")
    if cache_path.is_file() and request.args.get("refresh") != "1":
        return jsonify(json.loads(cache_path.read_text(encoding="utf-8")))

    client_active_id = run["meta"].get("client_active_id")
    if not client_active_id:
        return jsonify({"error": "no client_active_id set for this run yet -- call "
                                  "/api/run/<run_id>/client_active_id first"}), 400

    master_def, client_def = f.get("master_def") or "", f.get("client_def") or ""
    m_parsed = statements.parse_statements(master_def)
    c_parsed = statements.parse_statements(client_def)
    if not (m_parsed["ok"] and c_parsed["ok"]):
        return jsonify({"error": "statement structure unavailable for this finding "
                                  f"(master: {m_parsed['reason']}; client: {c_parsed['reason']}) -- "
                                  "cannot safely determine the merge delta"}), 400
    aligned = statements.align_statements(m_parsed["statements"], c_parsed["statements"])
    delta = [a for a in aligned if a["tag"] in ("added", "changed")]
    if not delta:
        return jsonify({"error": "no body-level delta between master and client for this finding -- "
                                  "the structural difference is signature/parameter-only"}), 400

    result = ai_merge.propose_merge(master_def, client_def, delta, client_active_id)
    result["master_def"] = master_def  # browser never otherwise receives raw finding text in bulk
    # Only cache a genuinely usable proposal -- an "unstructured" (garbled/
    # truncated) response or an "ok: False" failure is not a real answer, and
    # caching it would entomb a transient failure (e.g. a token-limit
    # truncation) forever until someone thinks to pass ?refresh=1.
    if result.get("proposed_master_def"):
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(result, indent=1), encoding="utf-8")
    return jsonify(result)


@app.post("/api/run/<run_id>/<direction>/merge_accept/<finding_id>")
def api_merge_accept(run_id, direction, finding_id):
    """Persists the (possibly user-edited) proposed text as a `.merged.sql`
    sidecar. Never applies anything by itself -- scriptgen.assemble() only
    picks this up once the finding is separately Approved and Assembled
    through the existing, unchanged review+Apply flow."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    idx = run["workspaces"][direction]
    row = next((f for f in idx["findings"] if f["id"] == finding_id), None)
    if not row:
        return jsonify({"error": "unknown finding_id"}), 404
    body = request.get_json(force=True)
    merged_text = body.get("merged_def")
    if not merged_text or not merged_text.strip():
        return jsonify({"error": "merged_def must be non-empty"}), 400

    base = run["run_dir"] / direction / row["path"]
    merged_path = Path(str(base) + ".merged.sql")
    merged_path.parent.mkdir(parents=True, exist_ok=True)
    merged_path.write_text(merged_text, encoding="utf-8")
    return jsonify({"ok": True})


@app.post("/api/diff_preview")
def api_diff_preview():
    """Generic ad-hoc text diff for previewing content that isn't a stored
    finding's own master_def/client_def -- e.g. an AI-proposed merge body vs
    105's current master_def. Reuses diff_render exactly as /richdiff does;
    no new diff logic, just a route that accepts two raw strings instead of
    reading them from a finding's sidecar files."""
    body = request.get_json(force=True)
    left, right = body.get("left", ""), body.get("right", "")
    view = body.get("view") or "split"
    if view == "unified":
        rich = diff_render.render_rich_diff(left, right)
    else:
        view = "split"
        rich = diff_render.render_split_diff(left, right)
    return jsonify({"kind": "text", "view": view, **rich})


@app.get("/api/ai_merge/test")
def api_ai_merge_test():
    """'Test AI connection' for the merge feature specifically -- separate
    button/route from /api/ai/test since this is a different key/provider
    (DeepSeek, not OpenRouter)."""
    return jsonify(ai_merge.test_connection())


@app.get("/api/run/<run_id>/metrics")
def api_metrics(run_id):
    """Computed on demand, not at pipeline end -- it's a disk-only read (index.json
    + captured evidence files), no live DB needed, and re-drawing the accuracy
    sample with a different ?seed= gives an independent second check for free."""
    run = _load_run(run_id)
    if not run:
        return jsonify({"error": "unknown run"}), 404
    seed = request.args.get("seed", default=0, type=int)
    sample_size = request.args.get("sample_size", default=40, type=int)
    try:
        result = metrics.compute(run["run_dir"], sample_size=sample_size, seed=seed)
    except Exception as e:  # noqa: BLE001 - surface computation failures to the GUI, don't swallow
        return jsonify({"error": f"metrics computation failed: {e}"}), 500
    return jsonify(result)


@app.get("/api/download/<run_id>/<artifact>")
def api_download(run_id, artifact):
    run = _load_run(run_id)
    if not run:
        return jsonify({"error": "unknown run"}), 404
    path = run["meta"]["artifacts"].get(artifact)
    if not path or not Path(path).is_file():
        return jsonify({"error": f"no artifact '{artifact}'"}), 404
    return send_file(path, as_attachment=True)


@app.get("/api/ai/test")
def api_ai_test():
    """'Test AI connection' button -- confirms the key + at least one model in
    the fallback chain actually answers, before the user relies on it mid-review."""
    return jsonify(ai.test_connection())


@app.post("/api/run/<run_id>/<direction>/ai/<finding_id>")
def api_ai_finding(run_id, direction, finding_id):
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    f = _finding_full(run, direction, finding_id)
    if not f:
        return jsonify({"error": "unknown finding_id"}), 404

    cache_path = run["run_dir"] / direction / (f["path"] + ".ai.json")
    force = request.args.get("refresh") == "1"
    if cache_path.is_file() and not force:
        return jsonify(json.loads(cache_path.read_text(encoding="utf-8")))
    if request.args.get("peek") == "1":
        # Reopening a finding should show its cached card immediately without
        # ever firing an uninvited AI call for findings nobody asked about yet
        # -- "on demand per finding" (PLAN.md §9) means the FIRST call is
        # explicit, not that every re-open silently re-triggers or skips one.
        return jsonify({"cached": False})

    result = ai.ask_about_finding(f)
    result["cached_at"] = time.time()
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(result, indent=1), encoding="utf-8")
    return jsonify(result)


@app.post("/api/run/<run_id>/<direction>/ai_batch")
def api_ai_batch(run_id, direction):
    """AI triage over multiple selected findings, capped and progress-streamed
    (same SSE job pattern as /api/compare) rather than one long blocking
    request -- never a blind sweep over every finding in a run."""
    run = _load_run(run_id)
    if not run or direction not in run["workspaces"]:
        return jsonify({"error": "unknown run or direction"}), 404
    body = request.get_json(force=True)
    finding_ids = list(dict.fromkeys(body.get("finding_ids") or []))  # de-dup, keep order
    if not finding_ids:
        return jsonify({"error": "no findings selected"}), 400
    if len(finding_ids) > AI_BATCH_CAP:
        return jsonify({"error": f"batch capped at {AI_BATCH_CAP} findings at a time "
                                  f"(selected {len(finding_ids)}) -- narrow the selection"}), 400

    job_id = uuid.uuid4().hex[:12]
    q: queue.Queue = queue.Queue()
    JOBS[job_id] = {"queue": q, "result": None, "error": None, "done": False, "kind": "ai_batch"}

    def log(msg: str):
        q.put(msg)

    def worker():
        results = {}
        try:
            for i, fid in enumerate(finding_ids, 1):
                f = _finding_full(run, direction, fid)
                if not f:
                    results[fid] = {"ok": False, "error": "unknown finding_id"}
                    log(f"[{i}/{len(finding_ids)}] unknown finding, skipped")
                    continue
                cache_path = run["run_dir"] / direction / (f["path"] + ".ai.json")
                if cache_path.is_file():
                    results[fid] = json.loads(cache_path.read_text(encoding="utf-8"))
                    log(f"[{i}/{len(finding_ids)}] {f['name']}: cached")
                    continue
                result = ai.ask_about_finding(f)
                result["cached_at"] = time.time()
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_text(json.dumps(result, indent=1), encoding="utf-8")
                results[fid] = result
                if result.get("ok") and result.get("suggestion"):
                    status = result["suggestion"]["recommendation"]
                elif result.get("ok"):
                    status = "unstructured response"
                else:
                    status = f"failed: {result.get('error')}"
                log(f"[{i}/{len(finding_ids)}] {f['name']}: {status}")
        except Exception as e:  # noqa: BLE001 - surface every failure to the GUI, don't swallow
            JOBS[job_id]["error"] = str(e)
        finally:
            JOBS[job_id]["result"] = results
            JOBS[job_id]["done"] = True
            q.put(None)

    threading.Thread(target=worker, daemon=True).start()
    return jsonify({"job_id": job_id})


@app.post("/api/datacopy/tables")
def api_datacopy_tables():
    body = request.get_json(force=True)
    _, err = _datacopy_dst_guard(body)
    if err:
        return err
    src_conn = _sql_connect(body.get("source") or {})
    if src_conn is None:
        return jsonify({"error": "source needs server + database"}), 400
    try:
        cur = src_conn.cursor(as_dict=True)
        tables = datacopy.list_config_tables(cur)
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": str(e)}), 400
    finally:
        src_conn.close()
    return jsonify({"tables": tables})


@app.post("/api/datacopy/preview")
def api_datacopy_preview():
    body = request.get_json(force=True)
    _, err = _datacopy_dst_guard(body)
    if err:
        return err
    tables = body.get("tables") or []
    if not tables:
        return jsonify({"error": "tables list required"}), 400
    include_delete = bool(body.get("include_delete", False))
    src_conn = _sql_connect(body.get("source") or {})
    dst_conn = _sql_connect(body.get("destination") or body.get("client") or {})
    if src_conn is None or dst_conn is None:
        return jsonify({"error": "source and destination each need server + database"}), 400
    results = []
    try:
        for table in tables:
            results.append(_datacopy_table_plan(src_conn, dst_conn, table, include_delete))
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": str(e)}), 400
    finally:
        src_conn.close()
        dst_conn.close()
    return jsonify({"tables": results})


@app.post("/api/datacopy/script")
def api_datacopy_script():
    body = request.get_json(force=True)
    _, err = _datacopy_dst_guard(body)
    if err:
        return err
    tables = body.get("tables") or []
    if not tables:
        return jsonify({"error": "tables list required"}), 400
    include_delete = bool(body.get("include_delete", False))
    src_conn = _sql_connect(body.get("source") or {})
    dst_conn = _sql_connect(body.get("destination") or body.get("client") or {})
    if src_conn is None or dst_conn is None:
        return jsonify({"error": "source and destination each need server + database"}), 400
    parts = []
    try:
        for table in tables:
            info = _datacopy_table_plan(src_conn, dst_conn, table, include_delete)
            parts.append(datacopy.emit_merge_script(
                info["table"], info["cols"], info["key_cols"], info["plan"]))
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": str(e)}), 400
    finally:
        src_conn.close()
        dst_conn.close()
    script = "\n".join(parts)
    run_id = body.get("run_id")
    direction = body.get("direction") or "105_to_client"
    if run_id:
        run = _load_run(run_id)
        if run:
            pkg = run["run_dir"] / "package"
            pkg.mkdir(exist_ok=True)
            (pkg / "datacopy.sql").write_text(script, encoding="utf-8")
    return jsonify({"script": script})


@app.post("/api/datacopy/apply")
def api_datacopy_apply():
    body = request.get_json(force=True)
    _, err = _datacopy_dst_guard(body)
    if err:
        return err
    tables = body.get("tables") or []
    if not tables:
        return jsonify({"error": "tables list required"}), 400
    include_delete = bool(body.get("include_delete", False))
    src_conn = _sql_connect(body.get("source") or {})
    dst_conn = _sql_connect(body.get("destination") or body.get("client") or {})
    if src_conn is None or dst_conn is None:
        return jsonify({"error": "source and destination each need server + database"}), 400
    inserted = updated = deleted = 0
    errors = []
    try:
        for table in tables:
            info = _datacopy_table_plan(src_conn, dst_conn, table, include_delete)
            dst_cur = dst_conn.cursor(as_dict=True)
            res = datacopy.apply_plan(
                dst_cur, info["table"], info["key_cols"], info["plan"],
                identity_cols=body.get("identity_cols"),
            )
            dst_conn.commit()
            inserted += res.get("inserted", 0)
            updated += res.get("updated", 0)
            deleted += res.get("deleted", 0)
            errors.extend(res.get("errors") or [])
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": str(e), "errors": errors}), 400
    finally:
        src_conn.close()
        dst_conn.close()
    return jsonify({"inserted": inserted, "updated": updated, "deleted": deleted, "errors": errors})


@app.post("/api/webdeploy/preview")
def api_webdeploy_preview():
    body = request.get_json(force=True)
    roots, err = _webdeploy_roots(body)
    if err:
        return err
    src, dst = roots
    if not src.is_dir():
        return jsonify({"error": f"not a directory: {src}"}), 400
    manifest = webdeploy.build_manifest(src, dst)
    return jsonify({
        "manifest": manifest,
        "copy_count": len(manifest.get("copy", [])),
        "delete_count": len(manifest.get("delete", [])),
    })


@app.post("/api/webdeploy/script")
def api_webdeploy_script():
    body = request.get_json(force=True)
    roots, err = _webdeploy_roots(body)
    if err:
        return err
    src, dst = roots
    if not src.is_dir():
        return jsonify({"error": f"not a directory: {src}"}), 400
    manifest = webdeploy.build_manifest(src, dst)
    text = webdeploy.emit_robocopy(manifest, src, dst)
    return jsonify({"script": text})


@app.post("/api/webdeploy/apply")
def api_webdeploy_apply():
    body = request.get_json(force=True)
    roots, err = _webdeploy_roots(body)
    if err:
        return err
    src, dst = roots
    if not src.is_dir():
        return jsonify({"error": f"not a directory: {src}"}), 400
    allow_delete = bool(body.get("allow_delete", False))
    manifest = webdeploy.build_manifest(src, dst)
    result = webdeploy.apply_copy(manifest, src, dst, allow_delete=allow_delete)
    return jsonify(result)


@app.get("/api/run/<run_id>/<direction>/package.zip")
def api_package_zip(run_id, direction):
    if direction == "client_to_105":
        return jsonify({"error": "package zip is client-targeted scripts only (not client_to_105)"}), 403
    run = _load_run(run_id)
    if not run or direction not in run.get("workspaces", {}):
        return jsonify({"error": "unknown run or direction"}), 404
    apply_dir = run["run_dir"] / direction / "apply"
    script_name = "add_update_on_client.sql"
    script_path = apply_dir / script_name
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        if script_path.is_file():
            zf.write(script_path, script_name)
        manifest_path = apply_dir / "manifest.json"
        if manifest_path.is_file():
            zf.write(manifest_path, "manifest.json")
        dc = run["run_dir"] / "package" / "datacopy.sql"
        if dc.is_file():
            zf.write(dc, "datacopy.sql")
        tutorial = Path(__file__).resolve().parent / "TUTORIAL.md"
        if tutorial.is_file():
            zf.writestr("TUTORIAL-snippet.md", tutorial.read_text(encoding="utf-8")[:8000])
    if not buf.tell():
        return jsonify({"error": "nothing to package — assemble a client script first"}), 400
    buf.seek(0)
    return send_file(buf, mimetype="application/zip", as_attachment=True,
                     download_name=f"{run_id}_{direction}_package.zip")


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5057, debug=False, threaded=True)
