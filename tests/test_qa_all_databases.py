"""Regression: ISSUE-002 — all-databases still required a selected database.

Found by /qa on 2026-10-28.
Report: .gstack/qa-reports/qa-report-127-0-0-1-2026-10-28.md

buildSideSpec returns null when the Client dropdown is empty, so the
checkbox never reached the server and the empty-state sentence was dead.
"""
import pathlib
import unittest


class AllDatabasesPayloadTests(unittest.TestCase):
    def test_checkbox_is_read_before_the_live_database_is_required(self):
        js = pathlib.Path("static/app.js").read_text(encoding="utf-8")
        start = js.index("function buildFullUpdatePayload")
        fn = js[start:js.index("function renderFullUpdateFiles")]
        self.assertLess(fn.index("const allDatabases"), fn.index("liveConnectFields"))
        self.assertIn("!allDatabases && !fields.database", fn)
        self.assertIn(
            "Select the Client database, or check All databases on both sides.",
            fn,
        )
        # An empty live database is refused only when the checkbox is off.
        guard = fn.index("!allDatabases && !fields.database")
        message = fn.index("Select the Client database, or check All databases on both sides.")
        self.assertLess(guard, message)


if __name__ == "__main__":
    unittest.main()
