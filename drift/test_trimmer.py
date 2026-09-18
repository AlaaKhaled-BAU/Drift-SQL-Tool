import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.trimmer import handle_trim, trim_procedure  # noqa: E402

PROC = """CREATE PROCEDURE [dbo].[zz_test]
AS
BEGIN
 IF @ClientActive = 66
 BEGIN
  SELECT 'mine'
 END
 ELSE
 BEGIN
  SELECT 'new feature'
 END
 SELECT 'shared'
END"""


class TrimProcedure(unittest.TestCase):
    def test_output_is_full_proc_without_else_arm(self):
        r = trim_procedure(PROC, 66)
        self.assertTrue(r["ok"], r.get("reason"))
        self.assertIn("CREATE PROCEDURE", r["trimmed_sql"])
        self.assertIn("mine", r["trimmed_sql"])
        self.assertIn("shared", r["trimmed_sql"])
        self.assertNotIn("new feature", r["trimmed_sql"])
        self.assertTrue(any("new feature" in (h.get("body") or "") for h in r["harvest"]))
        self.assertEqual(r["client_id"], 66)
        self.assertIn("mode", r)
        self.assertIn("stats", r)

    def test_invalid_id_refuses(self):
        r = trim_procedure(PROC, "abc")
        self.assertFalse(r["ok"])
        self.assertIsNone(r.get("trimmed_sql"))

    def test_empty_definition_refuses(self):
        r = trim_procedure("", 66)
        self.assertFalse(r["ok"])
        self.assertIsNone(r.get("trimmed_sql"))


class HandleTrim(unittest.TestCase):
    def test_handle_trim_ok_200(self):
        data, status = handle_trim({"definition": PROC, "client_active_id": 66})
        self.assertEqual(status, 200)
        self.assertTrue(data["ok"])
        self.assertIn("trimmed_sql", data)
        self.assertIn("harvest", data)

    def test_handle_trim_bad_id_400(self):
        data, status = handle_trim({"definition": PROC, "client_active_id": "abc"})
        self.assertEqual(status, 400)
        self.assertFalse(data["ok"])
        self.assertIn("reason", data)


if __name__ == "__main__":
    unittest.main()
