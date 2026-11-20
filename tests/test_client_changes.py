import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.client_changes import classify_client_change  # noqa: E402

PROC = "SqlProcedure"
TABLE = "SqlTable"
FUNC = "SqlScalarFunction"

ACTIVE = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
 END
 ELSE
 BEGIN
  SELECT 'else-only'
 END
END"""

ACTIVE_HIDES_B = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
  SELECT 'b'
 END
 ELSE
 BEGIN
  SELECT 'else-only'
 END
END"""

ACTIVE_EXTRA = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
  SELECT 'extra'
 END
 ELSE
 BEGIN
  SELECT 'else-only'
 END
END"""

ELSE_ONLY_RIGHT = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'arm'
 END
 ELSE
 BEGIN
  SELECT 'else-other'
 END
END"""


def _proc(role, name="dbo.zz_keep", master=None, client=None):
    return {
        "id": "p1",
        "type": PROC,
        "role": role,
        "category": "structural",
        "name": name,
        "bare_name": name.split(".")[-1],
        "master_def": master,
        "client_def": client,
    }


class ClassifyClientChangeTests(unittest.TestCase):
    def test_only_on_105_object_stays_off_the_list(self):
        row = {"id": "t1", "type": TABLE, "role": "only_on_other", "category": "structural",
               "name": "dbo.OnMaster", "bare_name": "OnMaster"}
        got = classify_client_change(row, 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "only_on_105")
        self.assertIsNone(got["inspect"])

    def test_excluded_procedure_name_stays_off_the_list(self):
        got = classify_client_change(
            _proc("added", name="dbo.ABS_Integ_GetDataFromAPI"), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "name_excluded")

    def test_excluded_function_name_stays_off_the_list(self):
        row = {"id": "f1", "type": FUNC, "role": "added", "category": "structural",
               "name": "dbo.Alpha_Foo", "bare_name": "Alpha_Foo"}
        got = classify_client_change(row, 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "name_excluded")

    def test_table_whose_name_contains_integ_is_still_listed(self):
        row = {"id": "t2", "type": TABLE, "role": "added", "category": "structural",
               "name": "dbo.IntegBuffer", "bare_name": "IntegBuffer"}
        got = classify_client_change(row, 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["inspect"], "immediate")

    def test_added_procedure_is_listed_for_later_inspect(self):
        got = classify_client_change(_proc("added", client="CREATE PROCEDURE dbo.zz_keep AS SELECT 1"), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "added")
        self.assertEqual(got["inspect"], "procedure")

    def test_client_hid_a_line_is_listed(self):
        got = classify_client_change(_proc("modified", master=ACTIVE_HIDES_B, client=ACTIVE), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")
        self.assertEqual(got["inspect"], "procedure")

    def test_client_added_a_line_is_listed(self):
        got = classify_client_change(_proc("modified", master=ACTIVE, client=ACTIVE_EXTRA), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")

    def test_else_only_difference_stays_off_the_list(self):
        got = classify_client_change(_proc("modified", master=ACTIVE, client=ELSE_ONLY_RIGHT), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")

    def test_modified_procedure_without_client_active_id_is_not_listed(self):
        got = classify_client_change(_proc("modified", master=ACTIVE, client=ACTIVE_EXTRA), None)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "needs_client_active")

    def test_table_missing_only_a_105_column_stays_off_the_list(self):
        row = {"id": "t3", "type": TABLE, "role": "modified", "category": "structural",
               "name": "dbo.Orders", "bare_name": "Orders",
               "columns": {"added": [], "removed": ["HiddenCol"], "retyped": []}}
        got = classify_client_change(row, None)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "only_on_105")

    def test_table_with_a_client_added_column_is_listed(self):
        row = {"id": "t4", "type": TABLE, "role": "modified", "category": "structural",
               "name": "dbo.Orders", "bare_name": "Orders",
               "columns": {"added": ["ExtraCol"], "removed": ["HiddenCol"], "retyped": []}}
        got = classify_client_change(row, None)
        self.assertTrue(got["list"])
        self.assertEqual(got["inspect"], "immediate")

    def test_formatting_only_stays_off_the_list(self):
        row = _proc("modified", master=ACTIVE, client=ACTIVE_EXTRA)
        row["category"] = "formatting_only"
        got = classify_client_change(row, 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "noise")


from drift.diff_render import render_split_diff  # noqa: E402
from drift.proc_lens import compare_procs  # noqa: E402


class TrimmedDiffReuseTests(unittest.TestCase):
    def test_active_read_diff_shows_a_hide_and_an_extra(self):
        master = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'keep'
  SELECT 'b'
  SELECT 'mid'
 END
END"""
        client = """CREATE PROCEDURE [dbo].[zz_keep]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'keep'
  SELECT 'mid'
  SELECT 'extra'
 END
END"""
        lens = compare_procs(master, client, 66, "active_read", direction="client_to_105")
        self.assertTrue(lens["ok"])
        self.assertFalse(lens["identical"])
        self.assertNotIn("ELSE", lens["preview_left"].upper())
        rich = render_split_diff(lens["preview_left"], lens["preview_right"])
        tags = [
            row["tag"]
            for hunk in rich["hunks"] if not hunk.get("collapsed")
            for row in hunk["lines"]
        ]
        self.assertIn("delete", tags)
        self.assertIn("insert", tags)
