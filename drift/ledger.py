"""Append-only JSONL ledger of everything we applied to a client (PLAN-V4 B.6).

Closes requirement #1: "what did we apply on client X on date Y". Every
update run appends one line per artifact it produced/acted on (apply
manifest, execution report, webpage manifest). The NEXT update against
the same client reads the last entry as its baseline, so "changed since
last time" becomes a filter over the current comparison instead of tribal
memory. It also finally gives the 3-way lost-fix question ("the client
once had a fix that is now absent -- was that ours to keep?") a data
source instead of an argument.

Design constraints:
  - Append-only JSONL: one JSON object per line. Crashes mid-run leave a
    truncated last line at worst; earlier lines stay readable. No rewrite,
    no lock file, no corruption amplification.
  - Functions read the MODULE-GLOBAL LEDGER_FILE at call time, never a
    captured copy -- so tests can rebind `ledger.LEDGER_FILE` to a tmp
    path and every function follows without reimport tricks.
  - Corrupt lines are skipped with a printed note, never raised: a single
    bad hand-edited or truncated line must not make the whole history
    unreadable (house rule: noise is surfaced, but never fatal).
"""
import json
import uuid
from datetime import datetime, timezone

try:
    from . import config
except ImportError:  # allows `python3.13 test_ledger.py` to run standalone --
    import config    # same plain-import fallback header as scriptgen.py etc.


# Default location lives in the gitignored work/ dir alongside every other
# run artifact (same convention as OUTPUT_DIR / .mssql_pw in config.py).
LEDGER_FILE = config.WORK_DIR / "ledger.jsonl"


def append_entry(client_id, run_id, kind: str, payload: dict) -> dict:
    """Append one entry, return it (with id/ts filled in).

    kind names the artifact class ("webpage_manifest", "execution_report",
    "apply_manifest", ...); payload carries that artifact's summary keys,
    spread flat onto the entry so `read_entries(kind=...)` consumers can
    filter/sort on payload fields directly with jq-like simplicity.
    """
    entry = {
        "id": uuid.uuid4().hex[:12],
        # UTC ISO-8601 with explicit tz: naive timestamps caused the
        # "which server wrote this?" ambiguity once already (VALIDATION.md).
        "ts": datetime.now(timezone.utc).isoformat(),
        "client_id": str(client_id),
        "run_id": run_id,
        "kind": kind,
        **payload,
    }
    # Single json.dumps per line keeps the file self-synchronizing-ish:
    # each line parses independently, so one corrupt line costs one entry.
    with open(LEDGER_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return entry


def read_entries(client_id: str | None = None, kind: str | None = None) -> list[dict]:
    """Read entries, newest-last (file order). Optional client/kind filters."""
    try:
        with open(LEDGER_FILE, encoding="utf-8") as f:
            raw_lines = f.readlines()
    except FileNotFoundError:
        return []  # no ledger yet == empty history, not an error

    out = []
    for i, line in enumerate(raw_lines):
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            # Skip-with-comment, never crash: a truncated final line (crash
            # mid-append) or a hand-mangled line must not take down reads.
            # We print rather than swallow silently so the damage is visible.
            print(f"ledger: skipping corrupt line {i + 1} in {LEDGER_FILE}")
            continue
        if client_id is not None and e.get("client_id") != client_id:
            continue
        if kind is not None and e.get("kind") != kind:
            continue
        out.append(e)
    return out


def last_for_client(client_id: str) -> dict | None:
    """Most recent entry for this client (file order), or None if never seen.

    This is the baseline hook B.7's orchestrator calls before an update:
    whatever we applied last time defines "changed since" for next time.
    """
    entries = read_entries(client_id=client_id)
    return entries[-1] if entries else None
