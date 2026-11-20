"""Regression: ISSUE-004 — a failed Full Update kept the previous downloads.

Found by /qa on 2026-10-28.
Report: .gstack/qa-reports/qa-report-127-0-0-1-2026-10-28.md

The worker already logs FAILED. The stream error handler logged it again
and left the last run's file links on screen.
"""
import pathlib
import unittest


class FullUpdateErrorStateTests(unittest.TestCase):
    def test_stream_error_clears_files_and_does_not_repeat_the_log_line(self):
        js = pathlib.Path("static/app.js").read_text(encoding="utf-8")
        start = js.index("fullUpdateBtn.addEventListener")
        handler = js[start:js.index("/* end fullUpdateBtn */")]
        self.assertIn("function clearFullUpdateFiles", js)
        self.assertIn("clearFullUpdateFiles()", handler)
        self.assertIn("logEl.textContent", handler)
        self.assertIn("includes(msg)", handler)
        # File links are removed only when the error event carries a message,
        # so a normal stream close after result does not wipe a success.
        error_at = handler.index('addEventListener("error"')
        error_fn = handler[error_at:handler.index("return;", error_at)]
        self.assertLess(error_fn.index("if (e.data)"), error_fn.index("clearFullUpdateFiles()"))


if __name__ == "__main__":
    unittest.main()
