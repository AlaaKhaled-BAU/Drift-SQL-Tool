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
        path = Path(__file__).resolve().parent.parent / "sendsalesmandata.txt"
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

    def test_handle_trim_bad_id_400(self):
        data, status = handle_trim({"definition": PROC, "client_active_id": "abc"})
        self.assertEqual(status, 400)
        self.assertFalse(data["ok"])
        self.assertIn("reason", data)


if __name__ == "__main__":
    unittest.main()
