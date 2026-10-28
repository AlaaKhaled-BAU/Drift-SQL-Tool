"""Full Update renderer. Fixture catalogs, no live SQL.

Alphabetical order is the wrong order: Aaa is listed before Zed, and
dbo.Caller is listed before dbo.Zee. The script has to emit the referenced
name first.
"""
import inspect
import json
import pathlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from drift.full_update import (  # noqa: E402
    capture_live_catalog,
    catalog_key_for_restore,
    render_full_update,
    render_table_type,
    write_sql_file,
)
from drift import full_update, restore  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
LEFT = json.loads((FIXTURES / "left_105_catalog.json").read_text(encoding="utf-8"))
RIGHT = json.loads((FIXTURES / "right_local_catalog.json").read_text(encoding="utf-8"))


def _type_batch(sql: str, name: str) -> str:
    marker = f"CREATE TYPE [dbo].[{name}]"
    start = sql.index(marker)
    end = sql.index("\nGO\n", start)
    return sql[start:end]


class FullUpdateRenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = render_full_update(LEFT, RIGHT)
        cls.files = cls.out["files"]
        cls.unified = cls.files["unified_full_update.sql"]
        cls.schema = cls.files["Aaa_schema.sql"]
        cls.udtt = cls.files["Aaa_udtt.sql"]
        cls.executable, _, cls.manual = cls.unified.partition("-- MANUAL")

    def test_fixture_is_an_alphabetical_trap(self):
        self.assertLess(list(LEFT["databases"]).index("Aaa"), list(LEFT["databases"]).index("Zed"))
        objects = list(LEFT["databases"]["Aaa"]["objects"])
        self.assertLess(objects.index("dbo.Caller"), objects.index("dbo.Zee"))
        self.assertLess(objects.index("dbo.V2"), objects.index("dbo.V1"))
        self.assertIn("aaa", RIGHT["databases"])
        self.assertNotIn("Aaa", RIGHT["databases"])

    def test_catalog_key_for_restore_uses_header_name(self):
        self.assertEqual(
            catalog_key_for_restore({"database_name": "Olives_BO"}, "drift_left_abc"),
            "Olives_BO",
        )
        with self.assertRaises(ValueError):
            catalog_key_for_restore({"database_name": "  "}, "drift_left_abc")

    def test_script_uses_logical_database_not_physical_name(self):
        left = {
            "server_label": "bak",
            "databases": {
                "Olives_BO": {
                    "objects": {
                        "dbo.P": {
                            "schema": "dbo",
                            "name": "P",
                            "type": "SqlProcedure",
                            "schema_bound": False,
                            "definition": "CREATE PROCEDURE [dbo].[P] AS BEGIN SELECT 1 END",
                        }
                    },
                    "dependencies": [],
                }
            },
        }
        right = {
            "server_label": "client",
            "databases": {"Olives_BO": {"objects": {}, "dependencies": []}},
        }
        blob = "\n".join(render_full_update(left, right)["files"].values())
        self.assertIn("USE [Olives_BO]", blob)
        self.assertNotIn("drift_left_", blob)
        joined = "\n".join(self.files.values())
        self.assertNotIn("drift_left_", joined)
        self.assertNotIn("USE [aaa]", joined)

    def test_table_type_recreates_the_module_it_drops(self):
        self.assertIn("IF TYPE_ID(N'[dbo].[Tvp]') IS NOT NULL DROP TYPE [dbo].[Tvp]", self.udtt)
        self.assertIn("DROP PROCEDURE [dbo].[UsesTvp]", self.udtt)
        block = _type_batch(self.udtt, "Tvp")
        self.assertEqual(block.count("PRIMARY KEY"), 1)
        self.assertIn("PRIMARY KEY ([Id], [Qty])", block)
        for line in block.splitlines():
            stripped = line.strip()
            if stripped.startswith("[Id]") or stripped.startswith("[Qty]"):
                self.assertNotIn("PRIMARY KEY", line)
        create_at = self.udtt.index("CREATE TYPE [dbo].[Tvp]")
        recreate = self.udtt.index("CREATE OR ALTER PROCEDURE [dbo].[UsesTvp]", create_at)
        self.assertLess(create_at, recreate)
        for token in ("CREATE TABLE", "ALTER TABLE"):
            found = self.udtt.find(token)
            if found != -1:
                self.assertLess(recreate, found)
        self.assertNotIn("CREATE TABLE", self.udtt)
        self.assertNotIn("ALTER TABLE", self.udtt)
        unified_recreate = self.unified.index(
            "CREATE OR ALTER PROCEDURE [dbo].[UsesTvp]",
            self.unified.index("CREATE TYPE [dbo].[Tvp]"),
        )
        self.assertLess(unified_recreate, self.unified.index("CREATE TABLE"))

    def test_three_column_key_is_one_constraint_and_no_key_type_has_none(self):
        three = _type_batch(self.udtt, "ThreeKey")
        self.assertEqual(three.count("PRIMARY KEY"), 1)
        self.assertIn("PRIMARY KEY ([A], [B], [C])", three)
        for line in three.splitlines():
            stripped = line.strip()
            if stripped.startswith("[A]") or stripped.startswith("[B]") or stripped.startswith("[C]"):
                self.assertNotIn("PRIMARY KEY", line)
        self.assertNotIn("PRIMARY KEY", _type_batch(self.udtt, "NoKey"))
        direct = render_table_type(
            "dbo",
            "ThreeKey",
            [
                {"name": "A", "type": "int", "max_length": 4, "precision": 10, "scale": 0,
                 "nullable": False, "key_ordinal": 1},
                {"name": "B", "type": "int", "max_length": 4, "precision": 10, "scale": 0,
                 "nullable": False, "key_ordinal": 2},
                {"name": "C", "type": "int", "max_length": 4, "precision": 10, "scale": 0,
                 "nullable": False, "key_ordinal": 3},
            ],
            False,
        )
        self.assertEqual(direct.count("PRIMARY KEY"), 1)
        self.assertNotIn("PRIMARY KEY", render_table_type(
            "dbo", "NoKey",
            [{"name": "Id", "type": "int", "max_length": 4, "precision": 10, "scale": 0,
              "nullable": False}],
            False,
        ))

    def test_excluded_and_schema_bound_referencers_skip_the_type(self):
        blob = "\n".join(self.files.values())
        self.assertNotRegex(blob, r"DROP\s+TYPE\s+\[dbo\]\.\[TvpBound\]")
        self.assertNotRegex(blob, r"DROP\s+TYPE\s+\[dbo\]\.\[TvpExcluded\]")
        self.assertNotRegex(blob, r"(?i)\bDROP\s+(PROCEDURE|FUNCTION|VIEW|TRIGGER)\s+\[dbo\]\.\[alpha_hide\]")
        self.assertNotRegex(blob, r"DROP\s+PROCEDURE\s+\[dbo\]\.\[BoundProc\]")
        for label in ("TvpBound", "TvpExcluded"):
            self.assertRegex(blob, rf"SKIP[^\n]*\[dbo\]\.\[{label}\]")
        for line in blob.splitlines():
            if line.strip().startswith("--"):
                continue
            self.assertNotRegex(line, r"(?i)\bDROP\b.*alpha_hide")

    def test_rules_override_skips_the_type_drop(self):
        out = render_full_update(LEFT, RIGHT, [{"op": "contains", "value": "uses"}])
        blob = "\n".join(out["files"].values())
        self.assertNotIn("DROP TYPE [dbo].[Tvp]", blob)
        self.assertNotIn("CREATE TYPE [dbo].[Tvp]", blob)
        self.assertRegex(blob, r"SKIP[^\n]*\[dbo\]\.\[Tvp\]")

    def test_schema_file_keeps_nvarchar_length_and_omits_type_ddl(self):
        self.assertIn("KeepMe", self.schema)
        self.assertEqual(self.schema.count("PROCEDURE [dbo].[KeepMe]"), 1)
        self.assertNotIn("[dbo].[keepme]", self.schema)
        self.assertIn("nvarchar(20)", self.schema)
        self.assertNotIn("nvarchar(40)", self.schema)
        self.assertNotRegex(self.schema, r"(?i)\bnvarchar\b(?!\s*\()")
        self.assertNotIn("CREATE TYPE", self.schema)
        self.assertNotIn("DROP TYPE", self.schema)
        self.assertNotIn("[dbo].[Wrap]", self.schema)
        self.assertNotIn("UsesTvp", self.schema)

    def test_select_star_view_is_reemitted_after_column_add(self):
        schema_at = self.unified.index("CREATE SCHEMA [t]\nGO\n")
        self.assertTrue(self.unified[:schema_at].endswith("GO\n"))
        wrap_at = self.unified.index("[t].[Wrap]")
        name_at = self.unified.index("ALTER TABLE [dbo].[Parent] ADD [Name]")
        self.assertLess(schema_at, wrap_at)
        self.assertLess(name_at, wrap_at)
        self.assertIn("SELECT *", self.unified[wrap_at:wrap_at + 200])
        self.assertIn("[t].[Wrap]", self.schema)

    def test_not_null_without_default_and_identity_add_stay_manual(self):
        self.assertIn("-- MANUAL", self.unified)
        flag = None
        for chunk in self.executable.split("GO"):
            if "ALTER TABLE" in chunk and "ADD" in chunk:
                self.assertNotIn("[Code]", chunk)
                self.assertNotIn("[Seq]", chunk)
                if "[Flag]" in chunk:
                    flag = chunk
        self.assertIsNotNone(flag)
        self.assertIn("NOT NULL", flag)
        self.assertIn("DEFAULT", flag)
        self.assertIn("((0))", flag)
        self.assertIn("Code", self.manual)
        self.assertIn("Seq", self.manual)
        self.assertNotIn("[Code]", self.executable)
        self.assertNotIn("[Seq]", self.executable)
        self.assertRegex(self.executable, r"IDENTITY\s*\(\s*1\s*,\s*1\s*\)")
        self.assertIn("CREATE TABLE [dbo].[Fresh]", self.executable)

    def test_primary_key_is_add_constraint_after_foreign_key_drop(self):
        pk = self.unified.index("ADD CONSTRAINT [PK_Parent] PRIMARY KEY")
        self.assertLess(self.unified.index("ALTER TABLE [dbo].[Parent] ADD [Name]"), pk)
        self.assertLess(self.unified.index("DROP CONSTRAINT [FK_Child_Parent]"), pk)
        self.assertLess(pk, self.unified.index("ADD CONSTRAINT [FK_Child_Parent]"))
        self.assertNotIn("CREATE PRIMARY KEY", self.unified)
        self.assertNotIn("[FLAGS:", self.unified)
        self.assertIn("PRIMARY KEY CLUSTERED ([Id], [Name])", self.unified)

    def test_database_order_is_not_alphabetical(self):
        self.assertLess(self.unified.index("USE [Zed]"), self.unified.index("USE [Aaa]"))
        self.assertNotIn("USE [aaa]", self.unified)
        self.assertIn("OnlyZed", self.executable)
        self.assertIn("NeedsZed", self.executable)

    def test_absent_target_view_is_only_in_the_manual_section(self):
        self.assertNotIn("IssueMaster", self.executable)
        self.assertIn("IssueMaster", self.manual)
        self.assertNotIn("CREATE OR ALTER VIEW [dbo].[IssueMaster]", self.unified)
        self.assertNotIn("Olives_OWMS", self.executable)

    def test_function_and_view_order_is_not_alphabetical(self):
        self.assertLess(self.executable.index("[dbo].[Zee]"), self.executable.index("[dbo].[Caller]"))
        self.assertLess(self.executable.index("[dbo].[V1]"), self.executable.index("[dbo].[V2]"))

    def test_view_cycle_is_only_in_the_manual_section(self):
        self.assertNotIn("Loop1", self.executable)
        self.assertNotIn("Loop2", self.executable)
        self.assertIn("Loop1", self.manual)
        self.assertIn("Loop2", self.manual)

    def test_create_or_alter_is_not_doubled_on_second_pass(self):
        self.assertNotIn("CREATE OR ALTER OR ALTER", self.unified)
        self.assertNotIn("OR ALTER OR ALTER", self.unified)
        self.assertEqual(self.unified.count("CREATE OR ALTER PROCEDURE [dbo].[SecondPass]"), 1)
        self.assertIn("-- keep me", self.unified)
        self.assertIn("CREATE OR ALTER PROCEDURE [dbo].[Noted]", self.unified)
        self.assertNotRegex(self.unified, r"(?m)^CREATE\s+PROCEDURE\s+\[dbo\]\.\[Noted\]")

    def test_write_sql_file_writes_bom_and_crlf(self):
        text = "USE [Olives_BO]\nGO\n-- ع\n"
        path = pathlib.Path(tempfile.mkdtemp()) / "nested" / "out.sql"
        write_sql_file(path, text)
        data = path.read_bytes()
        self.assertTrue(data.startswith(b"\xef\xbb\xbf"))
        self.assertIn(b"\r\n", data)
        self.assertNotIn(b"\n", data.replace(b"\r\n", b""))
        self.assertNotIn(b"\r\r\n", data)
        self.assertIn("USE [Olives_BO]\r\n", data[3:].decode("utf-8"))
        src = inspect.getsource(write_sql_file)
        self.assertIn("write_bytes", src)
        self.assertNotIn("write_text", src)

    def test_capture_reads_referenced_database_name_once(self):
        class Recorder:
            def __init__(self):
                self.calls = []
                self.sql = []

            def __call__(self, database_name):
                self.calls.append(database_name)
                return self

            def cursor(self, *args, **kwargs):
                return self

            def execute(self, sql, *args):
                self.sql.append(sql)

            def fetchall(self):
                return []

            def close(self):
                return None

        recorder = Recorder()
        catalog = capture_live_catalog(recorder, "Olives_BO")
        self.assertEqual(recorder.calls, ["Olives_BO"])
        joined = "\n".join(recorder.sql)
        self.assertIn("referenced_database_name", joined)
        self.assertNotIn("referenced_database_id", joined)
        self.assertIn("Olives_BO", catalog["databases"])
        self.assertNotIn("password", json.dumps(catalog).casefold())

    def test_renderer_source_avoids_illegal_helpers(self):
        src = Path(full_update.__file__).read_text(encoding="utf-8")
        self.assertNotIn("livescan", src)
        self.assertNotIn("referenced_database_id", src)
        self.assertNotIn("get_index_definitions", src)
        self.assertNotIn("get_table_type_definitions", src)
        self.assertIn("order_names", src)
        self.assertIn("order_databases", src)
        self.assertIn("same_database", src)
        self.assertIn("schema_batch", src)
        self.assertIn("procedure_excluded", src)
        self.assertIn("_as_create_or_alter", src)
        self.assertIn("_rendered_type_ext", src)
        self.assertIn("trim_procedure", src)
        doc = full_update.__doc__ or ""
        self.assertIn("phase A", doc)
        self.assertIn("phase K", doc)
        self.assertIn("CREATE SCHEMA", doc)

    def test_restore_backup_returns_header_database_name(self):
        src = inspect.getsource(restore.restore_backup)
        self.assertIn("database_name", src)
        self.assertIn('header.get("DatabaseName")', src)
        self.assertIn("backup_date", src)
        self.assertIn("engine_major_version", src)

    def test_manifest_lists_exclusions_without_a_password(self):
        manifest = self.out["manifest"]
        self.assertIn("alpha_hide", json.dumps(manifest))
        self._assert_no_password(self.out)
        for text in self.files.values():
            self.assertNotIn("LocalOnly", text)
        self.assertIn("appendix", self.out)

    def test_selected_database_limits_scope(self):
        out = render_full_update(LEFT, RIGHT, database="Zed")
        self.assertIn("Zed_schema.sql", out["files"])
        self.assertIn("Zed_udtt.sql", out["files"])
        self.assertNotIn("Aaa_schema.sql", out["files"])
        unified = out["files"]["unified_full_update.sql"]
        self.assertIn("USE [Zed]", unified)
        self.assertNotIn("USE [Aaa]", unified)
        self.assertIn("OnlyZed", unified)

    def test_all_databases_flag_scripts_the_intersection(self):
        out = render_full_update(LEFT, RIGHT, database="Zed", all_databases=True)
        self.assertIn("Aaa_schema.sql", out["files"])
        self.assertIn("Zed_schema.sql", out["files"])
        unified = out["files"]["unified_full_update.sql"]
        self.assertLess(unified.index("USE [Zed]"), unified.index("USE [Aaa]"))

    def _assert_no_password(self, obj):
        if isinstance(obj, dict):
            for key, value in obj.items():
                self.assertNotEqual(str(key).casefold(), "password")
                self._assert_no_password(value)
        elif isinstance(obj, list):
            for item in obj:
                self._assert_no_password(item)


if __name__ == "__main__":
    unittest.main()
