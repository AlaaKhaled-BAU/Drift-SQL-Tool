"""Paths, container, and tool locations. Single source of truth."""
import os
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # drift-tool install root
# Monorepo: olives/apps/drift-tool → search .bak from repo root. Standalone git root → ROOT.
REPO_ROOT = ROOT.parent.parent if not (ROOT / ".git").is_dir() else ROOT
WORK_DIR = ROOT / "work"
OUTPUT_DIR = WORK_DIR / "output"
EXCLUDE_FILE = ROOT / "exclude-from-drift.txt"

WORK_DIR.mkdir(exist_ok=True)
OUTPUT_DIR.mkdir(exist_ok=True)

# --- scratch SQL Server container ---
CONTAINER_NAME = "drift-tool-mssql"
CONTAINER_IMAGE = "mcr.microsoft.com/mssql/server:2022-latest"
HOST_PORT = 14330
SA_USER = "sa"


def _sa_password() -> str:
    """Scratch-container SA password. Set DRIFT_MSSQL_SA_PASSWORD in the environment
    (desktop launcher, shell profile, or systemd). If unset, a one-time random
    password is used for this process only — existing containers created with a
    different password will not connect until you set the matching env var or
    remove the container: docker rm -f drift-tool-mssql."""
    env = os.environ.get("DRIFT_MSSQL_SA_PASSWORD", "").strip()
    if env:
        return env
    return secrets.token_urlsafe(18) + "aA1!"


SA_PASSWORD = _sa_password()

# Legacy read-only bind mount for the scratch container (optional; .bak files are
# staged with docker cp instead of requiring a host path under this root).
HOST_MOUNT_SRC = str(WORK_DIR)
CONTAINER_MOUNT_DST = "/host"
BACKUP_BROWSE_ROOT = WORK_DIR

# --- sqlpackage (installed as a dotnet tool; needs a matching runtime side-by-side) ---
SQLPACKAGE_BIN = os.path.expanduser("~/.dotnet/tools/sqlpackage")
DOTNET_ROOT_FOR_SQLPACKAGE = os.path.expanduser("~/.dotnet-8027")

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
    env["PATH"] = f"{DOTNET_ROOT_FOR_SQLPACKAGE}:{env.get('PATH', '')}"
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
