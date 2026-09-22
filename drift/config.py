"""Paths, container, and tool locations. Single source of truth."""
import os
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # apps/drift-tool/
REPO_ROOT = ROOT.parent.parent                           # olives/
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
_PW_FILE = WORK_DIR / ".mssql_pw"
if not _PW_FILE.exists():
    _PW_FILE.write_text(secrets.token_urlsafe(18) + "aA1!")
SA_PASSWORD = _PW_FILE.read_text().strip()

# Broad root mounted read-only into the container so RESTORE FROM DISK can see
# any .bak the user picks via the device browser, not just ones already inside
# the repo. Must be an ancestor of (or equal to) REPO_ROOT. Changing this value
# requires the scratch container to be recreated with the new mount -- handled
# automatically by docker_mgmt.ensure_running() (detects the mismatch, recreates).
BACKUP_BROWSE_ROOT = Path("/media/alaa/data")
HOST_MOUNT_SRC = str(BACKUP_BROWSE_ROOT)
CONTAINER_MOUNT_DST = "/host"

# --- sqlpackage (installed as a dotnet tool; needs a matching runtime side-by-side) ---
SQLPACKAGE_BIN = os.path.expanduser("~/.dotnet/tools/sqlpackage")
DOTNET_ROOT_FOR_SQLPACKAGE = os.path.expanduser("~/.dotnet-8027")

# --- python + mssql-scripter interpreter (packages live under python3.13 user site, not python3) ---
PYTHON_BIN = "python3.13"

# SqlPackage DeployReport/Script comparison profile — pinned per PLAN-03 §5.
# Formatting never counts as drift; permissions/extended-properties/role-membership
# default in some SqlPackage versions to being IGNORED, which would hide real drift,
# so they are explicitly turned back on here.
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
    # Real client databases have DB users mapped to server-level SQL logins (auth
    # accounts for that client's own apps/integrations). SqlPackage can't resolve
    # those logins' SIDs from a single-database extract and refuses to generate
    # ANY report at all (SQL74502) if they're in scope. Who has a login is an
    # access-provisioning concern, not the proc/table/permission drift this tool
    # targets, so user accounts are out of scope by design, not by accident.
    "/p:ExcludeObjectTypes=Users",
]


def sqlpackage_env():
    env = os.environ.copy()
    env["DOTNET_ROOT"] = DOTNET_ROOT_FOR_SQLPACKAGE
    env["PATH"] = f"{DOTNET_ROOT_FOR_SQLPACKAGE}:{env.get('PATH', '')}"
    return env


# --- AI triage (OpenRouter) -- advisory-only, never in the detection path.
# Key lives outside the repo tree's git history (work/ is gitignored) and is
# loaded server-side only; the browser never sees it.
_OPENROUTER_KEY_FILE = WORK_DIR / ".openrouter_key"
OPENROUTER_BASE = "https://openrouter.ai/api/v1"
# Zero-cost model, chosen deliberately (account is free-tier/no credits at
# setup time). Live-validated to answer chat/completions; JSON-mode strictness
# not guaranteed on free models, so drift/ai.py parses defensively regardless.
OPENROUTER_MODEL = "qwen/qwen3-coder:free"


def openrouter_key() -> str | None:
    if not _OPENROUTER_KEY_FILE.exists():
        return None
    key = _OPENROUTER_KEY_FILE.read_text().strip()
    return key or None


# --- AI merge proposal (DeepSeek, direct API -- NOT via OpenRouter/LiteLLM,
# and NOT the sibling client-chatbot project's key file -- drift-tool must
# not depend on another project's .env at runtime). Same gitignored-work-dir
# convention as _OPENROUTER_KEY_FILE; the value is copied in once from
# client-chatbot/gateway/.env's DEEPSEEK_KEY (a manual, non-code setup step).
_DEEPSEEK_KEY_FILE = WORK_DIR / ".deepseek_key"
DEEPSEEK_BASE = "https://api.deepseek.com"
DEEPSEEK_MODEL = "deepseek-chat"


def deepseek_key() -> str | None:
    if not _DEEPSEEK_KEY_FILE.exists():
        return None
    key = _DEEPSEEK_KEY_FILE.read_text().strip()
    return key or None
