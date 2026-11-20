import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import scriptgen  # noqa: E402


class CreateOrAlterOnceTests(unittest.TestCase):
    def test_create_or_alter_is_not_doubled(self):
        src = "CREATE OR ALTER PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        out = scriptgen._as_create_or_alter(src)
        self.assertNotIn("CREATE OR ALTER OR ALTER", out)
        self.assertEqual(out.upper().count("CREATE OR ALTER"), 1)
        plain = "CREATE PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        once = scriptgen._as_create_or_alter(plain)
        self.assertIn("CREATE OR ALTER PROCEDURE", once)
        self.assertNotIn("CREATE OR ALTER OR ALTER", once)
        commented = "-- note\nCREATE OR ALTER PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        kept = scriptgen._as_create_or_alter(commented)
        self.assertNotIn("CREATE OR ALTER OR ALTER", kept)
        self.assertEqual(kept.upper().count("CREATE OR ALTER"), 1)

    def test_second_pass_keeps_a_single_create_or_alter(self):
        plain = "CREATE PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        once = scriptgen._as_create_or_alter(plain)
        twice = scriptgen._as_create_or_alter(once)
        self.assertNotIn("CREATE OR ALTER OR ALTER", twice)
        self.assertEqual(twice.upper().count("CREATE OR ALTER"), 1)

    def test_leading_comment_becomes_create_or_alter(self):
        src = "-- note\nCREATE PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END"
        out = scriptgen._as_create_or_alter(src)
        self.assertIn("-- note", out)
        self.assertIn("CREATE OR ALTER PROCEDURE", out)
        self.assertNotIn("CREATE OR ALTER OR ALTER", out)
        self.assertNotRegex(out, r"(?im)^CREATE\s+PROCEDURE\b")


if __name__ == "__main__":
    unittest.main()
