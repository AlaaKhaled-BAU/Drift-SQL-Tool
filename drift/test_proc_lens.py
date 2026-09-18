import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.proc_lens import compare_procs  # noqa: E402

LEFT = """CREATE PROCEDURE [dbo].[zz_lens]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm-left'
 END
 ELSE
 BEGIN
  SELECT 'else-old'
 END
END"""

RIGHT = """CREATE PROCEDURE [dbo].[zz_lens]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'new'
 END
 ELSE
 BEGIN
  SELECT 'else-new'
 END
END"""

SAME_ARM_LEFT = """CREATE PROCEDURE [dbo].[zz_lens]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'same'
 END
 ELSE
 BEGIN
  SELECT 'else-old'
 END
END"""

SAME_ARM_RIGHT = """CREATE PROCEDURE [dbo].[zz_lens]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'same'
 END
 ELSE
 BEGIN
  SELECT 'else-new'
 END
END"""


class CompareProcsLens(unittest.TestCase):
    def test_full_sees_else_and_arm(self):
        r = compare_procs(LEFT, RIGHT, 66, "full")
        self.assertTrue(r["ok"])
        self.assertTrue(
            "else-new" in r["diff_unified"] or "else-new" in r["preview_right"],
            r["diff_unified"],
        )
        self.assertEqual(r["copy_kind"], "create_or_alter")
        self.assertIn("CREATE OR ALTER", r["copy_sql"])

    def test_active_read_hides_else_from_preview(self):
        r = compare_procs(LEFT, RIGHT, 66, "active_read")
        self.assertTrue(r["ok"])
        self.assertIn("new", r["preview_right"])
        self.assertNotIn("else-new", r["preview_right"])
        self.assertFalse(r["identical"])

    def test_active_plus_else_shows_else_in_preview(self):
        r = compare_procs(LEFT, RIGHT, 66, "active_plus_else")
        self.assertTrue(r["ok"])
        self.assertIn("else-new", r["preview_right"])
        self.assertTrue(
            "-- HARVEST" in r["copy_sql"] or "else-new" in r["copy_sql"],
            r["copy_sql"],
        )

    def test_active_read_identical_when_only_else_differs(self):
        r = compare_procs(SAME_ARM_LEFT, SAME_ARM_RIGHT, 66, "active_read")
        self.assertTrue(r["ok"])
        self.assertTrue(r["identical"])
        r2 = compare_procs(SAME_ARM_LEFT, SAME_ARM_RIGHT, 66, "active_plus_else")
        self.assertTrue(r2["ok"])
        self.assertFalse(r2["identical"])

    def test_copy_sql_is_client_create_or_alter(self):
        r = compare_procs(LEFT, RIGHT, 66, "full")
        self.assertIn(r["copy_kind"], ("create_or_alter", "none"))
        self.assertNotIn("splice_up", r)
        self.assertNotEqual(r.get("target"), "105")
        self.assertEqual(r["copy_side"], "client")
        self.assertIn("CREATE OR ALTER", r["copy_sql"])
        self.assertIn("else-new", r["copy_sql"])
        self.assertNotIn("else-old", r["copy_sql"].split("CREATE OR ALTER", 1)[-1][:200])

    def test_105_to_client_copy_uses_master_def(self):
        r = compare_procs(LEFT, RIGHT, 66, "full", direction="105_to_client")
        self.assertTrue(r["ok"])
        self.assertEqual(r["copy_side"], "master")
        self.assertIn("else-old", r["copy_sql"])
        self.assertNotIn("else-new", r["copy_sql"].split("CREATE OR ALTER", 1)[-1][:200])

    def test_copy_bakes_wanted_side_settings(self):
        r = compare_procs(
            LEFT, RIGHT, 66, "full",
            client_settings={"ansi_nulls": False, "quoted_identifier": True},
        )
        self.assertIn("SET ANSI_NULLS OFF", r["copy_sql"])
        self.assertIn("SET QUOTED_IDENTIFIER ON", r["copy_sql"])


if __name__ == "__main__":
    unittest.main()
