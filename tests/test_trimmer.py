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


class TrimmerBatchTests(unittest.TestCase):
    def test_select_stays_select(self):
        result = trim_procedure("SELECT 1 AS id", 62)
        self.assertTrue(result["ok"])
        self.assertEqual(result["trimmed_sql"], "SELECT 1 AS id")
        self.assertNotIn("Unknown", result["trimmed_sql"])
        self.assertNotIn("BEGIN", result["trimmed_sql"])

    def test_procedure_keeps_the_matching_branch(self):
        src = (
            "CREATE PROCEDURE dbo.P @ClientActive int AS BEGIN "
            "IF @ClientActive = 62 BEGIN SELECT 62 END ELSE BEGIN SELECT 1 END END"
        )
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"])
        self.assertTrue(result["trimmed_sql"].startswith("CREATE PROCEDURE"))
        self.assertIn("SELECT 62", result["trimmed_sql"])
        self.assertNotIn("SELECT 1", result["trimmed_sql"])

    def test_function_stays_function(self):
        src = "CREATE FUNCTION dbo.F() RETURNS int AS BEGIN RETURN 1 END"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertIn("FUNCTION", result["trimmed_sql"])
        self.assertIn("BEGIN", result["trimmed_sql"])
        self.assertIn("RETURN 1", result["trimmed_sql"])
        self.assertNotIn("Unknown", result["trimmed_sql"])

    def test_inline_tvf_is_returned_executable(self):
        src = "CREATE FUNCTION dbo.F() RETURNS TABLE AS RETURN SELECT 1 AS id"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertIn("RETURNS TABLE", result["trimmed_sql"])
        self.assertIn("RETURN SELECT 1 AS id", result["trimmed_sql"])
        self.assertNotIn("Unknown", result["trimmed_sql"])
        self.assertNotIn("CREATE PROCEDURE", result["trimmed_sql"])

    def test_view_stays_view(self):
        src = "CREATE VIEW dbo.V AS SELECT 1 AS id"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertTrue(result["trimmed_sql"].lstrip().upper().startswith("CREATE VIEW"))
        self.assertNotIn("Unknown", result["trimmed_sql"])

    def test_create_or_alter_procedure_is_a_module(self):
        src = "CREATE OR ALTER PROCEDURE dbo.P @ClientActive int AS BEGIN SELECT 1 END"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertIn("CREATE OR ALTER PROCEDURE", result["trimmed_sql"])
        self.assertNotIn("Unknown", result["trimmed_sql"])

    def test_create_or_alter_survives_a_second_trim(self):
        src = "CREATE OR ALTER PROCEDURE dbo.P @ClientActive int AS BEGIN SELECT 1 END"
        once = trim_procedure(src, 62)
        self.assertTrue(once["ok"], once.get("reason"))
        twice = trim_procedure(once["trimmed_sql"], 62)
        self.assertTrue(twice["ok"], twice.get("reason"))
        self.assertIn("CREATE OR ALTER PROCEDURE", twice["trimmed_sql"])
        self.assertNotIn("CREATE OR ALTER OR ALTER", twice["trimmed_sql"])
        self.assertEqual(twice["trimmed_sql"].upper().count("CREATE OR ALTER"), 1)
        self.assertNotIn("Unknown", twice["trimmed_sql"])

    def test_leading_comment_before_create_stays_a_module(self):
        src = "-- keep me\nCREATE PROCEDURE dbo.P @ClientActive int AS BEGIN SELECT 1 END"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertIn("-- keep me", result["trimmed_sql"])
        self.assertIn("CREATE PROCEDURE", result["trimmed_sql"])
        self.assertNotIn("Unknown", result["trimmed_sql"])

    def test_use_batch_stays_use(self):
        src = (
            "USE [Olives_BO]\nGO\nSET ANSI_NULLS ON\nGO\n"
            "CREATE PROCEDURE dbo.P @id int AS BEGIN SELECT @id END"
        )
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertIn("USE [Olives_BO]", result["trimmed_sql"])
        self.assertNotIn("-- omitted USE", result["trimmed_sql"])
        self.assertIn("SET ANSI_NULLS ON", result["trimmed_sql"])
        self.assertIn("\nGO\n", result["trimmed_sql"])

    def test_go_inside_a_string_does_not_split(self):
        src = "SELECT 'line\nGO\nline' AS q"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertEqual(result["trimmed_sql"].count("GO"), 1)
        self.assertNotIn("Unknown", result["trimmed_sql"])

    def test_string_containing_create_procedure_is_not_a_module(self):
        src = "SELECT 'CREATE PROCEDURE dbo.Fake AS SELECT 1' AS q"
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertNotIn("Unknown", result["trimmed_sql"])
        self.assertNotIn("CREATE PROCEDURE [dbo].[Unknown]", result["trimmed_sql"])
        self.assertTrue(result["trimmed_sql"].lstrip().upper().startswith("SELECT"))

    def test_invalid_id_on_a_module_is_not_ok(self):
        src = "CREATE PROCEDURE dbo.P @ClientActive int AS BEGIN SELECT 1 END"
        result = trim_procedure(src, "nope")
        self.assertFalse(result["ok"])
        self.assertIsNone(result["trimmed_sql"])

    def test_unbalanced_module_returns_the_original_batch(self):
        src = (
            "CREATE PROCEDURE dbo.P @ClientActive int AS BEGIN "
            "IF @ClientActive = 62 BEGIN SELECT 62 END"
        )
        result = trim_procedure(src, 62)
        self.assertTrue(result["ok"])
        self.assertEqual(result["trimmed_sql"], src)
        self.assertTrue(result["reason"])

    def test_loose_client_active_is_executable_and_not_a_procedure(self):
        result = trim_procedure("SELECT @ClientActive AS id", 62)
        self.assertTrue(result["ok"], result.get("reason"))
        self.assertNotIn("CREATE PROCEDURE", result["trimmed_sql"])
        self.assertNotIn("Unknown", result["trimmed_sql"])
        self.assertIn("DECLARE @ClientActive int = 62", result["trimmed_sql"])
        self.assertIn("SELECT @ClientActive AS id", result["trimmed_sql"])

    def test_omitted_id_on_a_batch_with_no_gates_returns_the_select(self):
        result = trim_procedure("SELECT 1 AS id", None)
        self.assertTrue(result["ok"])
        self.assertEqual(result["trimmed_sql"], "SELECT 1 AS id")


if __name__ == "__main__":
    unittest.main()
