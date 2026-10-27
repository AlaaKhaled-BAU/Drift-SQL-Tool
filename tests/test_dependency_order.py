"""Dependency order for Full Update. No live SQL.

Views and functions share one graph. Edges are (dependent, referenced):
the referenced name is emitted first. Cycles and anything that depends on
a cycle are the manual appendix (held back), not the auto order.

Alphabetical order is not proof. `dbo.Caller` sorts before `dbo.Zee`, and
`Aaa` sorts before `Zed`. Both fixtures fail if the implementation sorts.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.full_update import (  # noqa: E402
    DATABASE_CYCLE_WARNING,
    order_databases,
    order_names,
    same_database,
    schema_batch,
    schema_object_order,
    split_absent_targets,
)


class DependencyOrderTests(unittest.TestCase):
    def test_referenced_object_first(self):
        # sorted() also yields T then V. This fixture does not catch an
        # alphabetical implementation; the Caller/Zee and A/M/Z tests do.
        order, held = order_names(["V", "T"], [("V", "T")])
        self.assertEqual(held, [])
        self.assertLess(order.index("T"), order.index("V"))

    def test_cycle_is_removed_from_executable_order(self):
        order, held = order_names(["A", "B", "C"], [("A", "B"), ("B", "A")])
        self.assertEqual(held, ["A", "B"])
        self.assertEqual(order, ["C"])
        self.assertNotIn("A", order)
        self.assertNotIn("B", order)

    def test_dependent_of_a_cycle_is_held_back_too(self):
        order, held = order_names(
            ["A", "B", "D"],
            [("A", "B"), ("B", "A"), ("D", "A")],
        )
        self.assertEqual(set(held), {"A", "B", "D"})
        self.assertEqual(order, [])
        for name in ("A", "B", "D"):
            self.assertIn(name, held)
            self.assertNotIn(name, order)

    def test_transitive_dependent_of_a_cycle_is_appendix(self):
        order, held = order_names(
            ["A", "B", "E", "D"],
            [("A", "B"), ("B", "A"), ("E", "A"), ("D", "E")],
        )
        self.assertEqual(order, [])
        self.assertEqual(held, ["A", "B", "E", "D"])

    def test_cycle_prerequisite_stays_auto(self):
        # A depends on C, and A cycles with B. C does not depend on the cycle.
        order, held = order_names(
            ["A", "B", "C"],
            [("A", "B"), ("B", "A"), ("A", "C")],
        )
        self.assertEqual(order, ["C"])
        self.assertEqual(set(held), {"A", "B"})
        self.assertNotIn("C", held)

    def test_edge_to_a_name_outside_the_list_is_ignored(self):
        # Tables are created in an earlier phase and are not in this graph.
        order, held = order_names(["dbo.V"], [("dbo.V", "dbo.Parent")])
        self.assertEqual(order, ["dbo.V"])
        self.assertEqual(held, [])

    def test_callee_before_caller_even_when_caller_sorts_first(self):
        names = ["dbo.Caller", "dbo.Zee"]
        order, held = order_names(names, [("dbo.Caller", "dbo.Zee")])
        self.assertEqual(held, [])
        self.assertEqual(sorted(names), ["dbo.Caller", "dbo.Zee"])
        self.assertNotEqual(order, sorted(names))
        self.assertLess(order.index("dbo.Zee"), order.index("dbo.Caller"))

    def test_views_and_functions_share_one_graph(self):
        # dbo.Agg (function) sorts before dbo.ZeeView. One graph emits the view first.
        names = ["dbo.Agg", "dbo.ZeeView"]
        order, held = order_names(names, [("dbo.Agg", "dbo.ZeeView")])
        self.assertEqual(held, [])
        self.assertEqual(order, ["dbo.ZeeView", "dbo.Agg"])
        self.assertNotEqual(order, sorted(names))

    def test_order_is_not_alphabetical_or_reversed(self):
        names = ["A", "M", "Z"]
        order, held = order_names(names, [("A", "M"), ("Z", "A")])
        self.assertEqual(held, [])
        self.assertLess(order.index("M"), order.index("A"))
        self.assertLess(order.index("A"), order.index("Z"))
        self.assertNotEqual(order, sorted(names))
        self.assertNotEqual(order, list(reversed(sorted(names))))

    def test_alphabetical_sort_must_fail(self):
        """No edges. sorted() returns A, M, Z and must not be the result."""
        names = ["Z", "M", "A"]
        order, held = order_names(names, [])
        self.assertEqual(held, [])
        self.assertEqual(order, ["Z", "M", "A"])
        self.assertNotEqual(order, sorted(names))

    def test_ready_nodes_keep_input_order(self):
        order, held = order_names(["C", "B", "A"], [("A", "B")])
        self.assertEqual(held, [])
        self.assertEqual(order, ["C", "B", "A"])
        self.assertNotEqual(order, sorted(["C", "B", "A"]))

    def test_cross_database_order_is_not_alphabetical(self):
        names = ["Aaa", "Zed"]
        order, warnings = order_databases(names, [("Aaa", "Zed")])
        self.assertEqual(warnings, [])
        self.assertLess(order.index("Zed"), order.index("Aaa"))
        self.assertNotEqual(order, sorted(names))

    def test_databases_without_edges_keep_input_order(self):
        names = ["Zed", "Aaa"]
        order, warnings = order_databases(names, [])
        self.assertEqual(warnings, [])
        self.assertEqual(order, ["Zed", "Aaa"])
        self.assertNotEqual(order, sorted(names))

    def test_database_cycle_falls_back_to_casefold_and_one_warning(self):
        order, warnings = order_databases(
            ["Zed", "Aaa"],
            [("Aaa", "Zed"), ("Zed", "Aaa")],
        )
        self.assertEqual(order, ["Aaa", "Zed"])
        self.assertEqual(warnings, [DATABASE_CYCLE_WARNING])
        self.assertNotIn("\n", DATABASE_CYCLE_WARNING)

    def test_database_cycle_keeps_acyclic_referenced_database_first(self):
        # Aaa references Zed, so Zed stays first. Foo and Bar cycle.
        # Casefold of the whole list would put Aaa before Zed.
        names = ["Aaa", "Zed", "Foo", "Bar", "Mmm"]
        order, warnings = order_databases(
            names,
            [("Aaa", "Zed"), ("Foo", "Bar"), ("Bar", "Foo")],
        )
        self.assertEqual(warnings, [DATABASE_CYCLE_WARNING])
        self.assertEqual(order, ["Zed", "Aaa", "Mmm", "Bar", "Foo"])
        self.assertLess(order.index("Zed"), order.index("Aaa"))
        self.assertNotEqual(order, sorted(names, key=str.casefold))

    def test_same_database_casefold(self):
        self.assertTrue(same_database("olives_BO", "Olives_BO"))
        self.assertTrue(same_database("Aaa", "aaa"))
        self.assertTrue(same_database(None, "Olives_BO"))
        self.assertTrue(same_database("", "Olives_BO"))
        self.assertFalse(same_database("Olives_OWMS", "Olives_BO"))

    def test_absent_target_database_goes_to_the_appendix(self):
        objects = [
            {"name": "dbo.SameCase", "type": "SqlView"},
            {"name": "dbo.IssueMaster", "type": "SqlView"},
            {"name": "dbo.NeedsZed", "type": "SqlProcedure"},
            {"name": "dbo.FnNeedsMissing", "type": "SqlScalarFunction"},
            {"name": "dbo.PresentOther", "type": "SqlView"},
            {"name": "dbo.TrigNeedsMissing", "type": "SqlDmlTrigger"},
            {"name": "dbo.Mixed", "type": "SqlInlineTableValuedFunction"},
        ]
        dependencies = [
            {"from": "dbo.SameCase", "referenced_database_name": "olives_BO"},
            {"from": "dbo.IssueMaster", "referenced_database_name": "Olives_OWMS"},
            {"from": "dbo.NeedsZed", "referenced_database_name": "NotOnRight"},
            {"from": "dbo.FnNeedsMissing", "referenced_database_name": "MissingDb"},
            {"from": "dbo.PresentOther", "referenced_database_name": "zed"},
            {"from": "dbo.TrigNeedsMissing", "referenced_database_name": "MissingDb"},
            {"from": "dbo.Mixed", "referenced_database_name": "olives_BO"},
            {"from": "dbo.Mixed", "referenced_database_name": "MissingDb"},
        ]
        # Olives_BO is the database being scripted and is absent from this
        # present list on purpose. olives_BO still matches it by casefold.
        auto, appendix = split_absent_targets(
            objects,
            dependencies,
            "Olives_BO",
            ["Zed"],
        )
        self.assertEqual(
            auto,
            ["dbo.SameCase", "dbo.NeedsZed", "dbo.PresentOther"],
        )
        self.assertEqual(
            appendix,
            ["dbo.IssueMaster", "dbo.FnNeedsMissing", "dbo.TrigNeedsMissing", "dbo.Mixed"],
        )
        for name in appendix:
            self.assertNotIn(name, auto)

    def test_schema_batch_is_only_create_schema(self):
        text = schema_batch("t")
        self.assertEqual(text, "CREATE SCHEMA [t]\nGO\n")
        self.assertNotIn("CREATE TABLE", text)
        self.assertNotIn("CREATE TYPE", text)
        self.assertNotIn("DROP", text)

    def test_schema_batch_before_object_that_needs_that_schema(self):
        # z before t is not alphabetical. dbo gets no CREATE SCHEMA.
        names = ["dbo.Parent", "z.Late", "t.Wrap"]
        batches = schema_object_order(names)
        schemas = [batch for batch in batches if batch["kind"] == "schema"]
        objects = [batch for batch in batches if batch["kind"] == "object"]
        schema_names = [batch["schema"] for batch in schemas]
        self.assertEqual(schema_names, ["z", "t"])
        self.assertNotEqual(schema_names, sorted(schema_names))
        self.assertFalse(any(batch["schema"].casefold() == "dbo" for batch in schemas))
        self.assertEqual([batch["name"] for batch in objects], names)
        self.assertLess(
            max(index for index, batch in enumerate(batches) if batch["kind"] == "schema"),
            min(index for index, batch in enumerate(batches) if batch["kind"] == "object"),
        )
        t_schema = next(
            index for index, batch in enumerate(batches)
            if batch["kind"] == "schema" and batch["schema"] == "t"
        )
        t_object = next(
            index for index, batch in enumerate(batches)
            if batch["kind"] == "object" and batch["name"] == "t.Wrap"
        )
        self.assertLess(t_schema, t_object)
        self.assertEqual(batches[t_schema]["batch"], schema_batch("t"))
        self.assertEqual(batches[t_schema]["batch"], "CREATE SCHEMA [t]\nGO\n")
        self.assertNotIn("DROP", batches[t_schema]["batch"])
        self.assertNotIn("CREATE TABLE", batches[t_schema]["batch"])

    def test_schema_batch_once_for_casefold_match(self):
        batches = schema_object_order(["t.A", "T.B"])
        schemas = [batch for batch in batches if batch["kind"] == "schema"]
        self.assertEqual(len(schemas), 1)
        self.assertEqual(schemas[0]["schema"], "t")
        self.assertEqual(schemas[0]["batch"], schema_batch("t"))
        self.assertLess(
            0,
            next(index for index, batch in enumerate(batches) if batch.get("name") == "t.A"),
        )


if __name__ == "__main__":
    unittest.main()
