# Plan: Scratch Server settings page (server, port, auth type, user, password)

Status: NOT STARTED. Written for an executor who follows it literally.
Repo root: the folder containing `app.py`. All paths below are relative to it.
Run tests with: `python3.13 -m pytest -q` (Linux) or `venv\Scripts\python -m pytest -q` (Windows).

---

## 0. Background (read first, do not skip)

### What a "scratch server" is

Every compare side that is a `.bak` file is RESTOREd into a temporary database on a
"scratch" SQL Server, scripted, extracted to a `.dacpac`, compared, and then dropped.
Rehearse does the same for the client `.bak`.

Today the scratch server is chosen ONLY by environment variables, read once at import
time in `drift/config.py`:

| Variable | Meaning today |
|----------|---------------|
| `DRIFT_SCRATCH_SERVER` | If set: use this SQL Server. If unset: use the Docker container `drift-tool-mssql` on `127.0.0.1:14330`. |
| `DRIFT_SCRATCH_PORT` | Port (default 1433). Ignored when the server name contains `\` (named instance). |
| `DRIFT_SCRATCH_USER` / `DRIFT_SCRATCH_PASSWORD` | SQL login. |

Only SQL Server authentication exists. There is NO settings page. The only connection
forms in the UI are the Master/Client "Live" forms on the SQL Compare > Schema tab
(`templates/index.html` lines ~152-196); those are for live compare targets, NOT the
scratch server. Do not touch them in this plan.

### Goal

1. Add a **Settings** page (new top tab) where the user picks:
   - Mode: **Docker container** or **SQL Server (this machine or reachable by IP)**
   - Server (hostname, IP, or `host\INSTANCE`)
   - Port
   - Authentication: **SQL Server login** or **Windows authentication**
   - Username, Password (SQL login only)
   - Buttons: **Test connection**, **Save**
2. Support **Windows authentication** for the scratch server (Windows only).
3. Settings persist in `work/scratch_server.json` and apply without restarting the app.
4. Environment variables still work and, when present, win (the page shows them read-only).
5. Docker mode and all existing behavior stay exactly the same when nothing is configured.

### Hard rules for the executor

- Do NOT change anything about live compare sides (`livescan.py`, `_sql_connect`,
  `/api/live/databases`, the Live forms). Scope is the scratch server only.
- Do NOT return the saved password to the browser, ever. Not in GET, not in errors, not in logs.
- Do NOT run `DBCC TRACEON` or any server-wide setting on a non-Docker server (already true; keep it).
- Every step ends with running the full test suite. If it fails, fix before moving on.
- Keep code style: small functions, docstrings only where the code cannot say it, no new
  dependencies except the conditional one in Phase 1 (pyodbc) if and only if the spike says so.

---

## Phase 1: Spike (on the WINDOWS machine) — decide the Windows-auth driver

Windows authentication must work in two places:

- **pymssql** (all SQL the tool runs: RESTORE, catalog queries, DROP).
- **sqlpackage** (`/Action:Extract`). sqlpackage supports `/SourceTrustedConnection:True`
  natively, so this part is known to work.

pymssql's Windows wheels are built on FreeTDS. When `user` is empty on Windows, FreeTDS
may use the current Windows login (SSPI). This MUST be verified on the real machine before
writing code, because it decides the design.

### Step 1.1 — Run this on the Windows machine

In the repo folder, with the build venv (or any venv with `pip install pymssql`):

```bat
.build-venv\Scripts\python -c "import pymssql; c = pymssql.connect(server='localhost', login_timeout=5); cur = c.cursor(); cur.execute('SELECT SUSER_SNAME(), @@VERSION'); print(cur.fetchone())"
```

If the instance is named, replace `'localhost'` with `r'localhost\SQLEXPRESS'`.

### Step 1.2 — Read the result

- **It prints `('MACHINE\\username', 'Microsoft SQL Server ...')`**: pymssql supports Windows
  auth by passing no user and no password. Record "DRIVER = pymssql" and do Phase 3A.
  Skip Phase 3B entirely.
- **It raises an error** (typically `Login failed` / `18456` / `20002`): pymssql cannot do
  Windows auth here. Record "DRIVER = pyodbc" and do Phase 3B. Skip Phase 3A.

Write the outcome as the first line under "Status:" at the top of this file, e.g.
`Spike result (2026-..-..): pymssql Windows auth WORKS` — so later readers know.

---

## Phase 2: Settings storage and config API (both OSes, no UI yet)

### Step 2.1 — Settings file format

File: `work/scratch_server.json` (gitignored because `work/` is gitignored). Shape:

```json
{
  "mode": "local",
  "server": "localhost",
  "port": 1433,
  "auth": "sql",
  "user": "drift",
  "password": "secret"
}
```

- `mode`: `"docker"` or `"local"`. (`"local"` means "a SQL Server I point at", including by IP.)
- `auth`: `"sql"` or `"windows"`.
- `port`: integer 1-65535. Ignored when `server` contains `\`.
- `user` / `password`: required when `auth == "sql"`, must be empty strings when `auth == "windows"`.

File missing or unparseable → treat as `{"mode": "docker"}` and print one line
`[settings] ignoring unreadable work/scratch_server.json: <error>` (never crash startup).

### Step 2.2 — Replace the import-time constants in `drift/config.py`

Currently (lines ~72-101) `config.py` has module constants `SCRATCH_SERVER`, `USE_DOCKER`,
`SCRATCH_PORT`, `SCRATCH_USER` and functions `scratch_password()`,
`scratch_connect_kwargs()`, `scratch_sqlpackage_server()`.

Delete that whole block and replace it with the following API. Keep `CONTAINER_NAME`,
`HOST_PORT`, `SA_USER`, `SA_PASSWORD`, `SA_PASSWORD_FILE`, `_sa_password()` unchanged.

```python
SCRATCH_SETTINGS_FILE = WORK_DIR / "scratch_server.json"
_ENV_KEYS = ("DRIFT_SCRATCH_SERVER", "DRIFT_SCRATCH_PORT", "DRIFT_SCRATCH_USER",
             "DRIFT_SCRATCH_PASSWORD", "DRIFT_SCRATCH_AUTH")


def scratch_env_locked() -> bool:
    """True when any DRIFT_SCRATCH_* variable is set: env wins over the Settings page."""
    return any(os.environ.get(k, "").strip() for k in _ENV_KEYS)


def _normalize_server(server: str) -> str:
    """'.' and '(local)' are SSMS spellings that pymssql/FreeTDS do not understand."""
    s = server.strip()
    head, sep, instance = s.partition("\\")
    if head.lower() in {".", "(local)"}:
        head = "localhost"
    return head + sep + instance


def scratch_settings() -> dict:
    """Current scratch-server settings, read fresh on every call (cheap: one small file)."""
    if scratch_env_locked():
        server = os.environ.get("DRIFT_SCRATCH_SERVER", "").strip()
        return {
            "mode": "local" if server else "docker",
            "server": _normalize_server(server),
            "port": int(os.environ.get("DRIFT_SCRATCH_PORT", "").strip() or 1433),
            "auth": (os.environ.get("DRIFT_SCRATCH_AUTH", "").strip().lower() or "sql"),
            "user": os.environ.get("DRIFT_SCRATCH_USER", "").strip(),
            "password": os.environ.get("DRIFT_SCRATCH_PASSWORD", ""),
            "source": "env",
        }
    try:
        data = json.loads(SCRATCH_SETTINGS_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        data = {}
    except (OSError, ValueError) as e:
        print(f"[settings] ignoring unreadable {SCRATCH_SETTINGS_FILE.name}: {e}")
        data = {}
    mode = data.get("mode") if data.get("mode") in ("docker", "local") else "docker"
    return {
        "mode": mode,
        "server": _normalize_server(str(data.get("server") or "")),
        "port": int(data.get("port") or 1433),
        "auth": data.get("auth") if data.get("auth") in ("sql", "windows") else "sql",
        "user": str(data.get("user") or ""),
        "password": str(data.get("password") or ""),
        "source": "file" if data else "default",
    }


def use_docker() -> bool:
    return scratch_settings()["mode"] == "docker"


def scratch_connect_kwargs(settings: dict | None = None) -> dict:
    """pymssql server/port/user/password for the scratch server.
    Windows auth = no user and no password (only valid if the Phase 1 spike passed)."""
    s = settings or scratch_settings()
    if s["mode"] == "docker":
        return {"server": "127.0.0.1", "port": HOST_PORT, "user": SA_USER, "password": SA_PASSWORD}
    server = {"server": s["server"]} if "\\" in s["server"] else {"server": s["server"], "port": s["port"]}
    if s["auth"] == "windows":
        return server
    return {**server, "user": s["user"], "password": s["password"]}


def scratch_sqlpackage_server(settings: dict | None = None) -> str:
    kw = scratch_connect_kwargs(settings)
    return f"{kw['server']},{kw['port']}" if "port" in kw else kw["server"]
```

Also add `import json` at the top of `config.py`.

IMPORTANT: `SA_PASSWORD` is read inside the function at call time (`docker_mgmt` can
replace `config.SA_PASSWORD` when it adopts the container's password). Do not capture it
in a default argument.

### Step 2.3 — `save_scratch_settings()` in `drift/config.py`

```python
def save_scratch_settings(new: dict) -> dict:
    """Validate and write work/scratch_server.json. Returns the saved dict (with password).
    Raises ValueError with a user-facing message on bad input."""
    mode = new.get("mode")
    if mode not in ("docker", "local"):
        raise ValueError("mode must be 'docker' or 'local'")
    if mode == "docker":
        out = {"mode": "docker"}
    else:
        server = _normalize_server(str(new.get("server") or ""))
        if not server:
            raise ValueError("server is required")
        try:
            port = int(new.get("port") or 1433)
        except (TypeError, ValueError):
            raise ValueError("port must be a number") from None
        if not 1 <= port <= 65535:
            raise ValueError("port must be between 1 and 65535")
        auth = new.get("auth")
        if auth not in ("sql", "windows"):
            raise ValueError("auth must be 'sql' or 'windows'")
        if auth == "windows" and os.name != "nt":
            raise ValueError("Windows authentication is only available when the tool runs on Windows")
        user = str(new.get("user") or "").strip()
        password = str(new.get("password") or "")
        if auth == "sql":
            if not user:
                raise ValueError("username is required for SQL Server login")
            if not password:
                password = scratch_settings().get("password", "")  # blank = keep saved one
            if not password:
                raise ValueError("password is required for SQL Server login")
        else:
            user, password = "", ""
        out = {"mode": "local", "server": server, "port": port, "auth": auth,
               "user": user, "password": password}
    tmp = SCRATCH_SETTINGS_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(out, indent=1), encoding="utf-8")
    os.replace(tmp, SCRATCH_SETTINGS_FILE)  # atomic on Windows and Linux
    return out
```

The "blank password keeps the saved one" rule exists because the page never shows the
saved password; a user who only changes the port must not have to retype it.

### Step 2.4 — Update every caller of the removed names

Search: `rg -n "USE_DOCKER|SCRATCH_SERVER|SCRATCH_PORT|SCRATCH_USER|scratch_password" --glob '*.py'`

Expected hits and exact replacements:

| File | Old | New |
|------|-----|-----|
| `drift/docker_mgmt.py` `ensure_running` | `if not config.USE_DOCKER:` | `if not config.use_docker():` |
| `drift/restore.py` `restore_backup` | `if config.USE_DOCKER:` | `if config.use_docker():` |
| `drift/extract.py` `extract_dacpac` | builds cmd with `/SourceUser:{config.SCRATCH_USER}` and password file | see Step 2.5 |
| `tests/test_scratch_server.py` | patches `config.USE_DOCKER` etc. | rewrite, see Phase 5 |

`drift/restore.py` `_connect`/`open_connection`, `drift/docker_mgmt.py` `_wait_for_sql` /
`_disable_parallel_redo`, `drift/prepare_bench.py` already call
`config.scratch_connect_kwargs()` — no change needed, they automatically get Windows auth.

### Step 2.5 — `drift/extract.py` `extract_dacpac` with both auth types

Replace the body of `extract_dacpac` with:

```python
def extract_dacpac(db_name: str, out_path, log) -> str:
    """Extract from the scratch SQL Server (Docker container or configured server)."""
    log(f"extracting schema of [{db_name}] to {Path(out_path).name}...")
    settings = config.scratch_settings()
    kw = config.scratch_connect_kwargs(settings)
    cmd = [
        config.SQLPACKAGE_BIN,
        "/Action:Extract",
        f"/SourceServerName:{config.scratch_sqlpackage_server(settings)}",
        f"/SourceDatabaseName:{db_name}",
        "/SourceTrustServerCertificate:True",
        f"/TargetFile:{out_path}",
        "/p:ExtractAllTableData=false",
        "/p:VerifyExtraction=false",
    ]
    if "user" not in kw:  # Windows authentication
        return _run_extract(cmd + ["/SourceTrustedConnection:True"], db_name, log, out_path)
    cmd.insert(4, f"/SourceUser:{kw['user']}")
    return _extract_with_password(cmd, kw["password"], db_name, log, out_path)
```

Run tests. Expect `tests/test_scratch_server.py` to fail until Phase 5; everything else must pass.

---

## Phase 3A: Windows auth via pymssql (ONLY if the spike PASSED)

Nothing more to do in code: `scratch_connect_kwargs` already omits user/password for
Windows auth, and pymssql uses the Windows login. Go to Phase 4.

## Phase 3B: Windows auth via pyodbc (ONLY if the spike FAILED)

pymssql stays for everything else. Only the scratch connection with `auth == "windows"` uses
pyodbc, wrapped so callers see the same interface they use today.

What callers rely on (verified in the code):
- `conn.cursor(as_dict=True)` returning rows as dicts; plain `conn.cursor()` returning tuples.
- `%s` placeholders in `cur.execute(sql, params)` (e.g. `inspect_objects.fetch_by_names`).
- `cur.fetchone()`, `cur.fetchall()`, `conn.close()`, `autocommit=True` at connect.
- `pymssql.OperationalError` caught in `restore.restore_backup`.

### Step 3B.1 — Dependency

Add to `requirements.txt` a new line: `pyodbc; sys_platform == "win32"`.
The machine needs "ODBC Driver 18 for SQL Server" or 17 (installed with SSMS / SQL Server).

### Step 3B.2 — New file `drift/scratch_odbc.py`

```python
"""Windows-authentication connections to the scratch server via pyodbc, shaped like
pymssql connections so restore/inspect/changelog code does not change."""
import re

import pymssql

_PARAM = re.compile(r"%s")


def _driver() -> str:
    import pyodbc
    names = [d for d in pyodbc.drivers() if "SQL Server" in d]
    for preferred in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if preferred in names:
            return preferred
    if names:
        return names[-1]
    raise RuntimeError("no SQL Server ODBC driver installed (install ODBC Driver 18 for SQL Server)")


class _Cursor:
    def __init__(self, cur, as_dict):
        self._cur, self._as_dict = cur, as_dict

    def execute(self, sql, params=None):
        sql = _PARAM.sub("?", sql)
        if params is None:
            self._cur.execute(sql)
        else:
            self._cur.execute(sql, tuple(params) if isinstance(params, (list, tuple)) else (params,))
        return self

    def _row(self, row):
        if row is None or not self._as_dict:
            return None if row is None else tuple(row)
        return {d[0]: v for d, v in zip(self._cur.description, row)}

    def fetchone(self):
        return self._row(self._cur.fetchone())

    def fetchall(self):
        return [self._row(r) for r in self._cur.fetchall()]

    def __iter__(self):
        return iter(self.fetchall())


class _Conn:
    def __init__(self, conn):
        self._conn = conn

    def cursor(self, as_dict=False):
        return _Cursor(self._conn.cursor(), as_dict)

    def commit(self):
        self._conn.commit()

    def close(self):
        self._conn.close()


def connect(server, port=None, database=None, autocommit=True, timeout=0, login_timeout=10, **_):
    import pyodbc
    host = server if port is None else f"{server},{port}"
    cs = (f"DRIVER={{{_driver()}}};SERVER={host};Trusted_Connection=yes;"
          f"TrustServerCertificate=yes;DATABASE={database or 'master'}")
    try:
        conn = pyodbc.connect(cs, autocommit=autocommit, timeout=login_timeout)
    except pyodbc.Error as e:
        raise pymssql.OperationalError(str(e)) from e
    if timeout:
        conn.timeout = timeout
    return _Conn(conn)
```

Note: `%s` inside SQL string literals must not occur in the scratch-side modules, or the
`%s` → `?` rewrite would corrupt them. Check:
`rg -n "'%s'" drift/restore.py drift/inspect_objects.py drift/dependencies.py drift/changelog.py drift/convert.py drift/executor.py drift/docker_mgmt.py`
must return nothing; if it returns something, stop and report. (`drift/datacopy.py` has one,
but it only uses live connections, never the scratch server, so it is unaffected.)

RESTORE must not run inside a transaction: pyodbc with `autocommit=True` is required.
`restore._connect` already passes `autocommit=True`. Keep it.

### Step 3B.3 — One connect function for the scratch server

In `drift/restore.py` add:

```python
def scratch_connect(**extra):
    """All scratch-server connections go through here (Docker, SQL login, or Windows auth)."""
    kw = config.scratch_connect_kwargs()
    if "user" not in kw and config.scratch_settings()["mode"] == "local":
        from . import scratch_odbc
        return scratch_odbc.connect(**kw, **extra)
    return pymssql.connect(**kw, **extra)
```

Then replace, one by one:

- `restore._connect`: `return pymssql.connect(**config.scratch_connect_kwargs(), database=..., ...)`
  → `return scratch_connect(database=database, autocommit=autocommit, timeout=0, login_timeout=10)`
- `restore.open_connection` final `return pymssql.connect(**config.scratch_connect_kwargs(), ...)`
  → `return scratch_connect(database=scratch_db, autocommit=autocommit, timeout=timeout, login_timeout=10)`
  (leave the `kind == "live"` branch above it untouched)
- `drift/docker_mgmt.py` `_wait_for_sql`: `pymssql.connect(**config.scratch_connect_kwargs(), timeout=5, login_timeout=5)`
  → `restore.scratch_connect(timeout=5, login_timeout=5)` and add `from . import restore` inside the function
  (inside, to avoid an import cycle).
- `_disable_parallel_redo` only runs in Docker mode; leave it as pymssql.
- `drift/prepare_bench.py` is dev-only; leave it.

---

## Phase 4: HTTP API in `app.py`

Add these three routes next to the other `/api/desktop/...` routes (around line 224).
Add `import os` at the top of `app.py` if missing.

### Step 4.1 — Busy guard

A running compare or rehearse must not have its scratch server swapped mid-run
(restore on server A, then DROP on server B). Add near `APPLY_SESSIONS`:

```python
_SCRATCH_BUSY = 0
_SCRATCH_BUSY_LOCK = threading.Lock()


def _scratch_in_use() -> bool:
    if _SCRATCH_BUSY:
        return True
    return any(j.get("kind") == "compare" and not j.get("done") for j in JOBS.values())
```

In `api_rehearse_endpoint`, wrap ONLY the `executor.rehearse(...)` call:

```python
    global _SCRATCH_BUSY
    with _SCRATCH_BUSY_LOCK:
        _SCRATCH_BUSY += 1
    try:
        report = executor.rehearse(bak, batches, lambda m: print(f"[rehearse] {m}"))
    finally:
        with _SCRATCH_BUSY_LOCK:
            _SCRATCH_BUSY -= 1
```

Verify `_start_compare_job` creates JOBS entries with `"kind": "compare"`; if it uses a
different kind string, use that string in `_scratch_in_use`.

### Step 4.2 — GET `/api/scratch/settings`

```python
def _public_settings(s: dict) -> dict:
    return {
        "mode": s["mode"], "server": s["server"], "port": s["port"], "auth": s["auth"],
        "user": s["user"], "has_password": bool(s["password"]),
        "source": s["source"], "env_locked": s["source"] == "env",
        "windows_auth_available": os.name == "nt",
    }


@app.get("/api/scratch/settings")
def api_scratch_settings_get():
    return jsonify(_public_settings(config.scratch_settings()))
```

### Step 4.3 — POST `/api/scratch/settings` (save)

```python
@app.post("/api/scratch/settings")
def api_scratch_settings_save():
    if config.scratch_env_locked():
        return jsonify({"error": "settings come from DRIFT_SCRATCH_* environment variables or .env; edit those instead"}), 409
    if _scratch_in_use():
        return jsonify({"error": "a compare or rehearse is running; save again when it finishes"}), 409
    try:
        config.save_scratch_settings(request.get_json(silent=True) or {})
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    return jsonify({"ok": True, "settings": _public_settings(config.scratch_settings())})
```

### Step 4.4 — POST `/api/scratch/test` (test WITHOUT saving)

Takes the same body as save. Blank password with `auth == "sql"` means "use the saved one".
Returns diagnostics the user needs to fix problems before a 10-minute compare fails:

```python
@app.post("/api/scratch/test")
def api_scratch_test():
    body = request.get_json(silent=True) or {}
    if body.get("mode") == "docker":
        try:
            docker_mgmt.ensure_running(lambda m: None)
        except Exception as e:  # noqa: BLE001
            return jsonify({"ok": False, "error": str(e)}), 200
        return jsonify({"ok": True, "message": "Docker scratch container is running"})
    saved = config.scratch_settings()
    candidate = {
        "mode": "local",
        "server": config._normalize_server(str(body.get("server") or "")),
        "port": int(body.get("port") or 1433),
        "auth": body.get("auth") or "sql",
        "user": str(body.get("user") or "").strip(),
        "password": str(body.get("password") or "") or saved.get("password", ""),
    }
    if not candidate["server"]:
        return jsonify({"ok": False, "error": "server is required"}), 200
    if candidate["auth"] == "windows" and os.name != "nt":
        return jsonify({"ok": False, "error": "Windows authentication only works when the tool runs on Windows"}), 200
    try:
        conn = _scratch_test_connect(candidate)
        cur = conn.cursor(as_dict=True)
        cur.execute(
            "SELECT SUSER_SNAME() AS login_name, "
            "CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS version, "
            "CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS edition, "
            "IS_SRVROLEMEMBER('sysadmin') AS is_sysadmin, "
            "IS_SRVROLEMEMBER('dbcreator') AS is_dbcreator, "
            "CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(4000)) AS data_dir"
        )
        row = cur.fetchone()
        conn.close()
    except Exception as e:  # noqa: BLE001 - shown to the user as the test result
        return jsonify({"ok": False, "error": str(e)[:500]}), 200
    can_restore = bool(row["is_sysadmin"]) or bool(row["is_dbcreator"])
    return jsonify({
        "ok": True, "login_name": row["login_name"], "version": row["version"],
        "edition": row["edition"], "data_dir": row["data_dir"], "can_restore": can_restore,
        "warning": None if can_restore else
            "this login is not sysadmin or dbcreator; RESTORE and DROP DATABASE will fail",
    })
```

`_scratch_test_connect(candidate)`:
- Phase 3A (pymssql): `return pymssql.connect(**config.scratch_connect_kwargs(candidate), login_timeout=5, timeout=15)`
- Phase 3B (pyodbc): if `candidate["auth"] == "windows"` use `scratch_odbc.connect(**config.scratch_connect_kwargs(candidate), login_timeout=5, timeout=15)`, else the pymssql line above.

Never include the password in any response or `print`.

Status 200 with `ok: false` for connection failures is deliberate: the page shows the
message; 4xx is reserved for malformed requests.

---

## Phase 5: Tests

Rewrite `tests/test_scratch_server.py` completely. Use `tmp_path`-style temp dirs by
patching `config.SCRATCH_SETTINGS_FILE` to a file in `tempfile.mkdtemp()`, and
`patch.dict("os.environ", {...}, clear=False)` removing all `DRIFT_SCRATCH_*` keys for
file-based tests. Required test cases (one function each):

1. `test_no_file_no_env_is_docker` → `scratch_settings()["mode"] == "docker"`, kwargs target `127.0.0.1`/`HOST_PORT`/`sa`.
2. `test_corrupt_file_falls_back_to_docker` → file contains `{not json` → mode docker, no exception.
3. `test_file_sql_login` → saved local/sql → kwargs have server, port, user, password.
4. `test_file_named_instance_has_no_port` → server `localhost\SQLEXPRESS` → no `port` key; sqlpackage server string has no comma.
5. `test_windows_auth_kwargs_have_no_credentials` → auth windows → kwargs have no `user`/`password`.
6. `test_dot_and_local_normalize_to_localhost` → `.` → `localhost`; `(local)\SQLEXPRESS` → `localhost\SQLEXPRESS`.
7. `test_env_overrides_file` → file says local A, env `DRIFT_SCRATCH_SERVER=B` → server B, source env.
8. `test_save_blank_password_keeps_saved` → save with password, save again with blank → password unchanged.
9. `test_save_rejects_windows_auth_on_linux` → patch `config.os.name` to `"posix"` → ValueError.
10. `test_save_validates_port_and_server` → port 0, port "abc", empty server → ValueError each.
11. `test_extract_uses_trusted_connection_for_windows_auth` → patch settings to windows auth, patch `drift.extract.subprocess.run`, call `extract.extract_dacpac` → argv contains `/SourceTrustedConnection:True` and no `/SourceUser:` and no `@` response file.
12. `test_extract_sql_login_uses_password_file` → argv contains `/SourceUser:drift` and an `@...rsp` arg; password is not in argv.
13. Keep the two existing tests (`test_local_restore_reads_file_in_place_and_uses_instance_dirs`,
    `test_local_ensure_running_never_calls_docker_or_trace_flags`) but make them set settings
    through a temp settings file instead of patching removed constants.

New file `tests/test_scratch_api.py` using `app.app.test_client()`:

14. `test_get_never_returns_password` → after saving a password, GET JSON has no `password` key and `has_password` is true.
15. `test_save_blocked_when_env_locked` → env `DRIFT_SCRATCH_SERVER=x` → POST 409.
16. `test_save_blocked_while_compare_running` → insert `JOBS["x"] = {"kind": "compare", "done": False}` → POST 409; remove it afterwards.
17. `test_save_bad_input_400` → `{"mode": "local"}` with no server → 400 with message.
18. `test_test_endpoint_reports_connect_error` → patch the connect to raise → 200, `ok: false`, message present, no password in body.

Phase 3B only, new file `tests/test_scratch_odbc.py` (skip whole module if `pyodbc` not importable):

19. `%s` → `?` conversion, dict rows with `as_dict=True`, tuple rows without, `fetchone()` None passthrough — using a fake pyodbc cursor object with `description` and canned rows.

Run the full suite. All must pass.

---

## Phase 6: UI — the Settings page

### Step 6.1 — Tab button in `templates/index.html`

Inside `<nav class="tool-tabs" id="toolTabs" ...>` (line ~23), after the "Drift tool" button, add:

```html
      <button type="button" role="tab" id="toolTabSettings" class="tool-tab tab-tip" data-tool="settings" aria-selected="false"
        title="Where .bak files are restored: Docker container or your SQL Server (server, port, authentication).">Settings</button>
```

### Step 6.2 — Pane in `templates/index.html`

After the closing `</div>` of `paneCompare` and before the Drift pane (search for
`data-tool="drift"` on a `tool-pane` div and insert BEFORE it):

```html
    <div id="paneSettings" class="tool-pane" data-tool="settings" hidden>
      <h1>Settings</h1>
      <div class="sub">Where <code>.bak</code> files are restored for compare and rehearse. Temporary databases are always named <code>drift_*</code> / <code>zz_rehearsal_*</code> and are dropped afterwards.</div>
      <section class="block glass-panel" id="scratchSettings">
        <p id="scratchEnvLocked" class="run-warning" hidden>These values come from <code>DRIFT_SCRATCH_*</code> environment variables or <code>.env</code>. Edit those to change them.</p>
        <div class="side-mode-toggle" role="radiogroup" aria-label="Scratch server mode">
          <label><input type="radio" name="scratchMode" value="docker" checked> Docker container</label>
          <label><input type="radio" name="scratchMode" value="local"> SQL Server</label>
        </div>
        <div id="scratchLocalFields" hidden>
          <label class="trim-label">Server <input id="scratchServer" class="live-in" autocomplete="off" placeholder="localhost, 192.168.1.10, or localhost\SQLEXPRESS"></label>
          <label class="trim-label">Port <input id="scratchPort" class="live-in" inputmode="numeric" value="1433"></label>
          <label class="trim-label">Authentication
            <select id="scratchAuth" class="live-in">
              <option value="sql">SQL Server login</option>
              <option value="windows">Windows authentication</option>
            </select>
          </label>
          <label class="trim-label">Username <input id="scratchUser" class="live-in" autocomplete="username"></label>
          <label class="trim-label">Password <input id="scratchPass" type="password" class="live-in" autocomplete="off"></label>
          <p id="scratchRemoteHint" class="hint" hidden>This is not this machine. The SQL Server reads the <code>.bak</code> from ITS disk, so the backup path you pick must also exist on that server (for example a shared <code>\\server\share</code> path).</p>
          <p id="scratchWinAuthHint" class="hint" hidden>Signs in as the Windows user running Drift Tool.</p>
        </div>
        <div class="drift-copy-row">
          <button type="button" class="ghost sm" id="scratchTestBtn">Test connection</button>
          <button type="button" id="scratchSaveBtn">Save</button>
          <span id="scratchStatus" class="hint" role="status" aria-live="polite"></span>
        </div>
      </section>
    </div>
```

Reuse existing CSS classes only (`block`, `glass-panel`, `trim-label`, `live-in`, `hint`,
`run-warning`, `side-mode-toggle`, `drift-copy-row`, `ghost sm`). Do not add CSS unless a
field is visibly broken; if you must, add at most a `#scratchLocalFields { display: grid; gap: 8px; max-width: 520px; }` rule to `static/style.css`.

### Step 6.3 — JavaScript in `static/app.js`

Add a new section at the END of the file (after everything else, so all helpers exist):

```javascript
/* ============================== Settings (scratch server) ============================== */

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", ".", "(local)"]);

function scratchForm() {
  const mode = document.querySelector('input[name="scratchMode"]:checked')?.value || "docker";
  return {
    mode,
    server: document.getElementById("scratchServer").value.trim(),
    port: document.getElementById("scratchPort").value.trim() || "1433",
    auth: document.getElementById("scratchAuth").value,
    user: document.getElementById("scratchUser").value.trim(),
    password: document.getElementById("scratchPass").value,
  };
}

function updateScratchFieldGates() {
  const f = scratchForm();
  const local = f.mode === "local";
  const win = f.auth === "windows";
  const named = f.server.includes("\\");
  const host = f.server.split("\\")[0].toLowerCase();
  document.getElementById("scratchLocalFields").hidden = !local;
  document.getElementById("scratchPort").disabled = named;
  document.getElementById("scratchUser").disabled = win;
  document.getElementById("scratchPass").disabled = win;
  document.getElementById("scratchWinAuthHint").hidden = !win;
  document.getElementById("scratchRemoteHint").hidden = !local || !f.server || LOCAL_HOSTS.has(host);
}

function setScratchStatus(text, isError) {
  const el = document.getElementById("scratchStatus");
  el.textContent = text;
  el.style.color = isError ? "var(--danger, #c0392b)" : "";
}

async function loadScratchSettings() {
  let s;
  try {
    s = await (await fetch("/api/scratch/settings")).json();
  } catch (err) {
    setScratchStatus(String(err), true);
    return;
  }
  document.querySelector(`input[name="scratchMode"][value="${s.mode}"]`).checked = true;
  document.getElementById("scratchServer").value = s.server || "";
  document.getElementById("scratchPort").value = s.port || 1433;
  document.getElementById("scratchAuth").value = s.auth || "sql";
  document.getElementById("scratchUser").value = s.user || "";
  const pass = document.getElementById("scratchPass");
  pass.value = "";
  pass.placeholder = s.has_password ? "saved (leave blank to keep)" : "";
  const winOpt = document.querySelector('#scratchAuth option[value="windows"]');
  winOpt.disabled = !s.windows_auth_available;
  winOpt.textContent = s.windows_auth_available ? "Windows authentication" : "Windows authentication (Windows only)";
  const locked = !!s.env_locked;
  document.getElementById("scratchEnvLocked").hidden = !locked;
  document.querySelectorAll("#scratchSettings input, #scratchSettings select, #scratchSaveBtn")
    .forEach(el => { if (el.id !== "scratchTestBtn") el.disabled = locked; });
  updateScratchFieldGates();
  if (locked) document.getElementById("scratchSaveBtn").disabled = true;
  setScratchStatus(s.source === "default" ? "Using Docker (nothing saved yet)." : "", false);
}

async function testScratchSettings() {
  setScratchStatus("Testing…", false);
  let body;
  try {
    const resp = await fetch("/api/scratch/test", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(scratchForm()),
    });
    body = await resp.json();
  } catch (err) {
    setScratchStatus(String(err), true);
    return;
  }
  if (!body.ok) { setScratchStatus(`Failed: ${body.error}`, true); return; }
  if (body.message) { setScratchStatus(body.message, false); return; }
  const parts = [`Connected as ${body.login_name}`, `SQL Server ${body.version} (${body.edition})`];
  if (body.warning) { setScratchStatus(`${parts.join(" · ")} · WARNING: ${body.warning}`, true); return; }
  setScratchStatus(`${parts.join(" · ")} · can restore ✓`, false);
}

async function saveScratchSettings() {
  setScratchStatus("Saving…", false);
  let resp, body;
  try {
    resp = await fetch("/api/scratch/settings", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(scratchForm()),
    });
    body = await resp.json();
  } catch (err) {
    setScratchStatus(String(err), true);
    return;
  }
  if (!resp.ok) { setScratchStatus(body.error || `Save failed (${resp.status})`, true); return; }
  await loadScratchSettings();
  setScratchStatus("Saved. The next compare uses these settings.", false);
}

document.querySelectorAll('input[name="scratchMode"]').forEach(r => r.addEventListener("change", updateScratchFieldGates));
["scratchServer", "scratchAuth"].forEach(id =>
  document.getElementById(id).addEventListener("input", updateScratchFieldGates));
document.getElementById("scratchAuth").addEventListener("change", updateScratchFieldGates);
document.getElementById("scratchTestBtn").addEventListener("click", testScratchSettings);
document.getElementById("scratchSaveBtn").addEventListener("click", saveScratchSettings);
```

Remove the stray unicode `✓` if the project avoids non-ASCII in UI strings
(`rg -n "✓" static/app.js` — if there are none elsewhere, replace with the word "OK").

### Step 6.4 — Load settings when the tab opens

In `switchTool(tool)` (app.js ~line 1674), after the line
`if (tool === "drift") syncDriftFromRun();` add:

```javascript
  if (tool === "settings") loadScratchSettings();
```

`loadScratchSettings` is defined later in the file; that is fine because `switchTool`
only calls it on click, after the whole script has run.

### Step 6.5 — Tab-bar side effect check

`switchTool` adds class `rail-hidden-on-trimmer` to `#appShell` for every tool. Open the
Settings tab and confirm the layout looks like the Trimmer tab (no broken sidebar). If
the run-list rail appears and looks wrong, mirror whatever the Trimmer tab does.

---

## Phase 7: Docs and examples

1. `README.md`, Windows section "Where `.bak` files are restored": replace the `.env`
   instructions with: open **Settings**, choose **SQL Server**, fill Server / Port /
   Authentication, click **Test connection** (it must say "can restore"), click **Save**.
   Keep the `.env` variables as the alternative and state that they override the page.
   Add `DRIFT_SCRATCH_AUTH=windows` to the env table ("Windows only; leave USER/PASSWORD empty").
   Add a note: for Windows auth the Windows user running DriftTool.exe needs `dbcreator`
   or `sysadmin` on the instance, and the SQL Server service account (not the user) must
   be able to read the `.bak` file.
2. `.env.example`: add `# DRIFT_SCRATCH_AUTH=sql   # or windows (Windows only)`.
3. If Phase 3B was done: README requirements table gains
   "**ODBC Driver 18 for SQL Server** (only for Windows authentication)".

---

## Phase 8: Manual verification (must be done, in this order)

### On Linux

1. `python3.13 -m pytest -q` → all pass.
2. `python3.13 app.py`, open `http://127.0.0.1:5057`, click **Settings**:
   - Page shows "Docker container" selected, "Using Docker (nothing saved yet)."
   - "Windows authentication" option is disabled with "(Windows only)".
   - Click **Test connection** with Docker selected → "Docker scratch container is running".
3. Choose SQL Server, server `127.0.0.1`, port `14330`, SQL login `sa`, password = output of
   `docker exec drift-tool-mssql printenv MSSQL_SA_PASSWORD` → **Test** says "Connected as sa … can restore" → **Save**.
4. Reload the page → values persist, password field empty with "saved (leave blank to keep)".
   `curl -s localhost:5057/api/scratch/settings` → no `password` key.
5. Run a small `.bak` compare → run log shows `using local SQL Server 127.0.0.1,14330 for restores (no Docker)`.
   (The `.bak` path must exist inside that server too; for this Linux test copy it into the
   container at the same path first, as done in the verification of commit 18d90cc.)
6. Switch back to Docker, Save → next compare log shows `scratch SQL Server already running (container drift-tool-mssql)`.
7. Start a compare and, while it runs, click Save → error "a compare or rehearse is running".
8. `./build.sh` then run `dist/DriftTool/DriftTool` → Settings page works the same.
9. Delete `work/scratch_server.json` when done so Linux is back to its default.

### On Windows (the real target)

1. `git pull`, `build-windows.bat`, run `dist\DriftTool\DriftTool.exe`.
2. Settings → SQL Server, server `localhost` (or `localhost\SQLEXPRESS`), auth **Windows
   authentication** → **Test** → must show `Connected as MACHINE\user` and "can restore".
   If it shows the dbcreator/sysadmin warning, grant the role in SSMS
   (Security > Logins > the Windows user > Server Roles > dbcreator) and test again.
3. **Save**, then run a real `.bak` compare (both directions). It must finish with the same
   counts as on Linux for the same backup pair
   (reference: 105 `olives_bo.bak` vs morec `Olives_BO.bak` → client_to_105 344/64/446,
   105_to_client 344/447/63).
4. Repeat step 2-3 with **SQL Server login** to confirm both auth types.
5. Close and reopen the exe → Settings still saved; a compare works without re-entering anything.

---

## Phase 9: Commit

One commit, message:

```
Add Settings page for the scratch SQL Server (Windows auth supported).

Pick Docker or a SQL Server by host/IP, port, SQL login or Windows
authentication; Test connection reports login, version and whether the
login can RESTORE. Saved in work/scratch_server.json (password never sent
back to the browser); DRIFT_SCRATCH_* env vars still override. Saving is
refused while a compare or rehearse is running.
```

Push to `main`.

---

## Out of scope (do NOT do in this plan)

- Windows authentication for the **live** Master/Client forms on SQL Compare > Schema.
  That is a separate change (it touches `livescan.connect`, `_sql_connect`, the apply
  session, and data copy). Plan it separately after this ships.
- Encrypting the saved password (Windows DPAPI). The file lives in the gitignored `work/`
  folder next to `work/.mssql_pw`, same protection level as today.
- Mapping local `.bak` paths to paths on a remote server. The page warns instead.
