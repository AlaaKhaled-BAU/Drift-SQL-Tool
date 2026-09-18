"""ApplySession policy tests — fake errors, no live DB.

Run: cd apps/drift-tool && python3.13 drift/test_apply_session.py -v
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.apply_session import ApplySession, Decision  # noqa: E402


class TestApplySession(unittest.TestCase):
    def test_bind_skip_applies_to_later_same_msgno(self):
        s = ApplySession(["A", "B", "C"])
        p = s.on_error({"msgno": 2627, "msg": "dup", "sql_preview": "A"})
        self.assertTrue(p["need_decision"])
        s.decide(Decision(action="bind_skip", msgno=2627))
        auto = s.on_error({"msgno": 2627, "msg": "dup", "sql_preview": "B"})
        self.assertIsNone(auto)
        self.assertEqual(s.report[-1]["status"], "skipped")
        self.assertEqual(s.report[-1]["sql_preview"], "B")
        self.assertEqual(s.index, 2)

    def test_stop_leaves_tail_unexecuted(self):
        s = ApplySession(["A", "B", "C"])
        s.on_error({"msgno": 3602, "msg": "severe", "sql_preview": "A"})
        out = s.decide(Decision(action="stop"))
        self.assertTrue(s.stopped)
        self.assertEqual(out, {"done": True, "stopped": True, "report": s.report})
        self.assertEqual(len(s.report), 1)
        self.assertEqual(s.report[0]["status"], "stopped")
        self.assertEqual(s.index, 0)
        self.assertEqual(s.statements_remaining(), 3)
        self.assertIsNone(s.current_statement())

    def test_bind_stop_on_later_msgno_stops_without_prompt(self):
        s = ApplySession(["A", "B", "C"])
        s.on_error({"msgno": 2627, "msg": "dup", "sql_preview": "A"})
        s.decide(Decision(action="skip"))
        self.assertEqual(s.index, 1)
        s.on_error({"msgno": 999, "msg": "bad", "sql_preview": "B"})
        s.decide(Decision(action="bind_stop", msgno=999))
        self.assertTrue(s.stopped)
        self.assertEqual(s.report[-1]["decision"], "bind_stop")

    def test_feed_result_ok_advances(self):
        s = ApplySession(["SELECT 1", "SELECT 2"])
        self.assertIsNone(s.feed_result({"status": "ok", "class": "ok"}))
        self.assertEqual(s.index, 1)
        self.assertEqual(s.report[0]["status"], "ok")

    def test_feed_result_benign_prompts_not_auto_skip(self):
        """Executor may classify duplicate_key as benign; apply still pauses."""
        s = ApplySession(["INSERT dup"])
        p = s.feed_result({
            "status": "benign",
            "class": "duplicate_key",
            "msgno": 2627,
            "msg": "PK violation",
        })
        self.assertTrue(p["need_decision"])
        self.assertEqual(p["msgno"], 2627)
        s.decide(Decision(action="skip"))
        self.assertEqual(s.report[0]["status"], "skipped")
        self.assertTrue(s.done)

    def test_single_skip_continues_to_next_statement(self):
        s = ApplySession(["A", "B"])
        s.on_error({"msgno": 1, "msg": "x", "sql_preview": "A"})
        self.assertIsNone(s.decide(Decision(action="skip")))
        self.assertEqual(s.index, 1)
        self.assertEqual(s.current_statement(), "B")


if __name__ == "__main__":
    unittest.main(verbosity=2)
