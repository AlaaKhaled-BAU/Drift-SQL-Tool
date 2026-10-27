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

LUXURY_QUOTE = """CREATE PROCEDURE [dbo].[OT_MimicLuxuryQuote]
AS
BEGIN
IF @ClientActive = 8
BEGIN
  SELECT 'eight'
END
ELSE IF @ClientActive = 35 -- 'luxury items
BEGIN
  DELETE FROM OT_Stores WHERE SalesmanNo = @SalesmanNo
  IF @ClientActive = 88
  BEGIN
    INSERT INTO @Xtb SELECT 1
  END
END
ELSE IF @ClientActive in (83,149,160)-- Bladna
BEGIN
  SELECT 'bladna'
END
END"""


class LuxuryQuoteChain(unittest.TestCase):
    def test_client_8_drops_quoted_comment_arm_and_bladna(self):
        r = trim_procedure(LUXURY_QUOTE, 8)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertIn("IF @ClientActive = 8", sql)
        self.assertIn("eight", sql)
        self.assertNotIn("@ClientActive = 88", sql)
        self.assertNotIn("@Xtb", sql)
        self.assertNotIn("Bladna", sql)
        self.assertNotIn("bladna", sql)

    def test_client_35_keeps_if_line(self):
        r = trim_procedure(LUXURY_QUOTE, 35)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertIn("IF @ClientActive = 35", sql)
        self.assertIn("DELETE FROM OT_Stores", sql)
        self.assertNotIn("eight", sql)
        self.assertNotIn("bladna", sql)

    def test_client_88_does_not_keep_bladna(self):
        r = trim_procedure(LUXURY_QUOTE, 88)
        self.assertTrue(r["ok"], r.get("reason"))
        self.assertNotIn("bladna", r["trimmed_sql"])


class TrimProcedure(unittest.TestCase):
    def test_output_is_full_proc_without_else_arm(self):
        r = trim_procedure(PROC, 66)
        self.assertTrue(r["ok"], r.get("reason"))
        self.assertIn("CREATE PROCEDURE", r["trimmed_sql"])
        self.assertIn("IF @ClientActive = 66", r["trimmed_sql"])
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

    def test_middle_elseif_emits_if_not_else_if(self):
        proc = """CREATE PROCEDURE [dbo].[zz]
AS
BEGIN
IF @ClientActive = 8
BEGIN
  SELECT 'eight'
END
ELSE IF @ClientActive = 66
BEGIN
  SELECT 'sixtysix'
END
END"""
        r = trim_procedure(proc, 66)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertIn("IF @ClientActive = 66", sql)
        self.assertNotIn("ELSE IF", sql)
        self.assertIn("sixtysix", sql)
        self.assertNotIn("eight", sql)


class SendSalesmanData(unittest.TestCase):
    """The real OT_SendSalesmanData dump. Client 8 must not keep the
    123/161 PostedToERP gate; client 123 must keep that gate, IF line included."""

    @classmethod
    def setUpClass(cls):
        path = (
            Path(__file__).resolve().parent.parent
            / "fixtures"
            / "procedures"
            / "OT_SendSalesmanData.sql"
        )
        cls.definition = path.read_text(encoding="utf-8", errors="replace")

    def test_client_8_drops_other_client_update(self):
        r = trim_procedure(self.definition, 8)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertNotIn(
            "(@ClientActive=123 and @SalesPersonType=7) or @ClientActive = 161",
            sql,
        )
        self.assertNotIn("set PostedToERP=1", sql)
        self.assertGreater(r["stats"]["no_match"], 43)

    def test_client_8_does_not_keep_88_or_bladna_stores(self):
        r = trim_procedure(self.definition, 8)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertNotIn("if @ClientActive= 88", sql)
        self.assertNotIn("Bladna", sql)
        self.assertLess(len(sql), 400_000)

    def test_client_123_keeps_the_gate_and_its_if_line(self):
        r = trim_procedure(self.definition, 123)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertIn(
            "(@ClientActive=123 and @SalesPersonType=7) or @ClientActive = 161",
            sql,
        )
        self.assertIn("set PostedToERP=1", sql)
        self.assertIn("IF (@ClientActive=123", sql)


class ApiTrimRoute(unittest.TestCase):
    def test_flask_trim_route(self):
        from app import app as flask_app

        client = flask_app.test_client()
        r = client.post("/api/trim", json={"definition": PROC, "client_active_id": 66})
        self.assertEqual(r.status_code, 200)
        data = r.get_json()
        self.assertTrue(data["ok"])
        self.assertIn("trimmed_sql", data)


class HandleTrim(unittest.TestCase):
    def test_handle_trim_ok_200(self):
        data, status = handle_trim({"definition": PROC, "client_active_id": 66})
        self.assertEqual(status, 200)
        self.assertTrue(data["ok"])
        self.assertIn("trimmed_sql", data)
        self.assertIn("harvest", data)
        self.assertIn("excluded_ranges", data)

    def test_handle_trim_bad_id_400(self):
        data, status = handle_trim({"definition": PROC, "client_active_id": "abc"})
        self.assertEqual(status, 400)
        self.assertFalse(data["ok"])
        self.assertIn("reason", data)


class ExcludedRangesAndHighlighting(unittest.TestCase):
    def test_excluded_ranges_emitted_and_paint_entire_branch_red(self):
        proc = """CREATE PROCEDURE dbo.CollisionTest
AS
BEGIN
  -- comment outside gate
  IF @ClientActive = 1
  BEGIN
    SELECT 1
  END
  IF @ClientActive = 2
  BEGIN

    SELECT 1
  END
END"""
        r = trim_procedure(proc, 1)
        self.assertTrue(r["ok"])
        ranges = r.get("excluded_ranges")
        self.assertTrue(bool(ranges), "excluded_ranges must be non-empty")
        # Line 9 to 13 is IF @ClientActive = 2 BEGIN \n SELECT 1 END
        self.assertEqual(ranges[0], [9, 13])

        # Test highlighting logic equivalent to app.js:
        # Check range first: any line inside [start, end] is 'trimmed' (even blanks)
        trimmed_sql = r["trimmed_sql"]
        raw_lines = proc.splitlines()
        trimmed_set = set(l.strip() for l in trimmed_sql.splitlines() if l.strip())

        classified = []
        for idx, raw in enumerate(raw_lines):
            line_no = idx + 1
            if any(s <= line_no <= e for s, e in ranges):
                kind = "trimmed"
            else:
                norm = raw.strip()
                if not norm:
                    kind = "plain"
                elif norm in trimmed_set:
                    kind = "kept"
                else:
                    kind = "plain"
            classified.append((line_no, kind, raw))

        # Line 4 is comment outside gate -> plain
        self.assertEqual(classified[3][1], "plain")
        # Lines 5-8 are ClientActive = 1 -> kept
        for i in range(4, 8):
            self.assertEqual(classified[i][1], "kept", f"Line {i+1} should be kept")
        # Lines 9-13 are ClientActive = 2 -> trimmed (ALL lines red, including blank line 11 and SELECT 1)
        for i in range(8, 13):
            self.assertEqual(classified[i][1], "trimmed", f"Line {i+1} should be trimmed despite collision")
        self.assertEqual(classified[10][1], "trimmed", "Blank line inside cut block must be trimmed")

    def test_three_line_preamble_before_create_proc(self):
        script = """USE [master]
GO
SET ANSI_NULLS ON
CREATE PROCEDURE dbo.PreambleTest AS
BEGIN
  IF @ClientActive = 1
  BEGIN
    SELECT 1
  END
  IF @ClientActive = 2
  BEGIN
    SELECT 2
  END
END"""
        r = trim_procedure(script, 1)
        self.assertTrue(r["ok"])
        ranges = r.get("excluded_ranges")
        self.assertEqual(len(ranges), 1)
        # Line 10 to 13 is IF @ClientActive = 2 ... END in the full original script
        self.assertEqual(ranges[0], [10, 13])
        self.assertEqual(r["harvest"][0]["start_line"], 10)
        self.assertEqual(r["harvest"][0]["end_line"], 13)


DECLARE_TABLE = """CREATE PROCEDURE [dbo].[zz_decl]
AS
BEGIN
IF @ClientActive IN (74, 94)
BEGIN
  DECLARE @OT_ActionLog_Tmp TABLE (AutoID int PRIMARY KEY)
  INSERT INTO @OT_ActionLog_Tmp SELECT 1
END
UPDATE OT_CustomerMF SET A = 1
FROM @OT_ActionLog_Tmp AS i
WHERE @ClientActive NOT IN (136, 142)
END"""

DECLARE_SCALAR = """CREATE PROCEDURE [dbo].[zz_scalar]
AS
BEGIN
IF @ClientActive = 35
BEGIN
  DECLARE @AviItemsCount int = (SELECT COUNT(*) FROM Items)
END
UPDATE OT_SalesmanMF SET AviItemsCount = @AviItemsCount
END"""

TEMP_TABLE = """CREATE PROCEDURE [dbo].[zz_temp]
AS
BEGIN
IF @ClientActive = 35
BEGIN
  CREATE TABLE #OnlyTheirs (id int)
  INSERT INTO #OnlyTheirs SELECT 1
END
SELECT 1 AS shared
END"""


class DeclareHoist(unittest.TestCase):
    def test_table_variable_declare_is_prepended_without_its_insert(self):
        r = trim_procedure(DECLARE_TABLE, 248)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertRegex(sql, r"(?i)DECLARE\s+@OT_ActionLog_Tmp\s+TABLE")
        self.assertIn("FROM @OT_ActionLog_Tmp", sql)
        self.assertNotIn("INSERT INTO @OT_ActionLog_Tmp", sql)

    def test_scalar_initializer_is_stripped(self):
        r = trim_procedure(DECLARE_SCALAR, 248)
        self.assertTrue(r["ok"], r.get("reason"))
        sql = r["trimmed_sql"]
        self.assertRegex(sql, r"(?i)DECLARE\s+@AviItemsCount\s+int")
        self.assertNotIn("SELECT COUNT", sql)
        self.assertIn("@AviItemsCount", sql)

    def test_temp_table_is_not_hoisted(self):
        r = trim_procedure(TEMP_TABLE, 248)
        self.assertTrue(r["ok"], r.get("reason"))
        self.assertNotIn("#OnlyTheirs", r["trimmed_sql"])
        self.assertIn("shared", r["trimmed_sql"])


if __name__ == "__main__":
    unittest.main()
