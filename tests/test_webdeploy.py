"""Self-check for file-level web deploy (PLAN-V4 B.5). Run: python3.13 test_webdeploy.py"""
import os
import tempfile
from pathlib import Path

import webdeploy


def _tree(files: dict[str, bytes]) -> Path:
    """Materialize {relpath: content} under a fresh tmp root; returns the root."""
    root = Path(tempfile.mkdtemp())
    for rel, data in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    return root


def test_hash_tree_stable_across_reread():
    """Same bytes -> same hashes on every reread; that stability IS the
    manifest's correctness (a re-run must not invent phantom updates)."""
    root = _tree({"Olives/a.aspx": b"<% page %>", "srv/bin/x.dll": b"MZ"})
    h1 = webdeploy.hash_tree(root)
    h2 = webdeploy.hash_tree(root)
    assert h1 == h2 and set(h1) == {"Olives/a.aspx", "srv/bin/x.dll"}, h1
    assert all(len(v) == 64 for v in h1.values())  # sha256 hex


def test_hash_changes_when_bytes_change():
    root = _tree({"a.js": b"v1"})
    before = webdeploy.hash_tree(root)["a.js"]
    (root / "a.js").write_bytes(b"v2")
    after = webdeploy.hash_tree(root)["a.js"]
    assert before != after  # content-keyed, not name/timestamp-keyed


def test_ext_filter():
    root = _tree({"p.aspx": b"1", "b.dll": b"2", "app.js": b"3", "notes.txt": b"4"})
    h = webdeploy.hash_tree(root, exts={".aspx", ".js"})
    assert set(h) == {"p.aspx", "app.js"}, h
    assert set(webdeploy.hash_tree(root)) == {"p.aspx", "b.dll", "app.js", "notes.txt"}  # None=all


def test_hidden_and_sidecar_skipped():
    """.svn/.git junk and OUR OWN *.bak_<epoch> sidecars are not client content:
    hashing them would turn yesterday's rollback copies into today's drift."""
    root = _tree({
        "a.aspx": b"x",
        ".hidden.aspx": b"h",          # hidden FILE
        ".svn/wat.aspx": b"s",         # hidden DIR contents never walked
        "a.aspx.bak_1719999999": b"z",  # apply_copy()'s own sidecar shape
    })
    assert set(webdeploy.hash_tree(root)) == {"a.aspx"}, webdeploy.hash_tree(root)


def test_manifest_detects_add_update_delete():
    src = _tree({"a.aspx": b"NEW", "b.js": b"brand new"})   # update + add
    dst_root = _tree({"a.aspx": b"OLD", "c.dll": b"stale"})  # differs + orphaned
    m = webdeploy.build_manifest(src, dst_root)
    assert m["copy"] == ["a.aspx", "b.js"], m      # add and update share one key
    assert m["delete"] == ["c.dll"], m             # present in dst, absent from src


def test_manifest_with_missing_dst_everything_is_copy():
    """dst_root doesn't exist yet (fresh box): nothing to diff against, so
    every src file is a copy and delete is trivially empty -- no crash."""
    src = _tree({"x.aspx": b"1"})
    m = webdeploy.build_manifest(src, Path(tempfile.mkdtemp()) / "not_yet")
    assert m["copy"] == ["x.aspx"] and m["delete"] == [], m


def test_apply_copy_copies_and_backs_up_existing():
    src = _tree({"a.aspx": b"NEW", "deep/dir/x.js": b"js"})
    dst = _tree({"a.aspx": b"OLD"})                # pre-existing -> needs backup
    m = webdeploy.build_manifest(src, dst)
    r = webdeploy.apply_copy(m, src, dst)
    assert r["copied"] == 2 and r["backed_up"] == 1 and r["errors"] == [], r
    assert (dst / "a.aspx").read_bytes() == b"NEW"
    assert (dst / "deep/dir/x.js").read_bytes() == b"js"   # parents auto-created
    sidecars = list(dst.glob("a.aspx.bak_*"))
    assert len(sidecars) == 1 and sidecars[0].read_bytes() == b"OLD"  # real rollback path


def test_delete_blocked_by_default_then_opt_in():
    """Deletes are DDL-drop-grade dangerous here too: default OFF, and the
    block is VISIBLE in errors[] -- silence would hide a stale-file report."""
    src = _tree({"keep.aspx": b"k"})
    dst = _tree({"keep.aspx": b"k", "old.dll": b"o"})
    m = webdeploy.build_manifest(src, dst)
    r_off = webdeploy.apply_copy(m, src, dst)                       # allow_delete defaults False
    assert r_off["deleted"] == 0 and (dst / "old.dll").exists()
    assert any("blocked" in e for e in r_off["errors"]), r_off     # refusal is reported
    r_on = webdeploy.apply_copy(m, src, dst, allow_delete=True)
    assert r_on["deleted"] == 1 and not (dst / "old.dll").exists() and r_on["errors"] == []


def test_robocopy_text_has_dryrun_marker_and_every_copy():
    """Field operators get a script whose FIRST action previews with /L --
    they must be able to see scope before anything moves."""
    src = _tree({"Olives/p.aspx": b"1", "Olives/s/q.js": b"2"})
    m = {"copy": ["Olives/p.aspx", "Olives/s/q.js"], "delete": []}
    text = webdeploy.emit_robocopy(m, src, Path(r"C:\inetpub\client"))
    lines = text.split("\n")
    dry = [l for l in lines if "/L" in l]
    assert dry, text                                    # dry-run line present...
    assert lines.index(dry[0]) < min(i for i, l in enumerate(lines)
                                     if "robocopy" in l and "/L" not in l)  # ...and FIRST
    for rel in m["copy"]:
        assert rel.replace("/", "\\") in text or rel in text, f"{rel} missing from:\n{text}"
    assert "echo [" in text                             # progress markers per file
    assert "\n".join(lines) == text                     # deterministic join, contract shape


def test_symlink_dir_outside_root_skipped_not_followed():
    """A symlinked dir pointing OUTSIDE the tree must not leak its files into
    the manifest (that's how a stray /etc link becomes an accidental deploy).
    Skipped gracefully where the platform/filesystem denies symlink creation."""
    try:
        outside = _tree({"secret.txt": b"S"})
        root = _tree({"real.aspx": b"R"})
        os.symlink(outside, root / "linked")            # dir symlink -> outside root
    except (OSError, NotImplementedError):
        print("SKIP test_symlink_dir_outside_root_skipped_not_followed "
              "(platform denied symlink creation)")
        return
    h = webdeploy.hash_tree(root)
    assert set(h) == {"real.aspx"}, h                   # secret.txt NOT followed in


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
