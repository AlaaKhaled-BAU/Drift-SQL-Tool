"""Named comparison profiles -- PLAN-V5 Lane D / blueprint C5.

A profile is a saved answer to the four questions every compare asks:
which master .bak, which client .bak, which ClientActive id scopes it,
and what the exclusion list looked like when it was saved. Analysts
repeat the same master/client pair across days and machines; typing
those paths by hand (or re-picking them in a dropdown) is exactly the
kind of tribal memory this tool exists to kill. A profile turns
"compare 105 vs client 66 again" into one name.

Storage: one JSON object mapping name -> profile dict, in the gitignored
work/ dir -- same convention as ledger.jsonl (config.WORK_DIR). Nothing
in here is secret; it just isn't source code, and work/ is already where
every other runtime artifact lives.

Design constraints (mirroring ledger.py deliberately):
  - Functions read the MODULE-GLOBAL PROFILES_FILE at CALL time, never a
    captured copy -- so tests can rebind profiles.PROFILES_FILE to a tmp
    path and every function follows without reimport tricks.
  - Missing or corrupt file -> {} + a printed comment, never raised:
    losing your saved shortcuts must not take down the whole app's
    startup or the compare route (house rule: noise surfaced, never
    fatal). Same posture as ledger.read_entries().
"""
import json

try:
    from . import config
except ImportError:  # allows `python3.13 test_profiles.py` to run standalone --
    import config    # same plain-import fallback header as ledger.py etc.


# Default location lives in the gitignored work/ dir alongside every other
# run artifact (same convention as LEDGER_FILE / OUTPUT_DIR in config.py).
PROFILES_FILE = config.WORK_DIR / "profiles.json"


def _read_profiles() -> dict:
    """Load {name: profile} from disk; {} on missing OR unparseable file.

    One shared reader so every public function has identical missing/
    corrupt behavior -- there is no code path where a bad file crashes
    a caller. We print rather than swallow silently so the damage is
    visible in server logs.
    """
    try:
        raw = PROFILES_FILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}  # no profiles yet == empty book, not an error
    except OSError as e:
        print(f"profiles: cannot read {PROFILES_FILE}: {e}")
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        # Hand-mangled or truncated file: refuse to guess at partial
        # content (unlike the ledger we can't salvage line-by-line --
        # it's ONE json object), surface it, degrade to empty.
        print(f"profiles: corrupt JSON in {PROFILES_FILE} -- ignoring saved profiles")
        return {}
    return data if isinstance(data, dict) else {}


def _write_profiles(data: dict) -> None:
    """Persist the whole map. Read-modify-write of a tiny dict file;
    last-writer-wins is fine for a single-user internal tool."""
    PROFILES_FILE.write_text(json.dumps(data, indent=1, ensure_ascii=False),
                             encoding="utf-8")


def list_profiles() -> dict:
    """All profiles keyed by name. {} when none saved yet."""
    return _read_profiles()


def save_profile(name, master_path="", client_path="", client_active_id=None,
                 exclusions_snapshot=None) -> dict:
    """Create or overwrite one profile; returns the stored record.

    Overwrite-on-same-name is deliberate: a profile is a bookmark, not
    history (the run artifacts + ledger are the history). exclusions_snapshot
    records WHAT exclusion rules were active when the profile was made --
    purely informational provenance, never auto-reapplied here.
    """
    name = str(name or "").strip()  # None/whitespace collapse to the rejection below
    if not name:
        raise ValueError("profile name must be non-empty")
    data = _read_profiles()
    record = {
        "name": name,
        "master_path": str(master_path or ""),
        "client_path": str(client_path or ""),
        # ClientActive id kept verbatim (string or int); api_compare's own
        # digit validation still gates whatever value gets used later.
        "client_active_id": client_active_id,
        "exclusions_snapshot": exclusions_snapshot,
    }
    data[name] = record
    _write_profiles(data)
    return record


def get_profile(name) -> dict | None:
    """One profile by exact name, or None if absent (or the file is
    unreadable -- same degrade-to-empty contract as list_profiles)."""
    return _read_profiles().get(str(name))


def delete_profile(name) -> bool:
    """Remove one profile; True if it existed, False if absent (or the
    store was unreadable/corrupt -- nothing deletable then)."""
    name = str(name)
    data = _read_profiles()
    if name not in data:
        return False
    del data[name]
    _write_profiles(data)
    return True
