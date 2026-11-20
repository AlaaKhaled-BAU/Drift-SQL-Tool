"""PARSEONLY the trimmed large Olives_BO procedure.

Reads OBJECT_DEFINITION through pymssql (Unicode nvarchar, not a varchar cast)
and asks SQL Server, inside the mssql container, to accept the trimmer batch
under SET PARSEONLY. Skips only when Docker, the mssql container, or Olives_BO
is not reachable. Does not execute the procedure and does not write to the
database.

The host temp file uses tempfile.gettempdir(). The sqlcmd input path below is
inside the Linux container, not a host path.
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pymssql  # noqa: E402

from drift.statements import _mask_literals_and_comments  # noqa: E402
from drift.trimmer import trim_procedure  # noqa: E402

_CONTAINER = "mssql"
_SQLCMD = "/opt/mssql-tools18/bin/sqlcmd"
_PROCEDURE = "dbo.OT_SendSalesmanData"
_CLIENT_ID = 62
# Inside the mssql container (always Linux). Not a host filesystem path.
_REMOTE_SQL = "/tmp/drift_parseonly.sql"


def _redact(text: str, password: str) -> str:
    if password and text:
        return text.replace(password, "[REDACTED]")
    return text or ""


def _require_container() -> None:
    try:
        proc = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Status}}", _CONTAINER],
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise unittest.SkipTest("Docker is not installed or not on PATH") from exc
    if proc.returncode != 0 or proc.stdout.strip() != "running":
        raise unittest.SkipTest(f"Docker container {_CONTAINER} is not running")


def _password() -> str:
    env = os.environ.get("DRIFT_RIGHT_PASSWORD")
    if env:
        return env
    try:
        out = subprocess.check_output(
            ["docker", "exec", _CONTAINER, "printenv", "MSSQL_SA_PASSWORD"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError as exc:
        raise unittest.SkipTest("Docker is not installed or not on PATH") from exc
    except subprocess.CalledProcessError as exc:
        raise unittest.SkipTest(
            f"Docker container {_CONTAINER} is not reachable"
        ) from exc
    password = out.strip()
    if not password:
        raise unittest.SkipTest(
            f"Docker container {_CONTAINER} has no MSSQL_SA_PASSWORD "
            "and DRIFT_RIGHT_PASSWORD is unset"
        )
    return password


def _connect(password: str, *, skip_if_down: bool):
    try:
        return pymssql.connect(
            server="127.0.0.1",
            port=1433,
            user="sa",
            password=password,
            database="Olives_BO",
            login_timeout=10,
            timeout=120,
        )
    except pymssql.Error as exc:
        message = "Olives_BO is not reachable: " + _redact(str(exc), password)
        if skip_if_down:
            raise unittest.SkipTest(message) from exc
        raise AssertionError(message) from exc


class OlivesCompileTests(unittest.TestCase):
    def test_ot_send_salesman_data_parses(self):
        _require_container()
        password = _password()
        conn = _connect(password, skip_if_down=True)
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT OBJECT_DEFINITION(OBJECT_ID(N'dbo.OT_SendSalesmanData')), "
                "CONVERT(varchar(30), modify_date, 126) "
                "FROM sys.objects "
                "WHERE object_id = OBJECT_ID(N'dbo.OT_SendSalesmanData')"
            )
            row = cur.fetchone()
            self.assertIsNotNone(row, f"{_PROCEDURE} is missing from Olives_BO")
            definition, before = row
            cur.execute(
                "SELECT COUNT(*) FROM dbo.ClientsActive WHERE ClientID = 62"
            )
            active = cur.fetchone()[0]
        finally:
            conn.close()

        self.assertIsInstance(definition, str)
        self.assertGreaterEqual(active, 1)
        self.assertGreater(len(definition), 800000)
        self.assertTrue(any("\u0600" <= ch <= "\u06ff" for ch in definition))

        result = trim_procedure(definition, _CLIENT_ID)
        self.assertTrue(result["ok"], result.get("reason"))
        trimmed = result["trimmed_sql"]
        self.assertIsInstance(trimmed, str)
        self.assertNotIn("CREATE PROCEDURE [dbo].[Unknown]", trimmed)
        self.assertNotIn("Unknown", trimmed)
        masked = _mask_literals_and_comments(trimmed)
        match = re.search(r"(?is)\bCREATE\s+PROCEDURE\b", masked)
        self.assertIsNotNone(match, "trimmed batch is not CREATE PROCEDURE")
        header = trimmed[match.start():match.start() + 240]
        self.assertIn("OT_SendSalesmanData", header)
        self.assertNotIn("Unknown", header)

        payload = (
            "SET PARSEONLY ON;\nGO\n" + trimmed + "\nGO\nSET PARSEONLY OFF;\n"
        ).encode("utf-8")
        self.assertFalse(payload.startswith(b"\xef\xbb\xbf"))

        host = pathlib.Path(tempfile.gettempdir()) / f"drift_parseonly_{os.getpid()}.sql"
        try:
            host.write_bytes(payload)
            copied = subprocess.run(
                ["docker", "cp", str(host), f"{_CONTAINER}:{_REMOTE_SQL}"],
                capture_output=True,
            )
            self.assertEqual(
                copied.returncode,
                0,
                _redact(copied.stderr.decode("utf-8", "replace"), password),
            )
            # -b makes sqlcmd exit non-zero on a SQL error. Without it, a
            # rejected batch still returns 0. -f 65001 reads the UTF-8 file.
            parsed = subprocess.run(
                [
                    "docker", "exec", _CONTAINER,
                    _SQLCMD, "-C", "-b", "-S", "localhost",
                    "-U", "sa", "-P", password, "-d", "Olives_BO",
                    "-f", "65001", "-i", _REMOTE_SQL,
                ],
                capture_output=True,
            )
            out = _redact(parsed.stdout.decode("utf-8", "replace"), password)
            err = _redact(parsed.stderr.decode("utf-8", "replace"), password)
            self.assertEqual(
                parsed.returncode,
                0,
                "SET PARSEONLY rejected the trimmed batch\n" + out + err,
            )
            self.assertNotIn("Msg ", out)
            self.assertNotIn("Msg ", err)
        finally:
            host.unlink(missing_ok=True)
            subprocess.run(
                ["docker", "exec", "-u", "root", _CONTAINER, "rm", "-f", _REMOTE_SQL],
                capture_output=True,
            )

        conn = _connect(password, skip_if_down=False)
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT CONVERT(varchar(30), modify_date, 126) "
                "FROM sys.objects "
                "WHERE object_id = OBJECT_ID(N'dbo.OT_SendSalesmanData')"
            )
            after = cur.fetchone()[0]
        finally:
            conn.close()
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
