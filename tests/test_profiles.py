"""Self-check for named comparison profiles (PLAN-V5 Lane D / C5).
Run: python3.13 test_profiles.py"""
import json
import tempfile
from pathlib import Path

import profiles


def _tmp_profiles() -> Path:
    """Rebind the module-global PROFILES_FILE to a fresh tmp file.

    This rebinding is exactly why profiles.py must read PROFILES_FILE at
    CALL time, not capture it at import -- these tests would otherwise
    read/write the real work/profiles.json (and worse: see stale entries
    from real usage, or clobber them)."""
    fd = Path(tempfile.mkdtemp()) / "profiles.json"
    profiles.PROFILES_FILE = fd
    return fd


def test_save_get_list_delete_roundtrip():
    f = _tmp_profiles()
    assert profiles.list_profiles() == {}  # missing file -> {}, not crash

    saved = profiles.save_profile("acme-66", master_path="/baks/105.bak",
                                  client_path="/baks/acme.bak",
                                  client_active_id="66",
                                  exclusions_snapshot={"count": 3})
    assert saved["name"] == "acme-66" and saved["client_active_id"] == "66"
    assert f.is_file()  # actually persisted

    got = profiles.get_profile("acme-66")
    assert got == saved  # exact round-trip through disk
    assert set(profiles.list_profiles()) == {"acme-66"}

    # overwrite same name = update, not duplicate entry
    profiles.save_profile("acme-66", client_path="/baks/acme2.bak")
    assert profiles.get_profile("acme-66")["client_path"] == "/baks/acme2.bak"
    assert len(profiles.list_profiles()) == 1

    assert profiles.delete_profile("acme-66") is True
    assert profiles.get_profile("acme-66") is None
    assert profiles.list_profiles() == {}


def test_delete_missing_returns_false():
    _tmp_profiles()
    assert profiles.delete_profile("never-existed") is False
    profiles.save_profile("x")
    assert profiles.delete_profile("y") is False  # store exists, name doesn't
    assert profiles.get_profile("x") is not None  # untouched by failed delete


def test_corrupt_file_degrades_to_empty_with_comment(capsys=None):
    """Corrupt JSON -> {} + printed comment, never raised (ledger.py house
    rule: noise surfaced, never fatal) -- and a corrupt file must not stop
    save_profile from rebuilding a working store."""
    f = _tmp_profiles()
    f.write_text('{"acme": {"name": "acme", "trunc', encoding="utf-8")  # torn write
    import io, contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        assert profiles.list_profiles() == {}
        assert profiles.get_profile("acme") is None
        assert profiles.delete_profile("acme") is False
        # saving over a corrupt file recovers the store cleanly
        profiles.save_profile("fresh")
    out = buf.getvalue()
    assert "corrupt JSON" in out, out  # damage visible, not silent
    assert profiles.get_profile("fresh") is not None


def test_file_shape_is_json_object_map():
    """Contract: one JSON object {name: profile} so jq/inspection stays trivial,
    and non-dict content degrades to {} instead of exploding callers."""
    f = _tmp_profiles()
    profiles.save_profile("a", master_path="m")
    data = json.loads(f.read_text(encoding="utf-8"))
    assert isinstance(data, dict) and data["a"]["master_path"] == "m"

    f.write_text('[1, 2, 3]', encoding="utf-8")  # valid JSON, wrong shape
    assert profiles.list_profiles() == {}


def test_empty_name_rejected():
    _tmp_profiles()
    for bad in ("", "   ", None):
        try:
            profiles.save_profile(bad)
            assert False, f"expected ValueError for {bad!r}"
        except ValueError:
            pass


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
