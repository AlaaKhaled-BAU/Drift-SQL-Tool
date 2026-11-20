"""Adversarial traps for Client changes. No database.

Each test names the trap and what a failure would mean. SQL is fed to
classify_client_change, compare_procs (active_read, client_to_105),
trim_procedure, and render_split_diff. Flask cases use on-disk sidecars.
"""
import json
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from drift.client_changes import classify_client_change  # noqa: E402
from drift.diff_render import render_split_diff  # noqa: E402
from drift.proc_lens import compare_procs  # noqa: E402
from drift.trimmer import trim_procedure  # noqa: E402

PROC = "SqlProcedure"
TABLE = "SqlTable"
FUNC = "SqlScalarFunction"
VIEW = "SqlView"


def _proc(role, name="dbo.zz_keep", master=None, client=None, **extra):
    bare = name.split(".")[-1].strip("[]")
    row = {
        "id": extra.pop("id", "p1"),
        "type": extra.pop("type", PROC),
        "role": role,
        "category": extra.pop("category", "structural"),
        "name": name,
        "bare_name": extra.pop("bare_name", bare),
        "master_def": master,
        "client_def": client,
    }
    row.update(extra)
    return row


def _wrap(body: str, name: str = "zz_keep") -> str:
    return f"CREATE PROCEDURE dbo.{name} AS\nBEGIN\n{body}\nEND"


def _tags(hunks):
    return [
        row.get("tag")
        for hunk in hunks or []
        if not hunk.get("collapsed")
        for row in hunk.get("lines") or []
    ]


def _side_text(row, tag):
    side = row.get("left") if tag == "delete" else row.get("right")
    if not side:
        return ""
    if "text" in side:
        return side["text"]
    return "".join(word.get("text", "") for word in side.get("words") or [])


def _texts(hunks, tag):
    return [
        _side_text(row, tag)
        for hunk in hunks or []
        if not hunk.get("collapsed")
        for row in hunk.get("lines") or []
        if row.get("tag") == tag
    ]


def _lens(master, client, cid=66):
    return compare_procs(master, client, cid, "active_read", direction="client_to_105")


def _diff(master, client, cid=66):
    lens = _lens(master, client, cid)
    rich = render_split_diff(lens.get("preview_left") or "", lens.get("preview_right") or "")
    return lens, rich


class HideAndExtraTraps(unittest.TestCase):
    def test_hidden_line_before_shared_mid_stays_listed_as_delete(self):
        """Trap: client drops SELECT 'b' but keeps SELECT 'mid'. Failure means a customization was dropped or paired away."""
        master = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'keep'\n  SELECT 'b'\n  SELECT 'mid'\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'keep'\n  SELECT 'mid'\n END")
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")
        lens, rich = _diff(master, client)
        self.assertFalse(lens["identical"])
        self.assertTrue(any("b" in text for text in _texts(rich["hunks"], "delete")), _texts(rich["hunks"], "delete"))

    def test_client_extra_after_shared_line_is_an_insert(self):
        """Trap: client adds SELECT 'extra' after a shared line. Failure means a client-only line never reaches the diff."""
        master = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'keep'\n  SELECT 'mid'\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'keep'\n  SELECT 'mid'\n  SELECT 'extra'\n END")
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")
        _, rich = _diff(master, client)
        self.assertTrue(any("extra" in text for text in _texts(rich["hunks"], "insert")), _texts(rich["hunks"], "insert"))


class ElseAndNestedTraps(unittest.TestCase):
    def test_else_only_difference_is_not_listed(self):
        """Trap: only the other client's ELSE body differs. Failure means active_read still treated ELSE as a client change."""
        master = _wrap(
            " IF @ClientActive = 66\n BEGIN\n  SELECT 'arm'\n END\n ELSE\n BEGIN\n  SELECT 'else-old'\n END"
        )
        client = master.replace("else-old", "else-new")
        trimmed = trim_procedure(master, 66)
        self.assertTrue(trimmed["ok"])
        self.assertNotIn("else-old", trimmed["trimmed_sql"])
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")

    def test_inner_client_8_block_inside_66_does_not_list(self):
        """Trap: the only difference is IF @ClientActive = 8 nested inside the 66 arm. Failure means another client's inner block survived the trim."""
        master = _wrap(
            " IF @ClientActive = 66\n BEGIN\n  SELECT 'arm'\n  IF @ClientActive = 8\n  BEGIN\n   SELECT 'inner-a'\n  END\n  SELECT 'after'\n END"
        )
        client = master.replace("inner-a", "inner-b")
        left = trim_procedure(master, 66)["trimmed_sql"]
        right = trim_procedure(client, 66)["trimmed_sql"]
        self.assertNotIn("inner-a", left)
        self.assertNotIn("inner-b", right)
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")

    def test_difference_in_the_66_arm_around_a_nested_8_is_listed(self):
        """Trap: the 66 arm itself changes while an inner 8 block is noise. Failure means a real arm change was discarded with the inner block."""
        master = _wrap(
            " IF @ClientActive = 66\n BEGIN\n  SELECT 'arm'\n  IF @ClientActive = 8\n  BEGIN\n   SELECT 'inner'\n  END\n END"
        )
        client = master.replace("SELECT 'arm'", "SELECT 'arm2'")
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")
        lens = _lens(master, client)
        self.assertIn("arm2", lens["preview_right"])
        self.assertNotIn("inner", lens["preview_left"])


class NameAndRoleTraps(unittest.TestCase):
    def test_integ_alpha_sp_and_mms_names_are_excluded(self):
        """Trap: bracketed, cased, and function names that Scripts skip. Failure means an excluded name was offered as a client change."""
        cases = [
            _proc("added", name="dbo.ABS_Integ_GetDataFromAPI", client="CREATE PROCEDURE dbo.ABS_Integ_GetDataFromAPI AS SELECT 1"),
            _proc("modified", name="[dbo].[Alpha_Foo]", bare_name="", master="x", client="y"),
            _proc("added", name="dbo.SP_Something", client="CREATE PROCEDURE dbo.SP_Something AS SELECT 1"),
            _proc("added", name="dbo.mms_helper", type=FUNC, client="CREATE FUNCTION dbo.mms_helper() RETURNS int AS BEGIN RETURN 1 END"),
        ]
        # bare_name "" must fall through to the bracketed name, not skip the filter.
        cases[1]["bare_name"] = ""
        for row in cases:
            got = classify_client_change(row, 66)
            self.assertFalse(got["list"], row["name"])
            self.assertEqual(got["kind"], "name_excluded", row["name"])

    def test_integ_table_and_sap_view_are_still_listed(self):
        """Trap: Scripts name tokens on a table and a view. Failure means the proc/function filter swallowed objects Scripts still emits."""
        table = {"id": "t", "type": TABLE, "role": "added", "category": "structural",
                 "name": "dbo.IntegBuffer", "bare_name": "IntegBuffer"}
        view = {"id": "v", "type": VIEW, "role": "added", "category": "structural",
                "name": "dbo.SapView", "bare_name": "SapView"}
        for row in (table, view):
            got = classify_client_change(row, 66)
            self.assertTrue(got["list"], row["name"])
            self.assertEqual(got["inspect"], "immediate", row["name"])

    def test_only_on_105_procedure_and_table_stay_off_even_with_a_body(self):
        """Trap: role only_on_other plus a real master body and an empty client body. Failure means a 105-only object was listed as a customization."""
        master = _wrap(" SELECT 'only-on-105'")
        proc = _proc("only_on_other", master=master, client="")
        table = {"id": "t", "type": TABLE, "role": "only_on_other", "category": "structural",
                 "name": "dbo.OnMaster", "bare_name": "OnMaster", "master_def": "CREATE TABLE dbo.OnMaster(id int)"}
        for row in (proc, table):
            got = classify_client_change(row, 66)
            self.assertFalse(got["list"])
            self.assertEqual(got["kind"], "only_on_105")
            self.assertIsNone(got["inspect"])


class TableColumnTraps(unittest.TestCase):
    def _table(self, columns):
        row = {"id": "t", "type": TABLE, "role": "modified", "category": "structural",
               "name": "dbo.Orders", "bare_name": "Orders"}
        if columns is not None:
            row["columns"] = columns
        return row

    def test_removed_column_only_is_not_listed(self):
        """Trap: the client lacks a column 105 has and nothing else changed. Failure means Scripts work was listed as a client change."""
        got = classify_client_change(self._table({"added": [], "removed": ["HiddenCol"], "retyped": []}), None)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "only_on_105")

    def test_added_column_plus_removed_column_is_listed(self):
        """Trap: a client-added column sitting next to a 105-only column. Failure means the added column was hidden by the removed one."""
        got = classify_client_change(
            self._table({"added": ["ExtraCol"], "removed": ["HiddenCol"], "retyped": []}), None)
        self.assertTrue(got["list"])
        self.assertEqual(got["inspect"], "immediate")

    def test_retyped_column_only_is_listed(self):
        """Trap: both sides have the column but the type changed. Failure means a real column change was treated as client-behind."""
        got = classify_client_change(
            self._table({"added": [], "removed": [], "retyped": [{"name": "Qty"}]}), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["inspect"], "immediate")

    def test_modified_table_without_column_detail_is_listed(self):
        """Trap: no columns key, so the evidence is unknown. Failure means unknown table drift was silently dropped."""
        got = classify_client_change(self._table(None), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "modified")
        self.assertEqual(got["inspect"], "immediate")


class GateAndNoiseTraps(unittest.TestCase):
    def test_missing_client_active_id_does_not_list_a_real_procedure_diff(self):
        """Trap: None and blank id on a procedure whose arms differ. Failure means procedures were compared without a ClientActive id."""
        master = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'a'\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'b'\n END")
        for cid in (None, ""):
            got = classify_client_change(_proc("modified", master=master, client=client), cid)
            self.assertFalse(got["list"], repr(cid))
            self.assertEqual(got["kind"], "needs_client_active")
            self.assertTrue(got["reason"])

    def test_missing_client_active_id_still_lists_an_added_table(self):
        """Trap: the procedure id gate applied to a new table. Failure means tables waited on a ClientActive id they do not use."""
        row = {"id": "t", "type": TABLE, "role": "added", "category": "structural",
               "name": "dbo.NewT", "bare_name": "NewT"}
        for cid in (None, ""):
            got = classify_client_change(row, cid)
            self.assertTrue(got["list"], repr(cid))
            self.assertEqual(got["inspect"], "immediate")

    def test_noise_categories_hide_a_real_body_diff(self):
        """Trap: formatting_only, no_difference, and irrelevant_to_client with different bodies. Failure means noise was promoted to a change."""
        master = _wrap(" SELECT 'one'")
        client = _wrap(" SELECT 'two'")
        rows = [
            _proc("modified", master=master, client=client, category="formatting_only"),
            _proc("modified", master=master, client=client, category="no_difference"),
            _proc("modified", master=master, client=client, scope={"irrelevant_to_client": True}),
        ]
        for row in rows:
            got = classify_client_change(row, 66)
            self.assertFalse(got["list"], row.get("category") or row.get("scope"))
            self.assertEqual(got["kind"], "noise")


class TrimFailureAndAddedTraps(unittest.TestCase):
    def test_empty_definition_uses_the_trimmer_reason(self):
        """Trap: both bodies are blank. Failure means the trimmer reason was swallowed or the blank proc was listed."""
        direct = trim_procedure("   ", 66)
        self.assertFalse(direct["ok"])
        got = classify_client_change(_proc("modified", master="  ", client=""), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "trim_failed")
        self.assertEqual(got["reason"], direct["reason"])
        self.assertEqual(got["reason"], "empty definition")

    def test_rejected_client_active_id_uses_the_trimmer_reason(self):
        """Trap: id 'nope' is not a missing id, it is a trimmer rejection. Failure means classify invented its own reason or listed the proc."""
        body = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 1\n END")
        direct = trim_procedure(body, "nope")
        self.assertFalse(direct["ok"])
        got = classify_client_change(_proc("modified", master=body, client=body), "nope")
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "trim_failed")
        self.assertEqual(got["reason"], direct["reason"])
        self.assertIn("invalid client_active_id", got["reason"])

    def test_added_procedure_is_listed_for_inspect_without_a_master_body(self):
        """Trap: a new client procedure has no 105 body. Failure means it was trimmed against an empty master and dropped."""
        got = classify_client_change(
            _proc("added", client="CREATE PROCEDURE dbo.zz_keep AS SELECT 1"), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "added")
        self.assertEqual(got["inspect"], "procedure")


class CommentLiteralAndNormalizeTraps(unittest.TestCase):
    def test_client_active_id_only_in_a_comment_does_not_list(self):
        """Trap: 66 appears only in a comment and the executable text matches. Failure means the comment was executed as a branch or kept as a diff."""
        master = _wrap(" -- IF @ClientActive = 66 SELECT 'ghost'\n SELECT 'same'")
        client = _wrap(" -- IF @ClientActive = 8 SELECT 'other-ghost'\n SELECT 'same'")
        left = trim_procedure(master, 66)["trimmed_sql"]
        self.assertNotIn("ghost", left)
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")

    def test_string_literal_is_not_a_branch_and_a_different_literal_still_lists(self):
        """Trap: '@ClientActive = 66' inside a string is not a gate. Ceiling: the trimmer keeps the literal, so a different string is a real change and is listed."""
        master = _wrap(" SELECT 'IF @ClientActive = 66 SELECT secret'\n SELECT 'same'")
        same = master
        changed = master.replace("secret", "other")
        self.assertIn("secret", trim_procedure(master, 66)["trimmed_sql"])
        identical = classify_client_change(_proc("modified", master=master, client=same), 66)
        self.assertFalse(identical["list"])
        self.assertEqual(identical["kind"], "identical_after_trim")
        listed = classify_client_change(_proc("modified", master=master, client=changed), 66)
        self.assertTrue(listed["list"])
        self.assertEqual(listed["kind"], "trimmed_diff")

    def test_keyword_case_and_repeated_spaces_are_not_listed(self):
        """Trap: select vs SELECT and extra spaces. Failure means normalize_sql differences were listed. String-literal case is a separate ceiling and is not this trap."""
        master = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 1\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n  select    1\n END")
        lens = _lens(master, client)
        self.assertTrue(lens["identical"])
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")

    def test_string_letter_case_is_kept_because_normalize_sql_does_not_fold_literals(self):
        """Trap ceiling: 'Same' vs 'same' inside a string. The normalizer leaves literals exact, so this stays listed. Do not treat it as whitespace noise."""
        master = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'Same'\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'same'\n END")
        lens = _lens(master, client)
        self.assertFalse(lens["identical"])
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")

    def test_neither_side_matches_66_so_the_shared_skeleton_is_not_listed(self):
        """Trap: both procedures gate on client 8 and only that arm differs. Failure means an unmatched id still compared the other client's arm."""
        master = _wrap(" IF @ClientActive = 8\n BEGIN\n  SELECT 'eight'\n END\n SELECT 'shared'")
        client = master.replace("eight", "EIGHT")
        left = trim_procedure(master, 66)["trimmed_sql"]
        self.assertNotIn("eight", left.lower())
        self.assertIn("shared", left)
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")


class GoBatchTraps(unittest.TestCase):
    def _batch(self, arm, else_sql):
        return (
            "CREATE PROCEDURE dbo.one AS\nBEGIN\n SELECT 1\nEND\nGO\n"
            "CREATE PROCEDURE dbo.two AS\nBEGIN\n"
            " IF @ClientActive = 66\n BEGIN\n  SELECT '" + arm + "'\n END\n"
            " ELSE\n BEGIN\n  SELECT '" + else_sql + "'\n END\nEND"
        )

    def test_second_batch_else_only_is_not_listed(self):
        """Trap: two GO batches, and only the second procedure's inactive ELSE differs. Failure means a later batch's ELSE was compared."""
        master = self._batch("arm", "else-a")
        client = self._batch("arm", "else-b")
        self.assertNotIn("else-a", trim_procedure(master, 66)["trimmed_sql"])
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertFalse(got["list"])
        self.assertEqual(got["kind"], "identical_after_trim")

    def test_second_batch_active_arm_difference_is_listed(self):
        """Trap: the first batch matches and the second batch's 66 arm differs. Failure means a later batch was ignored."""
        master = self._batch("arm", "else-a")
        client = self._batch("arm-b", "else-a")
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")
        self.assertIn("arm-b", _lens(master, client)["preview_right"])


class DirectionAndSizeTraps(unittest.TestCase):
    def test_classify_calls_compare_procs_as_client_to_105(self):
        """Trap: compare_procs(..., direction='105_to_client') copies the master side. Failure means classify aimed the lens at the client-update direction."""
        import drift.client_changes as cc
        seen = {}
        real = cc.compare_procs

        def spy(left, right, cid, lens, **kwargs):
            seen["direction"] = kwargs.get("direction")
            seen["lens"] = lens
            return real(left, right, cid, lens, **kwargs)

        master = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'a'\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n  SELECT 'b'\n END")
        cc.compare_procs = spy
        try:
            got = classify_client_change(_proc("modified", master=master, client=client), 66)
        finally:
            cc.compare_procs = real
        self.assertEqual(seen["direction"], "client_to_105")
        self.assertEqual(seen["lens"], "active_read")
        self.assertTrue(got["list"])
        wrong = compare_procs(master, client, 66, "active_read", direction="105_to_client")
        right = compare_procs(master, client, 66, "active_read", direction="client_to_105")
        self.assertEqual(wrong["copy_side"], "master")
        self.assertEqual(right["copy_side"], "client")

    def test_a_few_hundred_active_lines_still_surface_the_one_different_line(self):
        """Trap: one changed line buried in a long active arm. Failure means a long procedure was dropped or the diff lost that line."""
        lines = [f"  SELECT {n}" for n in range(200)]
        master_lines = list(lines)
        client_lines = list(lines)
        master_lines.insert(80, "  SELECT 'NEEDLE'")
        master = _wrap(" IF @ClientActive = 66\n BEGIN\n" + "\n".join(master_lines) + "\n END")
        client = _wrap(" IF @ClientActive = 66\n BEGIN\n" + "\n".join(client_lines) + "\n END")
        self.assertLess(len(master), 2_000_000)
        got = classify_client_change(_proc("modified", master=master, client=client), 66)
        self.assertTrue(got["list"])
        self.assertEqual(got["kind"], "trimmed_diff")
        _, rich = _diff(master, client)
        blob = " ".join(_texts(rich["hunks"], "delete"))
        self.assertIn("NEEDLE", blob)


class FlaskRouteTraps(unittest.TestCase):
    def setUp(self):
        from app import RUNS, app as flask_app
        import drift.config as config

        self.client = flask_app.test_client()
        self._runs = RUNS
        self._runs.clear()
        self.run_id = "client-changes-traps"
        self.run_dir = config.OUTPUT_DIR / self.run_id
        if self.run_dir.exists():
            shutil.rmtree(self.run_dir)
        proc_dir = self.run_dir / "client_to_105" / "02_modified"
        added_dir = self.run_dir / "client_to_105" / "01_added"
        proc_dir.mkdir(parents=True)
        added_dir.mkdir(parents=True)
        master = _wrap(
            " IF @ClientActive = 66\n BEGIN\n  SELECT 'arm'\n  SELECT 'b'\n  SELECT 'mid'\n END\n"
            " ELSE\n BEGIN\n  SELECT 'else-secret'\n END",
            "zz_keep",
        )
        client = _wrap(
            " IF @ClientActive = 66\n BEGIN\n  SELECT 'arm'\n  SELECT 'mid'\n  SELECT 'extra'\n END\n"
            " ELSE\n BEGIN\n  SELECT 'else-other'\n END",
            "zz_keep",
        )
        findings = [
            {"id": "proc1", "type": PROC, "role": "modified", "category": "structural",
             "name": "dbo.zz_keep", "bare_name": "zz_keep", "path": "02_modified/zz_keep"},
            {"id": "added1", "type": PROC, "role": "added", "category": "structural",
             "name": "dbo.zz_new", "bare_name": "zz_new", "path": "01_added/zz_new"},
            {"id": "tbl1", "type": TABLE, "role": "modified", "category": "structural",
             "name": "dbo.Orders", "bare_name": "Orders", "path": "02_modified/Orders"},
        ]
        (self.run_dir / "meta.json").write_text(
            json.dumps({"directions": ["client_to_105"], "client_active_id": None}),
            encoding="utf-8",
        )
        (self.run_dir / "client_to_105" / "index.json").write_text(
            json.dumps({"findings": findings}), encoding="utf-8")
        base = proc_dir / "zz_keep"
        Path(str(base) + ".master.sql").write_text(master, encoding="utf-8")
        Path(str(base) + ".client.sql").write_text(client, encoding="utf-8")
        Path(str(added_dir / "zz_new") + ".client.sql").write_text(
            "CREATE PROCEDURE dbo.zz_new AS SELECT 1", encoding="utf-8")
        Path(str(proc_dir / "Orders") + ".master.sql").write_text(
            "CREATE TABLE dbo.Orders(SECRET_MASTER int)", encoding="utf-8")
        self._runs.clear()

    def tearDown(self):
        self._runs.clear()
        if self.run_dir.exists():
            shutil.rmtree(self.run_dir)

    def test_list_route_does_not_echo_definitions(self):
        """Trap: the list payload includes master_def, client_def, or the on-disk SECRET_MASTER token. Failure means procedure text leaked into the name list."""
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes",
            json={"client_active_id": 66},
        )
        self.assertEqual(res.status_code, 200)
        raw = res.get_data(as_text=True)
        self.assertNotIn("master_def", raw)
        self.assertNotIn("client_def", raw)
        self.assertNotIn("SECRET_MASTER", raw)
        self.assertNotIn("else-secret", raw)
        for row in res.get_json()["rows"]:
            self.assertNotIn("master_def", row)
            self.assertNotIn("client_def", row)

    def test_inspect_unknown_id_and_table_id_fail_without_echoing_sql(self):
        """Trap: an unknown id or a table id is inspected. Failure means a non-procedure returned ok or echoed SECRET_MASTER."""
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes/inspect",
            json={"client_active_id": 66, "finding_ids": ["missing", "tbl1"]},
        )
        self.assertEqual(res.status_code, 200)
        body = res.get_json()
        raw = res.get_data(as_text=True)
        self.assertFalse(body["diffs"]["missing"]["ok"])
        self.assertFalse(body["diffs"]["tbl1"]["ok"])
        self.assertNotIn("master_def", body["diffs"]["tbl1"])
        self.assertNotIn("SECRET_MASTER", raw)

    def test_inspect_modified_procedure_has_hunks_header_and_no_copy_or_else(self):
        """Trap: inspect returns copy_sql, a preview of the untrimmed ELSE, or drops the ClientActive id. Failure means the route stopped using the trimmed split diff."""
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes/inspect",
            json={"client_active_id": 66, "finding_ids": ["proc1"]},
        )
        self.assertEqual(res.status_code, 200)
        diff = res.get_json()["diffs"]["proc1"]
        raw = res.get_data(as_text=True)
        self.assertTrue(diff["ok"])
        self.assertIn("66", diff["header"])
        self.assertTrue(diff["hunks"])
        self.assertIn("delete", _tags(diff["hunks"]))
        self.assertIn("insert", _tags(diff["hunks"]))
        self.assertNotIn("copy_sql", diff)
        self.assertNotIn("preview_left", diff)
        self.assertNotIn("preview_right", diff)
        self.assertNotIn("else-secret", raw)
        self.assertNotIn("else-other", raw)

    def test_inspect_added_procedure_is_added_only_with_no_hunks_or_copy(self):
        """Trap: a new procedure is given a fake side-by-side or a copy_sql payload. Failure means inspect tried to trim a one-sided object."""
        res = self.client.post(
            f"/api/run/{self.run_id}/client_changes/inspect",
            json={"client_active_id": 66, "finding_ids": ["added1"]},
        )
        diff = res.get_json()["diffs"]["added1"]
        self.assertTrue(diff["ok"])
        self.assertTrue(diff["added_only"])
        self.assertEqual(diff["hunks"], [])
        self.assertNotIn("copy_sql", diff)
