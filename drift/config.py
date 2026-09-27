"""Paths, container, and tool locations. Single source of truth."""
import json
import os
import secrets
import shutil
import sys
from pathlib import Path

if getattr(sys, "frozen", False):
    # PyInstaller: data lives beside the exe, not in the temp extract.
    ROOT = Path(sys.executable).resolve().parent
else:
    ROOT = Path(__file__).resolve().parent.parent          # drift-tool install root

def _load_dotenv(path: Path) -> None:
    """KEY=VALUE lines from .env beside the app; real environment variables win."""
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.removeprefix("export ").partition("=")
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        os.environ.setdefault(key, value)


_load_dotenv(ROOT / ".env")

WORK_DIR = ROOT / "work"
OUTPUT_DIR = WORK_DIR / "output"
EXCLUDE_FILE = ROOT / "exclude-from-drift.txt"
if not EXCLUDE_FILE.exists() and hasattr(sys, "_MEIPASS"):
    EXCLUDE_FILE = Path(sys._MEIPASS) / "exclude-from-drift.txt"

WORK_DIR.mkdir(exist_ok=True)
OUTPUT_DIR.mkdir(exist_ok=True)

# --- scratch SQL Server container ---
CONTAINER_NAME = "drift-tool-mssql"
CONTAINER_IMAGE = "mcr.microsoft.com/mssql/server:2022-latest"
HOST_PORT = 14330
SA_USER = "sa"


def _sa_password() -> str:
    """Scratch-container SA password: DRIFT_MSSQL_SA_PASSWORD if set, else a random
    one generated once and kept in SA_PASSWORD_FILE so the container created on
    the first run still accepts it after a restart."""
    env = os.environ.get("DRIFT_MSSQL_SA_PASSWORD", "").strip()
    if env:
        return env
    try:
        saved = SA_PASSWORD_FILE.read_text(encoding="utf-8").strip()
        if saved:
            return saved
    except OSError:
        pass
    pw = secrets.token_urlsafe(18) + "aA1!"
    SA_PASSWORD_FILE.write_text(pw, encoding="utf-8")
    return pw


SA_PASSWORD_FILE = WORK_DIR / ".mssql_pw"


SA_PASSWORD = _sa_password()

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


def _port(value, default: int = 1433) -> int:
    """A bad port must not stop the app from starting."""
    if value is None or value == "":
        return default
    try:
        port = int(value)
    except (TypeError, ValueError):
        print(f"[settings] ignoring invalid port {value!r}; using {default}")
        return default
    if not 1 <= port <= 65535:
        print(f"[settings] ignoring port {port} outside 1-65535; using {default}")
        return default
    return port


def scratch_settings() -> dict:
    """Current scratch-server settings, read fresh on every call (cheap: one small file)."""
    if scratch_env_locked():
        server = os.environ.get("DRIFT_SCRATCH_SERVER", "").strip()
        return {
            "mode": "local" if server else "docker",
            "server": _normalize_server(server),
            "port": _port(os.environ.get("DRIFT_SCRATCH_PORT", "").strip()),
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
        "port": _port(data.get("port")),
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
        raw_port = new.get("port")
        if raw_port is None or raw_port == "":
            port = 1433
        else:
            try:
                port = int(raw_port)
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

# .bak files are staged into the container with `docker cp`; no bind mount.
BACKUP_BROWSE_ROOT = WORK_DIR

def _sqlpackage_bin() -> str:
    """Same tool on Linux and Windows: env override, then the usual dotnet-tool locations."""
    override = os.environ.get("DRIFT_SQLPACKAGE", "").strip()
    if override:
        return override
    name = "sqlpackage.exe" if os.name == "nt" else "sqlpackage"
    tool = Path.home() / ".dotnet" / "tools" / name
    if tool.is_file():
        return str(tool)
    return shutil.which("sqlpackage") or str(tool)


def _dotnet_root() -> str:
    """The pinned side-by-side runtime wins, as before; otherwise DOTNET_ROOT or ~/.dotnet."""
    pinned = Path.home() / ".dotnet-8027"
    if pinned.is_dir():
        return str(pinned)
    override = os.environ.get("DOTNET_ROOT", "").strip()
    if override:
        return override
    return str(Path.home() / ".dotnet")


# --- sqlpackage (dotnet tool; needs a matching runtime side-by-side) ---
SQLPACKAGE_BIN = _sqlpackage_bin()
DOTNET_ROOT_FOR_SQLPACKAGE = _dotnet_root()

# --- python + mssql-scripter interpreter (packages live under python3.13 user site, not python3) ---
PYTHON_BIN = "python3.13"

# SqlPackage DeployReport/Script comparison profile.
COMPARE_PROFILE = [
    "/p:IgnoreWhitespace=true",
    "/p:IgnoreComments=true",
    "/p:IgnoreKeywordCasing=true",
    "/p:IgnoreSemicolonBetweenStatements=true",
    "/p:IgnorePermissions=false",
    "/p:IgnoreExtendedProperties=false",
    "/p:IgnoreRoleMembership=false",
    "/p:IgnoreColumnOrder=false",
    "/p:DropObjectsNotInSource=true",
    "/p:AllowIncompatiblePlatform=true",
    "/p:ExcludeObjectTypes=Users",
]


def sqlpackage_env():
    env = os.environ.copy()
    env["DOTNET_ROOT"] = DOTNET_ROOT_FOR_SQLPACKAGE
    env["PATH"] = os.pathsep.join(
        p for p in (DOTNET_ROOT_FOR_SQLPACKAGE, env.get("PATH", "")) if p
    )
    return env


# --- AI keys (env only; never committed, never sent to the browser) ---
OPENROUTER_BASE = "https://openrouter.ai/api/v1"
OPENROUTER_MODEL = "qwen/qwen3-coder:free"

DEEPSEEK_BASE = "https://api.deepseek.com"
DEEPSEEK_MODEL = "deepseek-chat"


def openrouter_key() -> str | None:
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    return key or None


def deepseek_key() -> str | None:
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    return key or None
