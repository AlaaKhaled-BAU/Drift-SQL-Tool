"""Scratch SQL Server settings (file + env). No live server: connections are mocked."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from drift import config, docker_mgmt, extract, restore

_ENV_KEYS = (
    "DRIFT_SCRATCH_SERVER", "DRIFT_SCRATCH_PORT", "DRIFT_SCRATCH_USER",
    "DRIFT_SCRATCH_PASSWORD", "DRIFT_SCRATCH_AUTH",
)


def _clear_scratch_env():
    return patch.dict("os.environ", {k: "" for k in _ENV_KEYS}, clear=False)


def _temp_settings():
    path = Path(tempfile.mkdtemp()) / "scratch_server.json"
    return patch.object(config, "SCRATCH_SETTINGS_FILE", path), path


def _write_settings(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


class ScratchSettings(unittest.TestCase):
    def test_no_file_no_env_is_docker(self):
        p, path = _temp_settings()
        with p, _clear_scratch_env():
            self.assertFalse(path.exists())
            s = config.scratch_settings()
            self.assertEqual(s["mode"], "docker")
            kw = config.scratch_connect_kwargs()
            self.assertEqual((kw["server"], kw["port"], kw["user"]), ("127.0.0.1", config.HOST_PORT, "sa"))
            self.assertEqual(kw["password"], config.SA_PASSWORD)

    def test_corrupt_file_falls_back_to_docker(self):
        p, path = _temp_settings()
        path.write_text("{not json", encoding="utf-8")
        with p, _clear_scratch_env():
            s = config.scratch_settings()
            self.assertEqual(s["mode"], "docker")

    def test_file_sql_login(self):
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "dbhost", "port": 1444,
            "auth": "sql", "user": "drift", "password": "pw",
        })
        with p, _clear_scratch_env():
            kw = config.scratch_connect_kwargs()
            self.assertEqual(kw, {"server": "dbhost", "port": 1444, "user": "drift", "password": "pw"})

    def test_file_named_instance_has_no_port(self):
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": r"localhost\SQLEXPRESS", "port": 1433,
            "auth": "sql", "user": "u", "password": "p",
        })
        with p, _clear_scratch_env():
            kw = config.scratch_connect_kwargs()
            self.assertNotIn("port", kw)
            self.assertEqual(config.scratch_sqlpackage_server(), r"localhost\SQLEXPRESS")
            self.assertNotIn(",", config.scratch_sqlpackage_server())

    def test_windows_auth_kwargs_have_no_credentials(self):
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "localhost", "port": 1433,
            "auth": "windows", "user": "", "password": "",
        })
        with p, _clear_scratch_env():
            kw = config.scratch_connect_kwargs()
            self.assertNotIn("user", kw)
            self.assertNotIn("password", kw)

    def test_dot_and_local_normalize_to_localhost(self):
        p, path = _temp_settings()
        _write_settings(path, {"mode": "local", "server": ".", "port": 1433, "auth": "sql", "user": "u", "password": "p"})
        with p, _clear_scratch_env():
            self.assertEqual(config.scratch_settings()["server"], "localhost")
        _write_settings(path, {
            "mode": "local", "server": r"(local)\SQLEXPRESS", "port": 1433,
            "auth": "sql", "user": "u", "password": "p",
        })
        with p, _clear_scratch_env():
            self.assertEqual(config.scratch_settings()["server"], r"localhost\SQLEXPRESS")

    def test_env_overrides_file(self):
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "A", "port": 1433,
            "auth": "sql", "user": "u", "password": "p",
        })
        with p, patch.dict("os.environ", {"DRIFT_SCRATCH_SERVER": "B"}, clear=False):
            s = config.scratch_settings()
            self.assertEqual(s["server"], "B")
            self.assertEqual(s["source"], "env")

    def test_save_blank_password_keeps_saved(self):
        p, path = _temp_settings()
        with p, _clear_scratch_env():
            config.save_scratch_settings({
                "mode": "local", "server": "h", "port": 1433,
                "auth": "sql", "user": "drift", "password": "secret1",
            })
            config.save_scratch_settings({
                "mode": "local", "server": "h", "port": 1433,
                "auth": "sql", "user": "drift", "password": "",
            })
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(data["password"], "secret1")

    def test_save_rejects_windows_auth_on_linux(self):
        p, path = _temp_settings()
        with p, _clear_scratch_env(), patch("drift.config.os.name", "posix"):
            with self.assertRaises(ValueError):
                config.save_scratch_settings({
                    "mode": "local", "server": "localhost", "port": 1433, "auth": "windows",
                })

    def test_save_validates_port_and_server(self):
        p, path = _temp_settings()
        with p, _clear_scratch_env():
            with self.assertRaises(ValueError):
                config.save_scratch_settings({
                    "mode": "local", "server": "h", "port": 0, "auth": "sql", "user": "u", "password": "p",
                })
            with self.assertRaises(ValueError):
                config.save_scratch_settings({
                    "mode": "local", "server": "h", "port": "abc", "auth": "sql", "user": "u", "password": "p",
                })
            with self.assertRaises(ValueError):
                config.save_scratch_settings({
                    "mode": "local", "server": "", "port": 1433, "auth": "sql", "user": "u", "password": "p",
                })

    def test_extract_uses_trusted_connection_for_windows_auth(self):
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "localhost", "port": 1433,
            "auth": "windows", "user": "", "password": "",
        })
        with p, _clear_scratch_env(), patch("drift.extract.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0)
            extract.extract_dacpac("db1", "/tmp/out.dacpac", lambda m: None)
        argv = run.call_args[0][0]
        self.assertIn("/SourceTrustedConnection:True", argv)
        self.assertFalse(any(a.startswith("/SourceUser:") for a in argv))
        self.assertFalse(any(str(a).startswith("@") for a in argv))

    def test_extract_sql_login_uses_password_file(self):
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "localhost", "port": 1433,
            "auth": "sql", "user": "drift", "password": "sekrit",
        })
        with p, _clear_scratch_env(), patch("drift.extract.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0)
            extract.extract_dacpac("db1", "/tmp/out.dacpac", lambda m: None)
        argv = run.call_args[0][0]
        self.assertTrue(any(a == "/SourceUser:drift" for a in argv))
        rsp_args = [a for a in argv if str(a).startswith("@") and str(a).endswith(".rsp")]
        self.assertEqual(len(rsp_args), 1)
        joined = " ".join(str(a) for a in argv)
        self.assertNotIn("sekrit", joined)


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
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "localhost", "port": 1433,
            "auth": "sql", "user": "drift", "password": "pw",
        })
        with p, _clear_scratch_env(), patch("drift.restore.scratch_connect", return_value=conn), \
                patch("drift.restore.subprocess.run") as run:
            restore.restore_backup(Path("/backups/client.bak"), "drift_client_1", lambda m: None)
        run.assert_not_called()
        restore_sql = next(s for s in executed if s.startswith("RESTORE DATABASE"))
        self.assertIn(str(Path("/backups/client.bak").resolve()), restore_sql)
        self.assertIn("C:\\SQLData\\drift_client_1__Olives_BO.mdf", restore_sql)
        self.assertIn("C:\\SQLData\\drift_client_1__Olives_BO_log.ldf", restore_sql)

    def test_local_ensure_running_never_calls_docker_or_trace_flags(self):
        conn = MagicMock()
        p, path = _temp_settings()
        _write_settings(path, {
            "mode": "local", "server": "localhost", "port": 1433,
            "auth": "sql", "user": "drift", "password": "pw",
        })
        with p, _clear_scratch_env(), patch("drift.restore.scratch_connect", return_value=conn), \
                patch("drift.docker_mgmt._run") as run:
            docker_mgmt.ensure_running(lambda m: None)
        run.assert_not_called()
        conn.cursor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
