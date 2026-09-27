# Olives DB Drift Tool

Desktop-first tool to compare Master (105) vs client SQL Server schemas, review drift, and assemble safe apply scripts.

## Windows

### Where `.bak` files are restored (Docker is not required)

A `.bak` is a backup image, not something the tool can diff directly. For every side you pick as a backup file, the tool restores it into a temporary database on a **scratch SQL Server**, then scripts it, builds `.dacpac` files with SqlPackage, compares, and drops the temporary databases. Rehearse restores the client `.bak` the same way.

On Windows, use the **SQL Server you already have on the machine** as the scratch server. Open **Settings** in the app, choose **SQL Server**, fill in **Server** / **Port** / **Authentication**, click **Test connection** (it should report that the login **can restore**), then click **Save**. Settings are stored in `work/scratch_server.json` beside the exe (password is never shown again in the UI).

Alternatively, put scratch settings in `.env` next to `DriftTool.exe` — those variables **override** the Settings page and show as read-only in the UI:

```ini
DRIFT_SCRATCH_SERVER=localhost
DRIFT_SCRATCH_USER=drift
DRIFT_SCRATCH_PASSWORD=your-password
```

- Named instance: `DRIFT_SCRATCH_SERVER=localhost\SQLEXPRESS` (the SQL Server Browser service must be running). Non-default port: add `DRIFT_SCRATCH_PORT=1433`.
- Use a **SQL login** (SQL Server and Windows Authentication mode) with the `dbcreator` role or `sysadmin`, so it can RESTORE and DROP. For **Windows authentication** (`DRIFT_SCRATCH_AUTH=windows`, leave `DRIFT_SCRATCH_USER` / `DRIFT_SCRATCH_PASSWORD` empty), the Windows user running `DriftTool.exe` needs `dbcreator` or `sysadmin` on the instance.
- The SQL Server **service account** must be able to read the `.bak` where it sits (the tool passes the file path to the server; nothing is copied). That applies to Windows authentication too: the login is your Windows user, but RESTORE still runs as the service account. Local disk folders normally work. For a network share, grant the service account access.
- Temporary databases are always named `drift_master_<id>`, `drift_client_<id>` or `zz_rehearsal_<id>` and are dropped afterwards, so your own databases are never replaced or removed. The tool does not change server settings.
- The instance must be the same or a newer SQL Server version than the one that made the backup.

**Docker instead (optional).** In **Settings**, choose **Docker container**, or leave scratch unset in `.env` and save nothing — the tool uses a Docker container (`drift-tool-mssql` on port 14330), as on Linux. Then Docker Desktop must be running.

**Live-only compares.** If both sides are live servers (no `.bak`), no scratch server is used at all.

### Requirements

| Requirement | Purpose |
|-------------|---------|
| **SQL Server** on the machine (Express, Developer or full) | Scratch server for restoring `.bak` files (or Docker Desktop instead) |
| **.NET SDK or runtime** | Runs `sqlpackage` (schema extract and compare) |
| **SqlPackage** | `dotnet tool install -g microsoft.sqlpackage` |
| **Python 3.12+** | Only to **build** the exe (`build-windows.bat`); running the built app does not need Python |
| **ODBC Driver 18 for SQL Server** | Only for **Windows authentication** to the scratch server (install with SSMS or [Microsoft download](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)) |
| **Git** (optional) | To clone/pull this repo |

Copy `.env.example` to `.env` next to `DriftTool.exe` (or `app.py`) and fill it in. See [Environment](#environment) below.

### Build and run (exe)

From the repo folder in **cmd** or **PowerShell**:

```bat
git pull
build-windows.bat
dist\DriftTool\DriftTool.exe
```

- Keep the entire `dist\DriftTool` folder together (do not move only the `.exe`).
- `work\` (run output) is created beside the exe; `.env` goes there too.
- The console shows `using local SQL Server … for restores (no Docker)` when a compare starts, confirming the local instance is used.
- Double-clicking the exe again while it is already running reopens the browser instead of starting a second server.

### Run from source on Windows (optional)

If you prefer not to use the exe:

```bat
py -3.12 -m venv venv
venv\Scripts\pip install -r requirements.txt
venv\Scripts\python app.py
```

Then open `http://127.0.0.1:5057` in your browser. Use **Choose .bak…** in the UI for backup paths.

## Linux

### Run (desktop)

```bash
./run-desktop.sh
```

Desktop shortcut (after clone):

```bash
INSTALL_ROOT="$(pwd)"
sed "s|@INSTALL_ROOT@|$INSTALL_ROOT|g" olives-drift-tool.desktop \
  > ~/.local/share/applications/olives-drift-tool.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

Requires: Docker (`drift-tool-mssql` scratch SQL Server), `sqlpackage` + .NET runtime (see `drift/config.py`), system PyGObject + WebKit2 (`python3-gi`, `gir1.2-webkit2-4.1`).

Build the same one-folder bundle as Windows:

```bash
./build.sh
dist/DriftTool/DriftTool
```

## Environment

| Variable | Purpose |
|----------|---------|
| `DRIFT_SCRATCH_SERVER` | Restore `.bak` files on this SQL Server instead of Docker (`localhost`, `localhost\SQLEXPRESS`, …) |
| `DRIFT_SCRATCH_PORT` | Port for `DRIFT_SCRATCH_SERVER` (default 1433; ignored for named instances) |
| `DRIFT_SCRATCH_USER` / `DRIFT_SCRATCH_PASSWORD` | SQL login for `DRIFT_SCRATCH_SERVER` (needs `dbcreator` or `sysadmin`) |
| `DRIFT_SCRATCH_AUTH` | `sql` (default) or `windows` (Windows only; leave USER/PASSWORD empty). Overrides Settings when any `DRIFT_SCRATCH_*` var is set |
| `DRIFT_MSSQL_SA_PASSWORD` | Docker mode only: SA password for the scratch container (optional; if unset, a password is generated once and stored in `work/.mssql_pw`). If you change it, recreate the container: `docker rm -f drift-tool-mssql` |
| `DRIFT_SQLPACKAGE` | Full path to `sqlpackage` / `sqlpackage.exe` if it is not under `%USERPROFILE%\.dotnet\tools` |
| `DEEPSEEK_API_KEY` | AI merge proposals (optional) |
| `OPENROUTER_API_KEY` | AI triage on findings (optional) |

Optional: copy `.env.example` to `.env` beside `app.py` or beside `DriftTool.exe`; it is loaded at startup and real environment variables take precedence.

## Browser mode (secondary)

```bash
./run.sh
```

Opens `http://localhost:5057` in the system browser (Linux).

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Tutorial](docs/TUTORIAL.md)

## Tests

```bash
python3.13 -m pytest -q
```
