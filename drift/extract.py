"""Live DB -> .dacpac (schema-only, parsed object model) via sqlpackage Extract."""
import subprocess

from . import config


def extract_dacpac(db_name: str, out_path, log) -> str:
    log(f"extracting schema of [{db_name}] to {out_path.name}...")
    cmd = [
        config.SQLPACKAGE_BIN, "/Action:Extract",
        f"/SourceServerName:127.0.0.1,{config.HOST_PORT}",
        f"/SourceDatabaseName:{db_name}",
        f"/SourceUser:{config.SA_USER}",
        f"/SourcePassword:{config.SA_PASSWORD}",
        "/SourceTrustServerCertificate:True",  # scratch container uses a self-signed cert
        f"/TargetFile:{out_path}",
        "/p:ExtractAllTableData=false",
        "/p:VerifyExtraction=false",
    ]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=config.sqlpackage_env())
    if r.returncode != 0:
        raise RuntimeError(f"sqlpackage Extract failed for [{db_name}]:\n{r.stdout[-1500:]}\n{r.stderr[-1500:]}")
    log(f"  extracted {out_path.name}")
    return str(out_path)
