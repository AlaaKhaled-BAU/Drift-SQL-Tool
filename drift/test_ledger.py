"""Self-check for the append-only ledger (PLAN-V4 B.6). Run: python3.13 test_ledger.py"""
import json
import tempfile
from pathlib import Path

import ledger


def _tmp_ledger() -> Path:
    """Rebind the module-global LEDGER_FILE to a fresh tmp file.

    This rebinding is exactly why ledger.py must read LEDGER_FILE at CALL
    time, not capture it at import -- these tests would otherwise write
    into the real work/ dir (and worse: see stale entries from real runs).
    """
    fd = Path(tempfile.mkdtemp()) / "ledger.jsonl"
    ledger.LEDGER_FILE = fd
    return fd


def test_append_then_read_roundtrip():
    _tmp_ledger()
    e = ledger.append_entry(105, "run_abc", "webpage_manifest", {"files": 3})
    assert e["id"] and len(e["id"]) == 12, e
    assert e["client_id"] == "105"  # str()-ed per contract
    assert "T" in e["ts"]  # ISO with tz marker
    got = ledger.read_entries()
    assert len(got) == 1 and got[0] == e
    assert got[0]["files"] == 3  # payload spread flat onto entry


def test_filters_by_client_and_kind():
    _tmp_ledger()
    ledger.append_entry("105", "r1", "webpage_manifest", {"n": 1})
    ledger.append_entry("205", "r2", "execution_report", {"n": 2})
    ledger.append_entry("105", "r3", "execution_report", {"n": 3})
    assert [e["n"] for e in ledger.read_entries(client_id="105")] == [1, 3]
    assert [e["n"] for e in ledger.read_entries(kind="execution_report")] == [2, 3]
    assert [e["n"] for e in ledger.read_entries(client_id="105", kind="webpage_manifest")] == [1]
    assert ledger.read_entries(client_id="999") == []


def test_last_for_client():
    _tmp_ledger()
    assert ledger.last_for_client("105") is None  # empty history -> None, not crash
    ledger.append_entry("105", "r1", "apply_manifest", {"seq": 1})
    ledger.append_entry("205", "r2", "apply_manifest", {"seq": 2})
    last = ledger.append_entry("105", "r3", "apply_manifest", {"seq": 3})
    assert ledger.last_for_client("105")["seq"] == 3  # most recent for THAT client
    assert ledger.last_for_client("205")["seq"] == 2
    assert ledger.last_for_client("404") is None


def test_corrupt_line_skipped_with_comment_not_crash():
    """One truncated line (crash mid-append) or hand-mangled line must not
    make the whole history unreadable -- skipped with a printed note."""
    f = _tmp_ledger()
    ledger.append_entry("105", "r1", "kind_a", {"ok": True})
    with open(f, "a") as fh:
        fh.write('{"client_id": "105", "trunc')  # simulate torn final line
        fh.write("\nnot json at all\n")
    ledger.append_entry("105", "r2", "kind_a", {"ok": False})
    got = ledger.read_entries(client_id="105")
    assert {g["run_id"] for g in got} == {"r1", "r2"}, got


def test_empty_and_missing_file_read_empty():
    f = _tmp_ledger()
    assert ledger.read_entries() == []
    f.write_text("")  # zero-byte file exists but has no entries
    assert ledger.read_entries() == []
    assert ledger.last_for_client("x") is None


def test_file_is_single_json_lines():
    """Contract: one JSON object per line, appended not rewritten -- a later
    reader (jq, tail -1) can consume the file without our module."""
    f = _tmp_ledger()
    ledger.append_entry("1", "a", "k", {})
    ledger.append_entry("2", "b", "k", {})
    lines = f.read_text().splitlines()
    assert len(lines) == 2 and all(json.loads(l) for l in lines)


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
