"""RESTORE a .bak into the scratch container as a live, queryable database."""
import threading
import time
from pathlib import Path

import pymssql

from . import config


def _connect(database=None, autocommit=True):
    return pymssql.connect(
        server="127.0.0.1", port=config.HOST_PORT,
        user=config.SA_USER, password=config.SA_PASSWORD,
        database=database, autocommit=autocommit, timeout=0, login_timeout=10,
    )


def host_path_to_container_path(host_path: Path) -> str:
    host_path = host_path.resolve()
    try:
        rel = host_path.relative_to(config.BACKUP_BROWSE_ROOT)
    except ValueError as e:
        raise ValueError(
            f"{host_path} is outside the mounted browse root, so the scratch container "
            f"can't see it (only {config.BACKUP_BROWSE_ROOT} is mounted in -- widen "
            f"BACKUP_BROWSE_ROOT in config.py to cover it)."
        ) from e
    return f"{config.CONTAINER_MOUNT_DST}/{rel.as_posix()}"


def _poll_restore_progress(db_name, log, stop_event):
    """RESTORE DATABASE blocks the connection running it, so track % via a second one."""
    try:
        conn = _connect()
        cur = conn.cursor(as_dict=True)
        while not stop_event.is_set():
            cur.execute(
                "SELECT percent_complete FROM sys.dm_exec_requests "
                "WHERE command IN ('RESTORE DATABASE','RESTORE') AND session_id <> @@SPID"
            )
            rows = cur.fetchall()
            if rows and rows[0]["percent_complete"]:
                log(f"  restoring {db_name}: {rows[0]['percent_complete']:.0f}%")
            time.sleep(3)
        conn.close()
    except Exception:  # noqa: BLE001 - progress reporting is best-effort
        pass


def restore_backup(bak_host_path: Path, db_name: str, log) -> dict:
    """Restore bak_host_path as db_name. Returns backup header info (version, date)."""
    container_path = host_path_to_container_path(bak_host_path)
    conn = _connect()
    cur = conn.cursor(as_dict=True)

    log(f"reading backup header: {bak_host_path.name}")
    cur.execute(f"RESTORE HEADERONLY FROM DISK = '{container_path}'")
    header = cur.fetchone()
    backup_date = header.get("BackupStartDate")
    sw_version = header.get("SoftwareVersionMajor")
    log(f"  backup taken {backup_date}, engine major version {sw_version}")

    cur.execute(f"RESTORE FILELISTONLY FROM DISK = '{container_path}'")
    files = cur.fetchall()

    move_clauses = []
    for f in files:
        logical = f["LogicalName"]
        is_log = f.get("Type") == "L"
        ext = "ldf" if is_log else "mdf"
        target = f"/var/opt/mssql/data/{db_name}__{logical}.{ext}"
        move_clauses.append(f"MOVE '{logical}' TO '{target}'")
    moves_sql = ", ".join(move_clauses)

    log(f"restoring {bak_host_path.name} -> database [{db_name}] ({len(files)} file(s))")
    stop_event = threading.Event()
    progress_thread = threading.Thread(
        target=_poll_restore_progress, args=(db_name, log, stop_event), daemon=True
    )
    progress_thread.start()
    client_error = None
    try:
        cur.execute(
            f"RESTORE DATABASE [{db_name}] FROM DISK = '{container_path}' "
            # STATS=5 forces SQL Server to push progress packets over the wire every
            # 5% instead of staying completely silent until the restore finishes --
            # without it a long restore looks identical to a dead connection to
            # anything on the network path enforcing an idle-socket timeout (this is
            # what reproduced restore.py's original client-timeout failure).
            f"WITH {moves_sql}, REPLACE, RECOVERY, STATS = 5"
        )
    except pymssql.OperationalError as e:
        client_error = e
    finally:
        stop_event.set()
        progress_thread.join(timeout=5)
    conn.close()

    if client_error is not None:
        # The client connection can drop mid-RESTORE (network blip, proxy idle-kill)
        # while the engine keeps working server-side. Don't fail the whole run on
        # that alone -- poll actual database state before giving up.
        log(f"  restore connection dropped ({client_error}); checking server-side state...")
        if not _wait_for_online(db_name, log):
            raise RuntimeError(
                f"RESTORE failed for {bak_host_path.name} -- connection dropped and "
                f"the database never reached ONLINE. If this is a version mismatch "
                f"(backup newer than the scratch server) or a corrupt/partial file, "
                f"the engine's own error is below:\n{client_error}"
            )
        log(f"  server confirms [{db_name}] finished restoring despite the dropped connection.")

    log(f"restored [{db_name}].")
    return {"backup_date": str(backup_date), "engine_major_version": sw_version}


def _wait_for_online(db_name: str, log, timeout=900) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            conn = _connect()
            cur = conn.cursor(as_dict=True)
            cur.execute("SELECT state_desc FROM sys.databases WHERE name = %s", (db_name,))
            row = cur.fetchone()
            conn.close()
            if row and row["state_desc"] == "ONLINE":
                return True
            if row:
                log(f"  [{db_name}] state={row['state_desc']}, still waiting...")
        except Exception as e:  # noqa: BLE001 - keep polling through transient errors
            log(f"  poll error (will retry): {e}")
        time.sleep(5)
    return False


def drop_database(db_name: str, log):
    try:
        conn = _connect()
        cur = conn.cursor()
        cur.execute(
            f"IF DB_ID('{db_name}') IS NOT NULL BEGIN "
            f"ALTER DATABASE [{db_name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
            f"DROP DATABASE [{db_name}]; END"
        )
        conn.close()
        log(f"dropped scratch database [{db_name}] (client data not left resident)")
    except Exception as e:  # noqa: BLE001 - best-effort teardown
        log(f"  warning: couldn't drop [{db_name}] cleanly: {e}")
