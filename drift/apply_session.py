"""Interactive apply loop: every SQL failure pauses unless msgno is bound this session.

Apply targets the client server only (caller's responsibility). Uses
executor.run_statement for classification; this layer never auto-skips benign
msgnos — operator skip/stop/bind-by-msgno only.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

_PREVIEW_CHARS = 120


@dataclass
class Decision:
    action: str  # "skip" | "stop" | "bind_skip" | "bind_stop"
    msgno: int | None = None


def _preview_sql(sql_text: str) -> str:
    flat = " ".join(sql_text.split())
    if len(flat) <= _PREVIEW_CHARS:
        return flat
    return flat[:_PREVIEW_CHARS] + "..."


class ApplySession:
    def __init__(self, statements: list[str]):
        self.statements = statements
        self.index = 0
        self.bindings: dict[int, str] = {}  # msgno -> "skip" | "stop"
        self.report: list[dict[str, Any]] = []
        self.stopped = False
        self._pending: dict[str, Any] | None = None

    @property
    def done(self) -> bool:
        return self.stopped or self.index >= len(self.statements)

    def current_statement(self) -> str | None:
        if self.done:
            return None
        return self.statements[self.index]

    def statements_remaining(self) -> int:
        if self.stopped:
            return max(0, len(self.statements) - self.index)
        return max(0, len(self.statements) - self.index)

    def feed_result(self, result: dict[str, Any], sql_preview: str | None = None) -> dict[str, Any] | None:
        """After run_statement. Ok advances; any non-ok prompts or applies a binding."""
        preview = sql_preview if sql_preview is not None else _preview_sql(self.statements[self.index])
        if result.get("status") == "ok":
            self.report.append({
                "index": self.index,
                "sql_preview": preview,
                "status": "ok",
                "msgno": 0,
                "msg": "",
                "class": result.get("class", "ok"),
            })
            self.index += 1
            return None
        return self.on_error({
            "msgno": result.get("msgno", 0),
            "msg": result.get("msg", ""),
            "sql_preview": preview,
            "class": result.get("class", "fatal"),
        })

    def on_error(self, error: dict[str, Any]) -> dict[str, Any] | None:
        """Record a failed statement (or feed_result delegate). Bound msgnos auto-apply."""
        if self.stopped:
            return {"done": True, "stopped": True, "report": self.report}

        msgno = int(error.get("msgno") or 0)
        preview = error.get("sql_preview") or _preview_sql(self.statements[self.index])
        msg = error.get("msg", "")

        bound = self.bindings.get(msgno)
        if bound == "skip":
            self._record(self.index, preview, "skipped", msgno, msg, decision="bound_skip")
            self.index += 1
            return None
        if bound == "stop":
            self._record(self.index, preview, "stopped", msgno, msg, decision="bound_stop")
            self.stopped = True
            return {"done": True, "stopped": True, "report": self.report}

        self._pending = {
            "msgno": msgno,
            "msg": msg,
            "sql_preview": preview,
            "index": self.index,
            "class": error.get("class", "fatal"),
        }
        return {
            "need_decision": True,
            "msgno": msgno,
            "msg": msg,
            "sql_preview": preview,
            "index": self.index,
        }

    def decide(self, decision: Decision) -> dict[str, Any] | None:
        if self._pending is None:
            raise ValueError("no pending error awaiting decision")

        msgno = self._pending["msgno"]
        if decision.msgno is not None:
            msgno = int(decision.msgno)
        preview = self._pending["sql_preview"]
        msg = self._pending["msg"]
        idx = self._pending["index"]

        action = decision.action
        if action == "skip":
            self._record(idx, preview, "skipped", msgno, msg, decision="skip")
            self.index = idx + 1
        elif action == "stop":
            self._record(idx, preview, "stopped", msgno, msg, decision="stop")
            self.stopped = True
        elif action == "bind_skip":
            self.bindings[msgno] = "skip"
            self._record(idx, preview, "skipped", msgno, msg, decision="bind_skip")
            self.index = idx + 1
        elif action == "bind_stop":
            self.bindings[msgno] = "stop"
            self._record(idx, preview, "stopped", msgno, msg, decision="bind_stop")
            self.stopped = True
        else:
            raise ValueError(f"unknown decision action: {action!r}")

        self._pending = None
        if self.stopped:
            return {"done": True, "stopped": True, "report": self.report}
        if self.index >= len(self.statements):
            return {"done": True, "report": self.report}
        return None

    def _record(
        self,
        index: int,
        preview: str,
        status: str,
        msgno: int,
        msg: str,
        *,
        decision: str | None = None,
    ) -> None:
        entry: dict[str, Any] = {
            "index": index,
            "sql_preview": preview,
            "status": status,
            "msgno": msgno,
            "msg": msg,
        }
        if decision is not None:
            entry["decision"] = decision
        self.report.append(entry)
