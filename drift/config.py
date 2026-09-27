"""Paths, container, and tool locations. Single source of truth."""
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
    one generated once and kept in work/.sa_password so the container created on
    the first run still accepts it after a restart."""
    env = os.environ.get("DRIFT_MSSQL_SA_PASSWORD", "").strip()
    if env:
        return env
    stored = WORK_DIR / ".sa_password"
    try:
        saved = stored.read_text(encoding="utf-8").strip()
        if saved:
            return saved
    except OSError:
        pass
    pw = secrets.token_urlsafe(18) + "aA1!"
    stored.write_text(pw, encoding="utf-8")
    return pw


SA_PASSWORD = _sa_password()

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
