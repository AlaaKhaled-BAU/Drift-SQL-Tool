"""Regression: ISSUE-005 — Escape left the procedures filter open.

Found by /qa on 2026-10-28.
Report: .gstack/qa-reports/qa-report-127-0-0-1-2026-10-28.md

The dialog is aria-modal. Escape now hides it the same way Close does,
without fetching a new token list. Reopening still loads the shipped defaults.
"""
import pathlib
import unittest


class ProcFilterEscapeTests(unittest.TestCase):
    def test_escape_hides_the_dialog_without_resetting_rules(self):
        js = pathlib.Path("static/app.js").read_text(encoding="utf-8")
        start = js.index('document.addEventListener("keydown"')
        handler = js[start:js.index("procFilterContainsBtn")]
        self.assertIn('event.key !== "Escape"', handler)
        self.assertIn("dialog.hidden = true", handler)
        self.assertNotIn("procedure_filter/defaults", handler)


if __name__ == "__main__":
    unittest.main()
