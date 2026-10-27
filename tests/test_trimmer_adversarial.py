"""Adversarial contract tests for the T-SQL procedure trimmer.

Each test is the smallest procedure that exhibits one shape. Expectations
follow SQL Server rules. A red test means the trimmer is wrong; the
assertion stays.
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.blocks import resolve_scope  # noqa: E402
from drift.trimmer import trim_procedure  # noqa: E402


def _without_literals(sql):
    """Blank string literals so a payload like 'else-arm' is not a keyword."""
    return re.sub(r"N?'(?:''|[^'])*'", " ", sql)


def _definition(body, *, verb="CREATE", params="@ClientActive int"):
    return (
        f"{verb} PROCEDURE dbo.p\n"
        f"    {params}\n"
        "AS\n"
        "BEGIN\n"
        f"{body.strip()}\n"
        "END"
    )


class TrimmerAdversarial(unittest.TestCase):
    def _trim(self, body, client_id=66, **kwargs):
        return trim_procedure(_definition(body, **kwargs), client_id)

    def _sql(self, body, client_id=66, **kwargs):
        result = self._trim(body, client_id, **kwargs)
        self.assertTrue(result["ok"], result.get("reason"))
        sql = result["trimmed_sql"]
        self._assert_wrapper(
            sql,
            verb=kwargs.get("verb", "CREATE"),
            params=kwargs.get("params", "@ClientActive int"),
        )
        return sql

    def _assert_wrapper(self, sql, *, verb="CREATE", params="@ClientActive int"):
        self.assertRegex(sql, rf"(?is)\b{verb}\s+PROCEDURE\b")
        self.assertIn(params, sql)
        self.assertRegex(sql, r"(?is)\bAS\s+BEGIN\b")
        self.assertRegex(sql, r"(?is)\bEND\s*$")

    def _assert_order(self, sql, patterns):
        start = 0
        for pattern in patterns:
            match = re.search(pattern, sql[start:], re.IGNORECASE | re.DOTALL)
            self.assertIsNotNone(match, f"missing {pattern}\n{sql}")
            start += match.end()

    def _assert_unconditional(self, sql, token):
        """A removed ladder's surviving ELSE runs as a BEGIN/END block."""
        self.assertIn(f"'{token}'", sql)
        code = _without_literals(sql)
        self.assertNotRegex(code, r"(?i)\bIF\b", sql)
        self.assertNotRegex(code, r"(?i)\bELSE\b", sql)
        self.assertNotRegex(code, r"(?i)1\s*=\s*1", sql)
        self.assertRegex(
            sql,
            rf"(?is)\bBEGIN\s+(?:BEGIN\s+)?SELECT\s+'{re.escape(token)}'\s+END\b",
            sql,
        )

    def test_dangling_else_if_after_removed_subquery_arm(self):
        sql = self._sql(
            """
            IF @ClientActive = 8 AND @x NOT IN (
                SELECT 8
            )
            BEGIN
                SELECT 'dead-arm'
            END
            ELSE IF @ClientActive = 66
            BEGIN
                SELECT 'kept-mine'
            END
            """
        )
        self.assertIn("kept-mine", sql)
        self.assertNotIn("dead-arm", sql)
        self.assertNotRegex(sql, r"(?i)\bNOT\s+IN\b", sql)
        self.assertNotRegex(
            sql,
            r"(?i)\bELSE\b",
            "surviving arm starts with ELSE after the subquery arm was removed:\n" + sql,
        )

    def test_multiline_or_client_id_only_on_second_line(self):
        sql = self._sql(
            """
            IF @ClientActive = 8
            OR @ClientActive = 66
            BEGIN
                SELECT 'kept-yes'
            END
            ELSE
            BEGIN
                SELECT 'dropped-no'
            END
            """
        )
        self.assertRegex(
            sql,
            r"(?is)@ClientActive\s*=\s*8\s+OR\s+@ClientActive\s*=\s*66",
            sql,
        )
        self.assertIn("kept-yes", sql)
        self.assertNotIn("dropped-no", sql)
        self.assertNotRegex(sql, r"(?i)\bELSE\b", sql)

    def test_unbraced_exec_leaves_following_select(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
                EXEC dbo.usp_Dead
            SELECT 'kept-after'
            """
        )
        self.assertNotRegex(sql, r"(?i)\bEXEC\b", sql)
        self.assertNotIn("usp_Dead", sql)
        self.assertNotRegex(sql, r"(?i)\bIF\b", sql)
        self.assertIn("kept-after", sql)

    def test_unbraced_update_set_is_one_statement(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
                UPDATE dbo.T SET Col = 1
            SELECT 'kept-after'
            """
        )
        self.assertNotRegex(
            sql,
            r"(?i)\bSET\b",
            "UPDATE SET was split; SET survived as its own statement:\n" + sql,
        )
        self.assertNotRegex(sql, r"(?i)\bUPDATE\b", sql)
        self.assertIn("kept-after", sql)

    def test_declare_list_hoists_only_the_used_name(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
            BEGIN
                DECLARE @a int, @b int = 5
                SELECT @a
            END
            SELECT @b
            """
        )
        decl = re.search(r"(?is)\bDECLARE\s+@b\s+int\b(?!\s*=)", sql)
        self.assertIsNotNone(
            decl,
            "kept @b needs DECLARE @b int, initializer stripped, @a not hoisted:\n" + sql,
        )
        self.assertNotIn("@a", sql)
        use = re.search(r"(?is)\bSELECT\s+@b\b", sql)
        self.assertIsNotNone(use, sql)
        self.assertLess(decl.start(), use.start())

    def test_table_variable_hoisted_without_its_insert(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
            BEGIN
                DECLARE @t TABLE (id int)
                INSERT INTO @t VALUES (1)
            END
            SELECT * FROM @t
            """
        )
        decl = re.search(r"(?is)\bDECLARE\s+@t\s+TABLE\s*\(\s*id\s+int\s*\)", sql)
        self.assertIsNotNone(decl, sql)
        use = re.search(r"(?is)\bFROM\s+@t\b", sql)
        self.assertIsNotNone(use, sql)
        self.assertLess(decl.start(), use.start())
        self.assertNotRegex(sql, r"(?i)\bINSERT\b", sql)

    def test_temp_table_unreferenced_is_not_hoisted(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
            BEGIN
                CREATE TABLE #temp (id int)
                INSERT INTO #temp VALUES (1)
            END
            SELECT 'kept-live'
            """
        )
        self.assertNotIn("#temp", sql)
        self.assertNotRegex(sql, r"(?i)\bCREATE\s+TABLE\b", sql)
        self.assertIn("kept-live", sql)

    def test_temp_table_referenced_by_kept_code_is_not_hoisted(self):
        """CREATE TABLE #temp stays in the removed arm. Kept code still
        reads #temp, so the batch does not compile. That gap is the result.
        """
        body = """
            IF @ClientActive = 1
            BEGIN
                CREATE TABLE #temp (id int)
                INSERT INTO #temp VALUES (1)
            END
            SELECT * FROM #temp
        """
        definition = _definition(body)
        scope = resolve_scope(definition, 66)
        self.assertTrue(scope["ok"], scope.get("reason"))
        kept_scope = "\n".join(scope["relevant_blocks"])
        result = trim_procedure(definition, 66)
        self.assertTrue(result["ok"], result.get("reason"))
        sql = result["trimmed_sql"]
        self._assert_wrapper(sql)
        for text in (kept_scope, sql):
            self.assertRegex(text, r"(?i)\bFROM\s+#temp\b", text)
            self.assertNotRegex(
                text,
                r"(?i)\bCREATE\s+TABLE\b",
                "CREATE TABLE #temp must not be hoisted; the reference is a compile gap:\n" + text,
            )

    def test_goto_from_outside_into_removed_arm_keeps_label(self):
        body = """
            GOTO Target
            IF @ClientActive = 1
            BEGIN
            Target:
                SELECT 'inside'
            END
            SELECT 'kept-after'
        """
        definition = _definition(body)
        scope = resolve_scope(definition, 66)
        self.assertTrue(scope["ok"], scope.get("reason"))
        excluded = "\n".join(block.get("body") or "" for block in scope["excluded_blocks"])
        self.assertNotIn("inside", excluded)
        sql = trim_procedure(definition, 66)["trimmed_sql"]
        self._assert_wrapper(sql)
        self.assertRegex(sql, r"(?i)\bGOTO\s+Target\b", sql)
        self.assertRegex(
            sql,
            r"(?m)^[ \t]*Target\s*:",
            "GOTO Target survived without its label:\n" + sql,
        )
        self.assertIn("inside", sql)
        self.assertIn("kept-after", sql)
        self.assertLess(
            re.search(r"(?i)\bGOTO\s+Target\b", sql).start(),
            re.search(r"(?m)^[ \t]*Target\s*:", sql).start(),
        )

    def test_label_in_comment_or_string_does_not_keep_arm(self):
        sql = self._sql(
            """
            GOTO Target
            IF @ClientActive = 1
            BEGIN
                SELECT 'dead-arm'
                SELECT 'Target:'
                /*
                Target:
                */
            END
            SELECT 'kept-live'
            Target:
            SELECT 'landed'
            """
        )
        self.assertNotIn(
            "dead-arm",
            sql,
            "a Target label inside a comment or string kept the dead arm:\n" + sql,
        )
        self.assertNotIn("'Target:'", sql)
        self.assertIn("kept-live", sql)
        self.assertIn("landed", sql)
        self.assertRegex(sql, r"(?i)\bGOTO\s+Target\b")
        self.assertRegex(sql, r"(?m)^[ \t]*Target\s*:")

    def test_if_condition_inside_string_is_not_a_gate(self):
        literal = (
            "IF @ClientActive = 1 BEGIN SELECT ''hidden'' END "
            "ELSE BEGIN SELECT ''also-hidden'' END"
        )
        sql = self._sql(
            f"""
            SELECT '{literal}'
            SELECT 'kept-visible'
            """,
            1,
        )
        self.assertIn(literal, sql)
        self.assertIn("kept-visible", sql)
        self.assertIn("also-hidden", sql)

    def test_case_else_inside_kept_arm_is_not_a_branch(self):
        sql = self._sql(
            """
            IF @ClientActive = 66
            BEGIN
                SELECT CASE WHEN 1 = 1 THEN 'a' ELSE 'b' END
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
            SELECT 'kept-after'
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s*=\s*66\s*BEGIN\s*"
            r"SELECT\s+CASE\s+WHEN\s+1\s*=\s*1\s+THEN\s+'a'\s+ELSE\s+'b'\s+END\s*"
            r"END\s*SELECT\s+'kept-after'",
            sql,
        )
        self.assertNotIn("else-arm", sql)
        self.assertNotRegex(sql, r"(?i)\bELSE\s+BEGIN\b", sql)

    def test_begin_tran_in_removed_arm_stays_balanced(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
            BEGIN
                BEGIN TRAN
                SELECT 'dead-arm'
                COMMIT TRAN
            END
            SELECT 'kept-live'
            """
        )
        self.assertNotIn("dead-arm", sql)
        self.assertNotRegex(sql, r"(?i)\bTRAN\b", sql)
        self.assertNotRegex(sql, r"(?i)\bCOMMIT\b", sql)
        self.assertIn("kept-live", sql)
        self.assertEqual(
            len(re.findall(r"(?i)\bBEGIN\b", sql)),
            len(re.findall(r"(?i)\bEND\b", sql)),
            sql,
        )

    def test_begin_try_catch_blocks_survive(self):
        result = self._trim(
            """
            BEGIN TRY
                IF @ClientActive = 1
                BEGIN
                    SELECT 'dead-arm'
                END
                SELECT 'kept-live'
            END TRY
            BEGIN CATCH
                SELECT 'caught-arm'
            END CATCH
            """
        )
        self.assertTrue(
            result["ok"],
            "BEGIN TRY/CATCH stays a block, the dead arm inside TRY is removed, "
            "and CATCH stays attached: " + str(result.get("reason")),
        )
        sql = result["trimmed_sql"]
        self._assert_wrapper(sql)
        self._assert_order(
            sql,
            [
                r"\bBEGIN\s+TRY\b",
                r"SELECT\s+'kept-live'",
                r"\bEND\s+TRY\b",
                r"\bBEGIN\s+CATCH\b",
                r"SELECT\s+'caught-arm'",
                r"\bEND\s+CATCH\b",
            ],
        )
        self.assertNotIn("dead-arm", sql)

    def test_nested_if_removes_inner_other_client(self):
        sql = self._sql(
            """
            IF @ClientActive = 66
            BEGIN
                SELECT 'outer'
                IF @ClientActive = 1
                BEGIN
                    SELECT 'inner-dead'
                END
                SELECT 'still'
            END
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s*=\s*66\s*BEGIN\s*"
            r"SELECT\s+'outer'\s*SELECT\s+'still'\s*END",
            sql,
        )
        self.assertNotIn("inner-dead", sql)
        self.assertNotRegex(sql, r"(?i)@ClientActive\s*=\s*1", sql)

    def test_unknown_or_predicate_keeps_following_else(self):
        sql = self._sql(
            """
            IF @ClientActive = 1 OR @Other = 1
            BEGIN
                SELECT 'maybe'
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s*=\s*1\s+OR\s+@Other\s*=\s*1\s*"
            r"BEGIN\s*SELECT\s+'maybe'\s*END\s*"
            r"ELSE\s*BEGIN\s*SELECT\s+'else-arm'\s*END",
            sql,
        )

    def test_first_arm_match_drops_middle_and_trailing_else(self):
        sql = self._sql(
            """
            IF @ClientActive = 66
            BEGIN
                SELECT 'first'
            END
            ELSE IF @ClientActive = 8
            BEGIN
                SELECT 'middle'
            END
            ELSE
            BEGIN
                SELECT 'trailing'
            END
            SELECT 'shared'
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s*=\s*66\s*BEGIN\s*"
            r"SELECT\s+'first'\s*END\s*SELECT\s+'shared'",
            sql,
        )
        self.assertNotIn("middle", sql)
        self.assertNotIn("trailing", sql)
        self.assertNotRegex(sql, r"(?i)\bELSE\b", sql)

    def test_while_condition_subquery_is_not_the_body(self):
        sql = self._sql(
            """
            WHILE EXISTS (SELECT 1 FROM dbo.T WHERE id = @ClientActive)
            BEGIN
                SELECT 'loop'
            END
            SELECT 'kept-after'
            """
        )
        self.assertRegex(
            sql,
            r"(?is)WHILE\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+dbo\.T\s+"
            r"WHERE\s+id\s*=\s*@ClientActive\s*\)\s*BEGIN\s+SELECT\s+'loop'\s+END\s+"
            r"SELECT\s+'kept-after'",
            sql,
        )

    def test_paren_inside_string_does_not_change_depth(self):
        # @s = '(' is not a client literal, so the AND stays unknown and ELSE stays.
        # The parenthesis inside the string must not swallow the body.
        sql = self._sql(
            """
            IF @ClientActive = 66 AND @s = '('
            BEGIN
                SELECT 'kept-mine'
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
            SELECT 'kept-after'
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s*=\s*66\s+AND\s+@s\s*=\s*'\('\s*"
            r"BEGIN\s+SELECT\s+'kept-mine'\s+END\s+"
            r"ELSE\s+BEGIN\s+SELECT\s+'else-arm'\s+END\s+"
            r"SELECT\s+'kept-after'",
            sql,
        )

    def test_semicolon_ends_unbraced_statement(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
                SELECT 'dead-arm';
            SELECT 'kept-live'
            """
        )
        self.assertNotIn("dead-arm", sql)
        self.assertIn("kept-live", sql)
        self.assertNotRegex(sql, r"(?i)\bIF\b", sql)

    def test_unicode_literal_begin_is_not_a_block(self):
        sql = self._sql(
            """
            IF @ClientActive = 66
            BEGIN
                SELECT N'BEGIN'
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
            SELECT 'kept-after'
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s*=\s*66\s*BEGIN\s*"
            r"SELECT\s+N'BEGIN'\s*END\s*SELECT\s+'kept-after'",
            sql,
        )
        self.assertNotIn("else-arm", sql)
        self.assertNotRegex(sql, r"(?i)\bELSE\b", sql)

    def test_final_else_becomes_begin_block(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
            BEGIN
                SELECT 'dead-arm'
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
            """
        )
        self.assertNotIn("dead-arm", sql)
        self._assert_unconditional(sql, "else-arm")

    def test_reversed_equality(self):
        body = """
            IF 165 = @ClientActive
            BEGIN
                SELECT 'kept-mine'
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
        """
        hit = self._sql(body, 165)
        self.assertRegex(hit, r"(?is)165\s*=\s*@ClientActive", hit)
        self.assertIn("kept-mine", hit)
        self.assertNotIn("else-arm", hit)
        self.assertNotRegex(hit, r"(?i)\bELSE\b", hit)
        miss = self._sql(body, 66)
        self.assertNotIn("kept-mine", miss)
        self._assert_unconditional(miss, "else-arm")

    def test_not_equal_comparison(self):
        body = """
            IF @ClientActive <> 66
            BEGIN
                SELECT 'not-me'
            END
            ELSE
            BEGIN
                SELECT 'me'
            END
        """
        same = self._sql(body, 66)
        self.assertNotIn("not-me", same)
        self._assert_unconditional(same, "me")
        other = self._sql(body, 8)
        self.assertRegex(other, r"(?is)@ClientActive\s*<>\s*66", other)
        self.assertIn("not-me", other)
        self.assertNotIn("'me'", other)
        self.assertNotRegex(other, r"(?i)\bELSE\b", other)

    def test_reversed_not_equal_comparison(self):
        body = """
            IF 66 <> @ClientActive
            BEGIN
                SELECT 'not-me'
            END
            ELSE
            BEGIN
                SELECT 'me'
            END
        """
        same = self._sql(body, 66)
        self.assertNotIn("not-me", same)
        self._assert_unconditional(same, "me")
        other = self._sql(body, 8)
        self.assertRegex(other, r"(?is)66\s*<>\s*@ClientActive", other)
        self.assertIn("not-me", other)
        self.assertNotIn("'me'", other)
        self.assertNotRegex(other, r"(?i)\bELSE\b", other)

    def test_in_list(self):
        body = """
            IF @ClientActive IN (8, 66, 70)
            BEGIN
                SELECT 'in-list'
            END
            ELSE
            BEGIN
                SELECT 'out-list'
            END
        """
        hit = self._sql(body, 66)
        self.assertRegex(hit, r"(?is)@ClientActive\s+IN\s*\(\s*8\s*,\s*66\s*,\s*70\s*\)", hit)
        self.assertIn("in-list", hit)
        self.assertNotIn("out-list", hit)
        self.assertNotRegex(hit, r"(?i)\bELSE\b", hit)
        miss = self._sql(body, 9)
        self.assertNotIn("in-list", miss)
        self._assert_unconditional(miss, "out-list")

    def test_not_in_list(self):
        body = """
            IF @ClientActive NOT IN (8, 70)
            BEGIN
                SELECT 'not-in'
            END
            ELSE
            BEGIN
                SELECT 'is-in'
            END
        """
        outside = self._sql(body, 66)
        self.assertRegex(
            outside,
            r"(?is)@ClientActive\s+NOT\s+IN\s*\(\s*8\s*,\s*70\s*\)",
            outside,
        )
        self.assertIn("not-in", outside)
        self.assertNotIn("is-in", outside)
        self.assertNotRegex(outside, r"(?i)\bELSE\b", outside)
        inside = self._sql(body, 8)
        self.assertNotIn("not-in", inside)
        self._assert_unconditional(inside, "is-in")

    def test_between_is_inclusive(self):
        body = """
            IF @ClientActive BETWEEN 60 AND 70
            BEGIN
                SELECT 'inside'
            END
            ELSE
            BEGIN
                SELECT 'outside'
            END
        """
        for client_id in (60, 66, 70):
            with self.subTest(client_id=client_id):
                sql = self._sql(body, client_id)
                self.assertRegex(sql, r"(?is)BETWEEN\s+60\s+AND\s+70", sql)
                self.assertIn("inside", sql)
                self.assertNotIn("outside", sql)
                self.assertNotRegex(sql, r"(?i)\bELSE\b", sql)
        for client_id in (59, 71):
            with self.subTest(client_id=client_id):
                sql = self._sql(body, client_id)
                self.assertNotIn("inside", sql)
                self._assert_unconditional(sql, "outside")

    def test_not_between(self):
        body = """
            IF @ClientActive NOT BETWEEN 60 AND 70
            BEGIN
                SELECT 'outside'
            END
            ELSE
            BEGIN
                SELECT 'inside'
            END
        """
        inside = self._sql(body, 66)
        self.assertNotIn("outside", inside)
        self._assert_unconditional(inside, "inside")
        outside = self._sql(body, 59)
        self.assertRegex(
            outside,
            r"(?is)@ClientActive\s+NOT\s+BETWEEN\s+60\s+AND\s+70",
            outside,
        )
        self.assertIn("outside", outside)
        self.assertNotIn("'inside'", outside)
        self.assertNotRegex(outside, r"(?i)\bELSE\b", outside)

    def test_nested_block_comment_is_not_code(self):
        sql = self._sql(
            """
            /* outer /* inner */
            IF @ClientActive = 66
            BEGIN
                SELECT 'comment-only'
            END
            */
            SELECT 'kept-live'
            """
        )
        self.assertNotIn(
            "comment-only",
            sql,
            "text after the inner */ was treated as code:\n" + sql,
        )
        self.assertIn("kept-live", sql)
        self.assertNotRegex(sql, r"(?i)\bIF\b", sql)

    def test_header_parameters_stay_on_alter_procedure(self):
        definition = (
            "ALTER PROCEDURE dbo.p\n"
            "    @ClientActive int,\n"
            "    @Name nvarchar(50) = N'default'\n"
            "AS\n"
            "BEGIN\n"
            "    IF @ClientActive = 66\n"
            "    BEGIN\n"
            "        SELECT @Name\n"
            "    END\n"
            "    ELSE\n"
            "    BEGIN\n"
            "        SELECT 'else-arm'\n"
            "    END\n"
            "END"
        )
        result = trim_procedure(definition, 66)
        self.assertTrue(result["ok"], result.get("reason"))
        sql = result["trimmed_sql"]
        self.assertRegex(sql, r"(?is)\bALTER\s+PROCEDURE\s+dbo\.p\b")
        self.assertIn("@ClientActive int", sql)
        self.assertIn("@Name nvarchar(50) = N'default'", sql)
        self.assertRegex(sql, r"(?is)\bAS\s+BEGIN\b")
        self.assertRegex(sql, r"(?is)\bEND\s*$")
        self.assertIn("SELECT @Name", sql)
        self.assertNotIn("else-arm", sql)

    def test_goto_and_label_inside_removed_arm_both_disappear(self):
        sql = self._sql(
            """
            IF @ClientActive = 1
            BEGIN
                GOTO Inside
                Inside:
                SELECT 'dead-arm'
            END
            SELECT 'kept-live'
            """
        )
        self.assertNotIn("dead-arm", sql)
        self.assertNotRegex(sql, r"(?i)\bGOTO\b", sql)
        self.assertNotRegex(sql, r"(?m)^[ \t]*Inside\s*:", sql)
        self.assertIn("kept-live", sql)

    def test_between_variable_keeps_following_else(self):
        sql = self._sql(
            """
            IF @ClientActive BETWEEN @lo AND @hi
            BEGIN
                SELECT 'maybe'
            END
            ELSE
            BEGIN
                SELECT 'else-arm'
            END
            """
        )
        self.assertRegex(
            sql,
            r"(?is)IF\s+@ClientActive\s+BETWEEN\s+@lo\s+AND\s+@hi\s*"
            r"BEGIN\s*SELECT\s+'maybe'\s*END\s*"
            r"ELSE\s*BEGIN\s*SELECT\s+'else-arm'\s*END",
            sql,
        )

    def test_unknown_unbraced_if_keeps_its_condition(self):
        sql = self._sql(
            """
            IF @ClientActive = 1 OR @Flag = 1
                EXEC dbo.usp_Maybe
            SELECT 'kept-after'
            """
        )
        tail = re.split(
            r"(?is)\bIF\s+@ClientActive\s*=\s*1\s+OR\s+@Flag\s*=\s*1\b",
            sql,
            maxsplit=1,
        )
        self.assertEqual(
            len(tail),
            2,
            "undecided unbraced IF dropped its condition and runs EXEC unconditionally:\n" + sql,
        )
        self.assertRegex(
            tail[1],
            r"(?is)^(?:\s*BEGIN\s+EXEC\s+dbo\.usp_Maybe\s+END|\s*EXEC\s+dbo\.usp_Maybe)"
            r"\s+SELECT\s+'kept-after'",
            sql,
        )


if __name__ == "__main__":
    unittest.main()
