import unittest
from unittest.mock import patch

from drift import extract


class ExtractLive(unittest.TestCase):
    def test_live_extract_argv_uses_caller_server_not_host_port(self):
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append(cmd)

            class R:
                returncode = 0
                stdout = ""
                stderr = ""

            return R()

        with patch("drift.extract.subprocess.run", fake_run):
            extract.extract_dacpac_source(
                {
                    "server": "10.0.10.105",
                    "port": 1433,
                    "database": "Olives_BO",
                    "user": "sa",
                    "password": "x",
                },
                "/tmp/t.dacpac",
                lambda m: None,
            )
        cmd = calls[0]
        self.assertIn("/Action:Extract", cmd)
        self.assertTrue(any("10.0.10.105,1433" in str(x) for x in cmd))
        self.assertFalse(any("14330" in str(x) for x in cmd))
        self.assertFalse(any(str(x).startswith("/SourcePassword:") for x in cmd))
        self.assertTrue(any(str(x).startswith("@") for x in cmd))


if __name__ == "__main__":
    unittest.main()
