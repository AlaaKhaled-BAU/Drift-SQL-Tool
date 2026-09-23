import unittest
from pathlib import Path
from unittest.mock import patch

from drift import restore


class RestoreCopy(unittest.TestCase):
    def test_restore_uses_docker_cp_not_browse_root(self):
        with patch("drift.restore.subprocess.run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = ""
            run.return_value.stderr = ""
            try:
                restore.stage_bak_in_container(Path("/tmp/anywhere/x.bak"), lambda m: None)
            except Exception as e:
                if "BACKUP_BROWSE_ROOT" in str(e) or "browse root" in str(e).lower():
                    self.fail(e)
            argv = " ".join(str(c) for call in run.call_args_list for c in (call[0][0] if call[0] else []))
            self.assertIn("cp", argv.lower())


if __name__ == "__main__":
    unittest.main()
