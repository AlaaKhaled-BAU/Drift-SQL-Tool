"""Scratch SQL Server selection: Docker container by default, local instance when
DRIFT_SCRATCH_SERVER is set. No live server needed: pymssql/docker are faked."""
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from drift import config, docker_mgmt, restore


def _local(server="localhost", port=1433, user="drift", password="pw"):
    return patch.multiple(config, SCRATCH_SERVER=server, USE_DOCKER=False,
                          SCRATCH_PORT=port, SCRATCH_USER=user), \
        patch.dict("os.environ", {"DRIFT_SCRATCH_PASSWORD": password})


class ConnectKwargs(unittest.TestCase):
    def test_docker_default_targets_container_port(self):
        with patch.multiple(config, USE_DOCKER=True, SCRATCH_SERVER="", SCRATCH_USER="sa"):
            kw = config.scratch_connect_kwargs()
        self.assertEqual((kw["server"], kw["port"], kw["user"]), ("127.0.0.1", config.HOST_PORT, "sa"))
        self.assertEqual(kw["password"], config.SA_PASSWORD)

    def test_local_host_and_port(self):
        a, b = _local("localhost", 1444)
        with a, b:
            kw = config.scratch_connect_kwargs()
            self.assertEqual(config.scratch_sqlpackage_server(), "localhost,1444")
        self.assertEqual((kw["server"], kw["port"], kw["user"], kw["password"]),
                         ("localhost", 1444, "drift", "pw"))

    def test_named_instance_has_no_port(self):
        a, b = _local("localhost\\SQLEXPRESS")
        with a, b:
            kw = config.scratch_connect_kwargs()
            self.assertEqual(config.scratch_sqlpackage_server(), "localhost\\SQLEXPRESS")
        self.assertNotIn("port", kw)


class LocalRestore(unittest.TestCase):
    def _fake_cursor(self, data_dir):
        cur = MagicMock()
        executed = []
        cur.execute.side_effect = lambda sql, *a: executed.append(sql)
        cur.fetchone.side_effect = [
            {"data_dir": data_dir, "log_dir": data_dir},
            {"BackupStartDate": "2026-01-01", "SoftwareVersionMajor": 16},
        ]
        cur.fetchall.return_value = [
            {"LogicalName": "Olives_BO", "Type": "D"},
            {"LogicalName": "Olives_BO_log", "Type": "L"},
        ]
        return cur, executed

    def test_local_restore_reads_file_in_place_and_uses_instance_dirs(self):
        cur, executed = self._fake_cursor("C:\\SQLData")
        conn = MagicMock()
        conn.cursor.return_value = cur
        a, b = _local()
        with a, b, patch("drift.restore.pymssql.connect", return_value=conn), \
                patch("drift.restore.subprocess.run") as run:
            restore.restore_backup(Path("/backups/client.bak"), "drift_client_1", lambda m: None)
        run.assert_not_called()  # no docker cp
        restore_sql = next(s for s in executed if s.startswith("RESTORE DATABASE"))
        self.assertIn(str(Path("/backups/client.bak").resolve()), restore_sql)
        self.assertIn("C:\\SQLData\\drift_client_1__Olives_BO.mdf", restore_sql)
        self.assertIn("C:\\SQLData\\drift_client_1__Olives_BO_log.ldf", restore_sql)

    def test_local_ensure_running_never_calls_docker_or_trace_flags(self):
        conn = MagicMock()
        a, b = _local()
        with a, b, patch("drift.docker_mgmt.pymssql.connect", return_value=conn), \
                patch("drift.docker_mgmt._run") as run:
            docker_mgmt.ensure_running(lambda m: None)
        run.assert_not_called()
        conn.cursor.assert_not_called()  # no DBCC TRACEON on the user's server


if __name__ == "__main__":
    unittest.main()
