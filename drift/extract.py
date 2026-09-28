"""Live DB -> .dacpac (schema-only, parsed object model) via sqlpackage Extract."""
import os
import subprocess
import tempfile
from pathlib import Path

from . import config


def _run_extract(cmd, database_label: str, log, out_path) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       timeout=600, env=config.sqlpackage_env(), **config.NO_WINDOW)
    if r.returncode != 0:
        raise RuntimeError(
            f"sqlpackage Extract failed for [{database_label}]:\n{r.stdout[-1500:]}\n{r.stderr[-1500:]}"
        )
    log(f"  extracted {Path(out_path).name}")
    return str(out_path)


def _extract_with_password(cmd, password: str, database_label: str, log, out_path) -> str:
    """Keep /SourcePassword off argv (visible in ps); pass it via a 0600 response file."""
    fd, rsp = tempfile.mkstemp(prefix="sqlpackage-", suffix=".rsp")
    try:
        if hasattr(os, "fchmod"):
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(f"/SourcePassword:{password}\n")
        return _run_extract(list(cmd) + [f"@{rsp}"], database_label, log, out_path)
    finally:
        try:
            os.unlink(rsp)
        except OSError:
            pass


def extract_dacpac_source(source: dict, out_path, log) -> str:
    """Extract schema from a caller-supplied SQL Server (live target)."""
    server = source["server"]
    port = int(source.get("port") or 1433)
    database = source["database"]
    log(f"extracting schema of [{database}] from {server},{port} to {Path(out_path).name}...")
    cmd = [
        config.SQLPACKAGE_BIN,
        "/Action:Extract",
        f"/SourceServerName:{server},{port}",
        f"/SourceDatabaseName:{database}",
        f"/SourceUser:{source['user']}",
        "/SourceTrustServerCertificate:True",
        f"/TargetFile:{out_path}",
        "/p:ExtractAllTableData=false",
        "/p:VerifyExtraction=false",
    ]
    return _extract_with_password(cmd, source["password"], database, log, out_path)


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
