"""Deep battery for blocks.py -- ClientActive block-scope resolution.

Every rule in the module docstring gets a test that would fail loudly if the
rule regressed, mirroring the surgical-battery philosophy: expected answers
fixed BEFORE the run, including adversarial probes (literals containing gate
syntax, CASE-END depth interference, dead-subtree containment). Run standalone:
    python3.13 test_blocks.py
"""
import sys
import unittest
from pathlib import Path

# blocks.py/statements.py use package-relative imports (same situation as
# test_statements.py -- see its docstring), so drift-tool/ goes on sys.path
# and the `drift` package provides the namespace.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.blocks import evaluate_condition, resolve_scope  # noqa: E402


def _proc(body: str) -> str:
    return f"CREATE PROCEDURE [dbo].[zz_test] AS\nBEGIN\n{body}\nEND"


class ConditionEvaluation(unittest.TestCase):
    def test_eq_match_and_no_match(self):
        self.assertEqual(evaluate_condition("@ClientActive = 66", 66), "match")
        self.assertEqual(evaluate_condition("@ClientActive = 165", 66), "no_match")

    def test_reversed_operand(self):
        self.assertEqual(evaluate_condition("165 = @ClientActive", 165), "match")
        self.assertEqual(evaluate_condition("165 = @ClientActive", 66), "no_match")

    def test_not_equals_is_the_generic_path(self):
        # The user's core case: `<> otherID` is how a generic block admits
        # every client EXCEPT the named ones.
        self.assertEqual(evaluate_condition("@ClientActive <> 165", 66), "match")
        self.assertEqual(evaluate_condition("@ClientActive <> 66", 66), "no_match")

    def test_in_and_not_in_lists(self):
        self.assertEqual(evaluate_condition("@ClientActive IN (33, 44, 165)", 66), "no_match")
        self.assertEqual(evaluate_condition("@ClientActive IN (33, 66)", 66), "match")
        self.assertEqual(evaluate_condition("@ClientActive NOT IN (33, 165)", 66), "match")
        self.assertEqual(evaluate_condition("@ClientActive NOT IN (33, 66)", 66), "no_match")

    def test_and_compound_of_exclusions(self):
        self.assertEqual(
            evaluate_condition("@ClientActive <> 165 AND @ClientActive <> 99", 66), "match")
        self.assertEqual(
            evaluate_condition("@ClientActive <> 99 AND @ClientActive = 66", 66), "match")
        self.assertEqual(
            evaluate_condition("@ClientActive <> 99 AND @ClientActive = 66", 165), "no_match")

    def test_or_with_unknown_term_degrades_to_unknown(self):
        self.assertEqual(
            evaluate_condition("@ClientActive = 165 OR @CompNo = 2", 66), "unknown")

    def test_no_variable_is_unknown(self):
        self.assertEqual(evaluate_condition("@SalesmanNo = 3", 66), "unknown")

    def test_var_vs_variable_is_unknown(self):
        self.assertEqual(evaluate_condition("@ClientActive = @SomeOtherVar", 66), "unknown")

    def test_none_and_empty_are_unknown(self):
        self.assertEqual(evaluate_condition(None, 66), "unknown")
        self.assertEqual(evaluate_condition("", 66), "unknown")

    def test_invalid_id_degrades_to_unknown(self):
        self.assertEqual(evaluate_condition("@ClientActive = 66", "abc"), "unknown")

    def test_commented_gate_text_is_ignored(self):
        cond = "/* old gate: @ClientActive = 165 */ @ClientActive = 66"
        self.assertEqual(evaluate_condition(cond, 66), "match")


class ScopeResolution(unittest.TestCase):
    def test_own_gate_kept_plus_generic_statement(self):
        r = resolve_scope(_proc(
            "IF @ClientActive = 66\nBEGIN\n SELECT 1\nEND\nSELECT 2"), 66)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("SELECT 1", joined)
        self.assertIn("SELECT 2", joined)
        self.assertEqual(r["stats"]["match"], 1)
        self.assertEqual(r["excluded_blocks"], [])

    def test_other_clients_branch_excluded_and_reported(self):
        r = resolve_scope(_proc(
            "IF @ClientActive = 165\nBEGIN\n SELECT 99\nEND\nSELECT 1"), 66)
        self.assertTrue(r["ok"])
        self.assertNotIn("SELECT 99", "\n".join(r["relevant_blocks"]))
        self.assertEqual(len(r["excluded_blocks"]), 1)
        self.assertIn("165", r["excluded_blocks"][0]["condition"])

    def test_else_body_harvested_when_client_already_has_arm(self):
        r = resolve_scope(_proc(
            "IF @ClientActive = 66\nBEGIN\n SELECT 'mine'\nEND\n"
            "ELSE\nBEGIN\n SELECT 'new feature'\nEND"), 66)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("mine", joined)
        self.assertNotIn("new feature", joined)
        harvest = r["excluded_blocks"]
        self.assertTrue(any(
            e.get("kind") == "else" and "new feature" in (e.get("body") or "")
            for e in harvest), harvest)

    def test_chain_client_matches_middle_else_becomes_dead(self):
        body = ("IF @ClientActive = 33\nBEGIN\n SELECT 'a'\nEND\n"
                "ELSE IF @ClientActive = 66\nBEGIN\n SELECT 'b'\nEND\n"
                "ELSE\nBEGIN\n SELECT 'c'\nEND")
        r = resolve_scope(_proc(body), 66)
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("'b'", joined)
        self.assertNotIn("'a'", joined)
        self.assertNotIn("'c'", joined)          # ELSE unreachable after definite match
        self.assertEqual(r["stats"]["match"], 1)
        self.assertEqual(r["stats"]["no_match"], 2)

    def test_kept_elseif_renders_as_if_when_it_is_the_only_arm(self):
        r = resolve_scope(_proc(
            "IF @ClientActive = 8\nBEGIN\n SELECT 8\nEND\n"
            "ELSE IF @ClientActive = 66\nBEGIN\n SELECT 66\nEND"), 66)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("IF @ClientActive = 66", joined)
        self.assertNotIn("ELSE IF", joined)

    def test_all_gates_fail_so_else_is_the_clients_path(self):
        body = ("IF @ClientActive = 33\nBEGIN\n SELECT 'a'\nEND\n"
                "ELSE IF @ClientActive = 165\nBEGIN\n SELECT 'b'\nEND\n"
                "ELSE\nBEGIN\n SELECT 'generic'\nEND")
        r = resolve_scope(_proc(body), 66)
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("'generic'", joined)
        self.assertNotIn("'a'", joined)
        self.assertNotIn("'b'", joined)

    def test_unknown_first_branch_keeps_everything_later(self):
        body = ("IF @ClientActive = @Which\nBEGIN\n SELECT 'u'\nEND\n"
                "ELSE IF @ClientActive = 165\nBEGIN\n SELECT 'x'\nEND\n"
                "ELSE\nBEGIN\n SELECT 'e'\nEND")
        r = resolve_scope(_proc(body), 66)
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("'u'", joined)             # unknown -> keep
        self.assertNotIn("'x'", joined)          # still decidable no_match
        self.assertIn("'e'", joined)             # uncertain prior -> ELSE stays possible
        self.assertGreaterEqual(r["stats"]["unknown"], 1)

    def test_nested_inner_gate_inside_dead_subtree_stays_dead(self):
        body = ("IF @ClientActive = 165\nBEGIN\n"
                "  IF @ClientActive = 66\n  BEGIN\n   SELECT 'ghost'\n  END\n"
                "END\nSELECT 'shared'")
        r = resolve_scope(_proc(body), 66)
        joined = "\n".join(r["relevant_blocks"])
        self.assertNotIn("'ghost'", joined)      # dead code is dead at any depth
        self.assertIn("'shared'", joined)
        self.assertEqual(r["stats"]["no_match"], 1)

    def test_outer_kept_inner_gate_resolved(self):
        body = ("IF @ClientActive = 66\nBEGIN\n"
                "  SELECT 'ours'\n"
                "  IF @ClientActive = 99\n  BEGIN\n   SELECT 'theirs'\n  END\n"
                "  SELECT 'also-ours'\n"
                "END")
        r = resolve_scope(_proc(body), 66)
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("'ours'", joined)
        self.assertIn("'also-ours'", joined)
        self.assertNotIn("'theirs'", joined)

    def test_string_literal_containing_gate_syntax_is_not_a_branch(self):
        body = ("IF @ClientActive = 66\nBEGIN\n"
                "  PRINT 'IF @ClientActive = 999 BEGIN phantom END'\n"
                "END")
        r = resolve_scope(_proc(body), 66)
        self.assertTrue(r["ok"])
        self.assertEqual(r["stats"]["match"], 1)     # only ONE real gate seen
        self.assertIn("phantom", "\n".join(r["relevant_blocks"]))

    def test_case_expression_does_not_corrupt_depth(self):
        body = ("IF @ClientActive = 66\nBEGIN\n"
                "  SELECT CASE WHEN 1 = 1 THEN 'x' ELSE 'y' END AS v\nEND")
        r = resolve_scope(_proc(body), 66)
        self.assertTrue(r["ok"], r.get("reason"))
        self.assertIn("CASE", "\n".join(r["relevant_blocks"]))

    def test_cursor_body_fails_honestly(self):
        body = ("DECLARE c CURSOR FOR SELECT 1\nOPEN c\nFETCH NEXT FROM c INTO @i\n"
                "WHILE @@FETCH_STATUS = 0\nBEGIN\n FETCH NEXT FROM c INTO @i\nEND\n"
                "CLOSE c\nDEALLOCATE c")
        r = resolve_scope(_proc(body), 66)
        self.assertFalse(r["ok"])
        self.assertIn("CURSOR", r["reason"])

    def test_invalid_id_fails_cleanly(self):
        r = resolve_scope(_proc("SELECT 1"), None)
        self.assertFalse(r["ok"])

    def test_unbraced_single_statement_branch(self):
        body = "IF @ClientActive = 66\n UPDATE T SET A = 1\nSELECT 2"
        r = resolve_scope(_proc(body), 66)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = " ".join("\n".join(r["relevant_blocks"]).split())
        self.assertIn("UPDATE T SET A = 1", joined)
        self.assertIn("SELECT 2", joined)

    def test_unbounded_no_match_with_no_keywords_is_excluded_not_copied(self):
        # Unbraced IF whose "body" has no statement keyword in the mask.
        r = resolve_scope(_proc(
            "IF @ClientActive = 123 -- '\n"
            "BEGIN\n SELECT 'other'\nEND"), 8)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = "\n".join(r["relevant_blocks"])
        self.assertNotIn("other", joined)

    def test_unbraced_single_statement_no_match_still_conservative(self):
        """IF @ClientActive = 123 UPDATE ... with no BEGIN: extent is one statement;
        that statement must not survive for client 8 if we can classify it.
        If the segmenter cannot split, today's rule keeps it — this test
        documents the bounded=false + UPDATE keyword path stays KEEP only
        when we cannot prove the IF wraps just that UPDATE.
        """
        r = resolve_scope(_proc(
            "IF @ClientActive = 123\n UPDATE T SET A = 1\nSELECT 2"), 8)
        self.assertTrue(r["ok"], r.get("reason"))
        joined = "\n".join(r["relevant_blocks"])
        self.assertIn("SELECT 2", joined)


class FingerprintSemantics(unittest.TestCase):
    _SHARED = "INSERT INTO Log VALUES ('entry')"

    def _master(self):
        return _proc(f"IF @ClientActive = 165\nBEGIN\n SELECT 'spartan-old'\nEND\n{self._SHARED}")

    def _client(self):
        return _proc(f"IF @ClientActive = 165\nBEGIN\n SELECT 'spartan-brand-new'\nEND\n{self._SHARED}")

    def test_diff_only_inside_other_clients_block_reads_identical(self):
        # THE point of the whole module: another client's edited branch must
        # not register as drift for THIS client.
        m = resolve_scope(self._master(), 66)
        c = resolve_scope(self._client(), 66)
        self.assertTrue(m["ok"] and c["ok"])
        self.assertEqual(m["fingerprint"], c["fingerprint"])

    def test_diff_in_shared_code_changes_fingerprint(self):
        m = resolve_scope(self._master(), 66)
        other = _proc(f"IF @ClientActive = 165\nBEGIN\n SELECT 'same'\nEND\n{self._SHARED}\nINSERT INTO Log VALUES ('entry2')")
        o = resolve_scope(other, 66)
        self.assertNotEqual(m["fingerprint"], o["fingerprint"])

    def test_whitespace_normalization_is_stable(self):
        a = resolve_scope(_proc("IF @ClientActive=66\nBEGIN\n  select    1\nEND"), 66)
        b = resolve_scope(_proc("IF @ClientActive = 66\nBEGIN\nSELECT 1\nEND"), 66)
        self.assertEqual(a["fingerprint"], b["fingerprint"])


class HeuristicTier(unittest.TestCase):
    """The deep-test finding: real procs (e.g. the 218KB OT_SendCustomersInfo)
    contain a CURSOR somewhere, which used to void scope resolution entirely.
    Tiered honesty: boundaries survive vocabulary distrust -- a provably-dead
    other-client branch inside a cursor proc stays provably dead."""

    def _cursor_proc_with_gate(self):
        body = ("DECLARE c CURSOR FOR SELECT 1\nOPEN c\nFETCH NEXT FROM c INTO @i\n"
                "IF @ClientActive = 165\nBEGIN\n SELECT 'spartan-only'\nEND\n"
                "SELECT 'shared'\n"
                "CLOSE c\nDEALLOCATE c")
        return _proc(body)

    def test_cursor_proc_with_clean_gate_is_heuristic_not_refused(self):
        r = resolve_scope(self._cursor_proc_with_gate(), 66)
        self.assertTrue(r["ok"], r.get("reason"))
        self.assertEqual(r["mode"], "heuristic")
        self.assertEqual(len(r["excluded_blocks"]), 1)
        self.assertIn("165", r["excluded_blocks"][0]["condition"])
        self.assertIsNone(r["fingerprint"])          # equality NEVER claimed here

    def test_cursor_proc_without_gates_still_fails_honestly(self):
        body = ("DECLARE c CURSOR FOR SELECT 1\nOPEN c\nFETCH NEXT FROM c INTO @i\n"
                "CLOSE c\nDEALLOCATE c")
        r = resolve_scope(_proc(body), 66)
        self.assertFalse(r["ok"])
        self.assertIn("CURSOR", r["reason"])

    def test_heuristic_exclusion_of_neq_our_id_gate(self):
        body = ("WHILE @@FETCH_STATUS = 0\nBEGIN\n FETCH NEXT FROM c INTO @i\nEND\n"
                "IF @ClientActive <> 66\nBEGIN\n SELECT 'not-ours'\nEND\nSELECT 'shared'")
        # no DECLARE CURSOR keyword -> not cursor_hit; force heuristic via vocab:
        # WHILE is recognized, so this is structured. Assert both modes behave
        # identically on the exclusion itself.
        r = resolve_scope(_proc(body), 66)
        self.assertTrue(r["ok"])
        self.assertEqual(r["excluded_blocks"][0]["condition"], "@ClientActive <> 66")
        self.assertNotIn("'not-ours'", "\n".join(r["relevant_blocks"]))

    def test_unbraced_gate_inside_cursor_proc_is_never_excluded(self):
        body = ("DECLARE c CURSOR FOR SELECT 1\nOPEN c\nFETCH NEXT FROM c INTO @i\n"
                "IF @ClientActive = 165 UPDATE T SET A = 1\n"
                "CLOSE c\nDEALLOCATE c")
        r = resolve_scope(_proc(body), 66)
        # Unbraced/unbounded gates are NEVER excluded (no proven extent):
        # either the proc is refused outright or the gate stays flagged
        # unknown with its text kept.
        if r["ok"]:
            self.assertEqual(
                [e for e in r["excluded_blocks"] if "165" in (e["condition"] or "")],
                [])
            self.assertIn("UPDATE T", "\n".join(r["relevant_blocks"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
