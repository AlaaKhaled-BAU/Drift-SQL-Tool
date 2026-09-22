"""Bring up the scratch SQL Server container used for every restore."""
import subprocess
import time
from pathlib import Path

import pymssql

from . import config


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def _container_state():
    r = _run(["docker", "inspect", "-f", "{{.State.Status}}", config.CONTAINER_NAME])
    return r.stdout.strip() if r.returncode == 0 else None


def _current_mount_source():
    """The host path actually bind-mounted at CONTAINER_MOUNT_DST right now, or
    None if the container doesn't exist. Docker mounts are fixed at container
    creation -- changing config.HOST_MOUNT_SRC (e.g. widening the backup-browse
    root) has no effect on an already-running container until it's recreated."""
    r = _run([
        "docker", "inspect", "-f",
        "{{range .Mounts}}{{if eq .Destination \"" + config.CONTAINER_MOUNT_DST + "\"}}{{.Source}}{{end}}{{end}}",
        config.CONTAINER_NAME,
    ])
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def ensure_running(log):
    state = _container_state()
    mounted = _current_mount_source()
    # Path() comparison normalizes trailing slashes / symlink-free equivalence.
    if state is not None and mounted is not None and Path(mounted) != Path(config.HOST_MOUNT_SRC):
        log(f"container's mount ({mounted}) no longer matches configured browse root "
            f"({config.HOST_MOUNT_SRC}) -- recreating container (scratch DBs only, nothing lost)")
        _run(["docker", "rm", "-f", config.CONTAINER_NAME])
        state = None

    if state == "running":
        log(f"scratch SQL Server already running (container {config.CONTAINER_NAME})")
    elif state is not None:
        log(f"container exists but state={state}, starting it")
        _run(["docker", "start", config.CONTAINER_NAME])
    else:
        log(f"creating scratch SQL Server container from {config.CONTAINER_IMAGE} "
            f"(mount: {config.HOST_MOUNT_SRC} -> {config.CONTAINER_MOUNT_DST})")
        _run([
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
            "-v", f"{config.HOST_MOUNT_SRC}:{config.CONTAINER_MOUNT_DST}:ro",
            config.CONTAINER_IMAGE,
        ])
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
