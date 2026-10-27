"""Procedure exclusion matcher.

Contains and Starts with both exclude. Several rules combine with OR, the
same way drift.compare.is_excluded excludes a name when any pattern matches.
Match is case-insensitive (str.casefold) because Olives_BO uses
SQL_Latin1_General_CP1256_CI_AS. Tokens are not anchored.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.proc_filter import default_rules, procedure_excluded  # noqa: E402

CONTAINS = (
    "alpha", "sap", "bonanza", "integ", "mms", "jawad", "hammoudeh",
    "technical", "niroukh", "api", "medical", "poa", "tax", "asset",
    "thuraya", "cmms", "memo",
)
STARTS = ("sp", "oms", "sms", "owms")
CLEAN = "OT_SendSalesmanData"


class ProcFilterTests(unittest.TestCase):
    def test_defaults_are_exactly_the_list(self):
        rules = default_rules()
        self.assertEqual([r["value"] for r in rules if r["op"] == "contains"], list(CONTAINS))
        self.assertEqual([r["value"] for r in rules if r["op"] == "starts_with"], list(STARTS))
        self.assertEqual(len(rules), len(CONTAINS) + len(STARTS))
        self.assertEqual(rules[0], {"op": "contains", "value": "alpha"})
        self.assertEqual(rules[-1], {"op": "starts_with", "value": "owms"})
        self.assertEqual(
            [r["op"] for r in rules],
            ["contains"] * len(CONTAINS) + ["starts_with"] * len(STARTS),
        )
        self.assertEqual(
            {(r["op"], r["value"]) for r in rules},
            {("contains", value) for value in CONTAINS}
            | {("starts_with", value) for value in STARTS},
        )
        self.assertTrue(all(set(r) == {"op", "value"} for r in rules))

    def test_contains_is_casefold_substring_or(self):
        self.assertTrue(procedure_excluded("OSFA_SP_Api"))
        self.assertTrue(procedure_excluded("Spartan_SAP_Integ"))
        self.assertTrue(procedure_excluded("ABS_Integ_GetDataFromAPI"))
        self.assertTrue(procedure_excluded("Alpha_Foo"))
        self.assertTrue(procedure_excluded("dbo.Alpha_Foo"))
        self.assertFalse(procedure_excluded("OT_SendSalesmanData"))

    def test_starts_with_is_prefix_not_anchored(self):
        self.assertTrue(procedure_excluded("sp_helptext"))
        self.assertTrue(procedure_excluded("SpecialReport"))
        self.assertTrue(procedure_excluded("Spartan_SAP_Integ"))
        self.assertFalse(procedure_excluded("GetSpecial"))
        self.assertTrue(procedure_excluded("owms_sync"))
        self.assertFalse(procedure_excluded("xowms"))

    def test_empty_token_matches_nothing(self):
        self.assertFalse(procedure_excluded("Anything", [{"op": "contains", "value": ""}]))
        self.assertFalse(procedure_excluded("Anything", [{"op": "starts_with", "value": "  "}]))
        self.assertFalse(procedure_excluded("Anything", [{"op": "regex", "value": "Any"}]))
        self.assertFalse(procedure_excluded("  Anything", [{"op": "starts_with", "value": "  "}]))
        self.assertFalse(procedure_excluded("alpha", [{"op": "contains", "value": ""}]))

    def test_excluded_name_is_the_drop_gate(self):
        self.assertTrue(procedure_excluded("alpha_hide"))
        self.assertFalse(procedure_excluded("UsesTvp"))
        for name in ("alpha_hide", "Spartan_SAP_Integ", "SpecialReport", "owms_sync"):
            self.assertTrue(procedure_excluded(name), name)
        for name in ("UsesTvp", "GetSpecial", "xowms", CLEAN):
            self.assertFalse(procedure_excluded(name), name)

    def test_each_default_token_excludes_a_match_and_not_a_clean_name(self):
        self.assertFalse(procedure_excluded(CLEAN))
        for token in CONTAINS:
            match = f"Zz{token}Zz"
            only = [{"op": "contains", "value": token}]
            self.assertTrue(procedure_excluded(match), token)
            self.assertTrue(procedure_excluded(match, only), token)
            self.assertFalse(procedure_excluded(CLEAN, only), token)
        for token in STARTS:
            match = f"{token.upper()}_Head"
            only = [{"op": "starts_with", "value": token}]
            self.assertTrue(procedure_excluded(match), token)
            self.assertTrue(procedure_excluded(match, only), token)
            self.assertFalse(procedure_excluded(CLEAN, only), token)

    def test_starts_with_does_not_fire_on_a_mid_name(self):
        for token in STARTS:
            mid = f"Qa{token}Qa"
            only = [{"op": "starts_with", "value": token}]
            self.assertNotEqual(mid.casefold()[:len(token)], token)
            self.assertIn(token, mid.casefold())
            self.assertFalse(procedure_excluded(mid, only), token)
            # None of the default starts-with tokens are also contains tokens.
            self.assertFalse(procedure_excluded(mid), token)
        self.assertFalse(procedure_excluded("GetSpecial"))
        self.assertFalse(procedure_excluded("xowms"))
        # A contains token still excludes a mid-name hit. "mms" is contains;
        # "sms" is only starts-with, so the same position is not a prefix hit.
        self.assertTrue(procedure_excluded("QammsQa"))
        self.assertFalse(procedure_excluded("QasmsQa"))
        both = [
            {"op": "contains", "value": "sp"},
            {"op": "starts_with", "value": "sp"},
        ]
        self.assertTrue(procedure_excluded("GetSpecial", both))
        self.assertTrue(procedure_excluded("SpecialReport", both))

    def test_match_is_casefold(self):
        self.assertTrue(procedure_excluded("ALPHA_FOO"))
        self.assertTrue(procedure_excluded("alpha_foo"))
        self.assertTrue(procedure_excluded("AlPhA_foo"))
        self.assertTrue(procedure_excluded("SPECIALREPORT"))
        self.assertTrue(procedure_excluded("specialreport"))
        self.assertTrue(procedure_excluded("HAMMOUDEH_x"))
        self.assertFalse(procedure_excluded("getspecial"))
        self.assertFalse(procedure_excluded("GETSPECIAL"))
        self.assertTrue(procedure_excluded("kept", [{"op": "contains", "value": "KEPT"}]))
        self.assertTrue(procedure_excluded("Owms_Sync", [{"op": "starts_with", "value": "OWMS"}]))

    def test_tokens_are_not_word_anchored(self):
        self.assertTrue(procedure_excluded("taxonomy"))
        self.assertTrue(procedure_excluded("PreIntegPost"))
        self.assertTrue(procedure_excluded("NotApiHidden"))
        self.assertTrue(procedure_excluded("Spartan_SAP_Integ"))

    def test_rules_combine_with_or(self):
        rules = [
            {"op": "contains", "value": "alpha"},
            {"op": "starts_with", "value": "sp"},
        ]
        self.assertTrue(procedure_excluded("Alpha_Only", rules))
        self.assertTrue(procedure_excluded("SpecialReport", rules))
        self.assertFalse(procedure_excluded("UsesTvp", rules))
        self.assertFalse(procedure_excluded("Alpha_Only", []))

    def test_per_run_removal_drops_only_that_token(self):
        without_alpha = [
            rule for rule in default_rules()
            if not (rule["op"] == "contains" and rule["value"] == "alpha")
        ]
        self.assertEqual(len(without_alpha), len(CONTAINS) + len(STARTS) - 1)
        self.assertFalse(any(rule["value"] == "alpha" for rule in without_alpha))
        self.assertFalse(procedure_excluded("Alpha_Foo", without_alpha))
        self.assertFalse(procedure_excluded("ALPHA_hide", without_alpha))
        self.assertTrue(procedure_excluded("Bonanza_Run", without_alpha))
        self.assertTrue(procedure_excluded("SpecialReport", without_alpha))
        self.assertTrue(procedure_excluded("Jawad_x", without_alpha))
        for token in CONTAINS:
            if token == "alpha":
                continue
            self.assertTrue(procedure_excluded(f"Zz{token}Zz", without_alpha), token)
        for token in STARTS:
            self.assertTrue(procedure_excluded(f"{token}_keep", without_alpha), token)

        without_sp = [
            rule for rule in default_rules()
            if not (rule["op"] == "starts_with" and rule["value"] == "sp")
        ]
        self.assertFalse(procedure_excluded("SpecialReport", without_sp))
        self.assertFalse(procedure_excluded("sp_helptext", without_sp))
        self.assertTrue(procedure_excluded("Spartan_SAP_Integ", without_sp))
        self.assertTrue(procedure_excluded("owms_sync", without_sp))
        self.assertTrue(procedure_excluded("Alpha_Foo", without_sp))

        shown = default_rules()
        shown[:] = [rule for rule in shown if rule["value"] != "alpha"]
        reloaded = default_rules()
        self.assertEqual(reloaded[0], {"op": "contains", "value": "alpha"})
        self.assertEqual(len(reloaded), len(CONTAINS) + len(STARTS))
        self.assertTrue(procedure_excluded("Alpha_Foo"))

    def test_qualified_name_uses_the_object_segment(self):
        self.assertTrue(procedure_excluded("[alpha_hide]"))
        self.assertTrue(procedure_excluded("dbo.sp_helptext"))
        self.assertTrue(procedure_excluded("[dbo].[sp_helptext]"))
        self.assertTrue(procedure_excluded("dbo.[SpecialReport]"))
        self.assertTrue(procedure_excluded("[dbo.SpecialReport]"))
        self.assertTrue(procedure_excluded("[Olives_BO].[dbo].[owms_sync]"))
        self.assertFalse(procedure_excluded("dbo.GetSpecial"))
        self.assertFalse(procedure_excluded("[dbo].[UsesTvp]"))
        self.assertFalse(procedure_excluded("sales.dbo.UsesTvp"))


if __name__ == "__main__":
    unittest.main()
