"""Bring up the scratch SQL Server container used for every restore."""
import os
import subprocess
import time

import pymssql

from . import config


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def _container_state():
    r = _run(["docker", "inspect", "-f", "{{.State.Status}}", config.CONTAINER_NAME])
    return r.stdout.strip() if r.returncode == 0 else None


def _adopt_container_password(log):
    """An existing container keeps the SA password it was created with. If that is not
    ours (password file lost, or created by an older build), use and save the container's."""
    r = _run(["docker", "inspect", "-f", "{{range .Config.Env}}{{println .}}{{end}}", config.CONTAINER_NAME])
    for line in r.stdout.splitlines():
        if line.startswith("MSSQL_SA_PASSWORD="):
            pw = line.split("=", 1)[1]
            if pw and pw != config.SA_PASSWORD:
                log("using the SA password the existing scratch container was created with")
                config.SA_PASSWORD = pw
                if not os.environ.get("DRIFT_MSSQL_SA_PASSWORD", "").strip():
                    config.SA_PASSWORD_FILE.write_text(pw, encoding="utf-8")
            return


def ensure_running(log):
    try:
        state = _container_state()
    except FileNotFoundError:
        raise RuntimeError("docker is not installed or not on PATH") from None
    if state is not None:
        _adopt_container_password(log)

    r = None
    if state == "running":
        log(f"scratch SQL Server already running (container {config.CONTAINER_NAME})")
    elif state is not None:
        log(f"container exists but state={state}, starting it")
        r = _run(["docker", "start", config.CONTAINER_NAME])
    else:
        log(f"creating scratch SQL Server container from {config.CONTAINER_IMAGE}")
        r = _run([
            "docker", "run", "-d", "--name", config.CONTAINER_NAME,
            "-e", "ACCEPT_EULA=Y",
            "-e", f"MSSQL_SA_PASSWORD={config.SA_PASSWORD}",
            "-e", "MSSQL_PID=Developer",
            "-e", "MSSQL_MEMORY_LIMIT_MB=4096",
            # SQL Server on Linux sizes its worker/parallel-redo thread pools off the
            # CPU count it *sees* via /proc/cpuinfo at startup. `--cpus` only throttles
            # CPU *time* (CFS quota) -- it does NOT change the visible core count, so
            # the engine still spins up threads for all host cores while getting a
            # fraction of the scheduling time, which stalls PARALLEL REDO forever on
            # DISPATCHER_QUEUE_SEMAPHORE during RESTORE. `--cpuset-cpus` actually
            # restricts the visible core count (cgroup cpuset, not cfs_quota), so the
            # engine sizes its thread pools to match what it's really given.
            "--cpuset-cpus", "0,1",
            "-p", f"{config.HOST_PORT}:1433",
            config.CONTAINER_IMAGE,
        ])
    if r is not None and r.returncode != 0:
        raise RuntimeError(f"docker failed (is Docker running?):\n{r.stderr[-1500:]}")
    _wait_for_sql(log)
    _disable_parallel_redo(log)


def _wait_for_sql(log, timeout=90):
    log("waiting for SQL Server to accept connections...")
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            conn = pymssql.connect(
                server="127.0.0.1", port=config.HOST_PORT,
                user=config.SA_USER, password=config.SA_PASSWORD,
                timeout=5, login_timeout=5,
            )
            conn.close()
            log("SQL Server is up.")
            return
        except Exception as e:  # noqa: BLE001 - polling until ready
            last_err = e
            time.sleep(2)
    raise RuntimeError(f"SQL Server did not become ready in {timeout}s: {last_err}")


def _disable_parallel_redo(log):
    """SQL Server on Linux has a known hang (PARALLEL REDO TASK stuck forever on
    DISPATCHER_QUEUE_SEMAPHORE) during RESTORE's crash-recovery phase in constrained/
    virtualized environments -- reproduced here even after pinning visible CPUs via
    cpuset. Microsoft's documented workaround is trace flag 3459, which forces
    single-threaded (serial) redo. Global scope, set once, applies to every
    RESTORE for the life of the container."""
    conn = pymssql.connect(
        server="127.0.0.1", port=config.HOST_PORT,
        user=config.SA_USER, password=config.SA_PASSWORD,
        autocommit=True, timeout=15, login_timeout=10,
    )
    cur = conn.cursor()
    cur.execute("DBCC TRACEON(3459, -1);")
    conn.close()
    log("parallel redo disabled (trace flag 3459) -- works around a known SQL-Server-on-Linux hang during RESTORE")
