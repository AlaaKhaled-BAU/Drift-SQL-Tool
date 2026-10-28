"""Regression: ISSUE-003 — one-sided databases were invisible in the UI.

Found by /qa on 2026-10-28.
Report: .gstack/qa-reports/qa-report-127-0-0-1-2026-10-28.md

The manifest already named databases present on only one side. The result
notes only counted appendix items and warnings, so the checkbox looked
like a silent success.
"""
import pathlib
import unittest


class OneSidedNotesTests(unittest.TestCase):
    def test_result_notes_name_databases_present_on_only_one_side(self):
        js = pathlib.Path("static/app.js").read_text(encoding="utf-8")
        start = js.index("function renderFullUpdateFiles")
        fn = js[start:js.index("function renderProcFilterRows")]
        self.assertIn("databases_only_on_left", fn)
        self.assertIn("databases_only_on_right", fn)
        self.assertIn("Only on the left:", fn)
        self.assertIn("Only on the right:", fn)


if __name__ == "__main__":
    unittest.main()
