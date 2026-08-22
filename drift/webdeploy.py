"""File-level webpage deploy for IIS boxes (PLAN-V4 B.5).

The web side of a client update is a plain file tree (`olives web pages/
{Olives,srv}`: .aspx pages, compiled .dll/.bin, .js). Unlike the SQL half,
there is no schema to diff -- the honest unit is the FILE, keyed by
SHA-256 of its bytes. This module answers three questions and acts on two:

  hash_tree()     -- what exists where, by content hash
  build_manifest()--- what would change (copy = add-or-update, delete)
  emit_robocopy() -- hand the field a Windows script they can run + preview
  apply_copy()    -- or do it ourselves with .bak_<epoch> sidecar backups

Safety posture, mirroring app.py's containment discipline:
  - roots are resolved once; any entry whose real path escapes the root
    is skipped (symlink-escape guard -- resolve() follows links, so the
    check runs on the target, exactly like /api/run/<id>/file).
  - directory symlinks pointing OUTSIDE the root are pruned, not followed.
  - hidden entries (.svn, .git, web.config backups) and our own *.bak_*
    sidecars are never hashed/manifested -- otherwise yesterday's backup
    would show up as today's drift and get "deployed" back into existence.
  - deletes are opt-in via allow_delete=False default -- same posture as
    DDL deletions in scriptgen.py: this module has no path that removes a
    client file unless explicitly told to.

Pure stdlib; no robocopy/subprocess here -- emit_robocopy writes TEXT for
a Windows operator, apply_copy uses shutil so tests run on Linux too.
"""
import fnmatch
import hashlib
import shutil
import time
from pathlib import Path

try:
    from . import config  # noqa: F401  (parity header; future constants live here)
except ImportError:  # allows `python3.13 test_webdeploy.py` to run standalone --
    import config      # same plain-import fallback as every sibling module.


# ---------------------------------------------------------------------------
# containment helpers (app.py pattern: resolve, then verify inside root)
# ---------------------------------------------------------------------------

def _resolved_root(root: Path) -> Path:
    """Resolve the root once; callers compare against this single anchor."""
    return Path(root).resolve()


def _contained(resolved_root: Path, candidate: Path) -> bool:
    """True iff `candidate` (already resolved) lives under `resolved_root`.

    Uses os.path.commonpath-style prefix on parts rather than string
    startswith, so /root2 does NOT pass a /root check (classic prefix bug).
    """
    try:
        return candidate == resolved_root or resolved_root in candidate.parents
    except OSError:
        return False


def _is_hidden_or_sidecar(name: str) -> bool:
    """Hidden dotfiles/dirs and our own .bak_<epoch> sidecars are never content."""
    if name.startswith("."):
        return True
    # "*.bak_*" is the sidecar shape apply_copy() itself creates; skipping it
    # in hashing means re-runs see a clean tree, not their own leftovers.
    return bool(fnmatch.fnmatch(name, "*.bak_*"))


def _iter_content_files(root: Path) -> list[Path]:
    """Every real file under root that passes hidden/sidecar/containment filters.

    os.walk(followlinks=False) already refuses to descend symlinked dirs;
    we additionally prune dirs resolving outside root and skip files whose
    resolved path escapes -- belt and suspenders, same as app.py.
    """
    r = _resolved_root(root)
    out = []
    for dirpath, dirnames, filenames in __import__("os").walk(r, followlinks=False):
        here = Path(dirpath)
        # Prune escapees and filtered names IN PLACE so walk never enters them.
        keep = []
        for d in dirnames:
            if _is_hidden_or_sidecar(d):
                continue
            p = (here / d)
            real = p.resolve()
            if not _contained(r, real):
                continue  # symlink (or odd mount) pointing outward: skip, don't follow
            keep.append(d)
        dirnames[:] = keep
        for f in filenames:
            if _is_hidden_or_sidecar(f):
                continue
            p = here / f
            real = p.resolve()
            if not _contained(r, real):
                continue  # hardlink/symlink file escaping root: refuse
            if p.is_file():
                out.append(p)
    return sorted(out)


def _sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------

def hash_tree(root: Path, exts: set[str] | None = None) -> dict[str, str]:
    """relpath(posix) -> sha256 hex of bytes.

    exts=None means all files; a set like {".aspx", ".dll", ".js"} filters
    by suffix (case-insensitive -- IIS boxes are case-insensitive in spirit).
    Deterministic order (sorted relpaths) so manifests are diffable text.
    """
    r = _resolved_root(root)
    exts_l = {e.lower() for e in exts} if exts else None
    result: dict[str, str] = {}
    for p in _iter_content_files(r):
        if exts_l is not None and p.suffix.lower() not in exts_l:
            continue
        rel = p.relative_to(r).as_posix()
        result[rel] = _sha256_file(p)
    return dict(sorted(result.items()))


def build_manifest(src_root: Path, dst_root: Path) -> dict:
    """{"copy": [...], "delete": [...]} between an update-package tree and a deployed tree.

    copy   = present in src but missing from dst (add), or hash differs (update)
             -- both are "copy this file over", which is why they share one key.
    delete = present in dst, absent from src (stale page/dll left behind).

    dst_root may not exist at all (fresh box / zipped copy not yet unpacked):
    then everything in src lands in copy and delete is empty.
    Both sides use the SAME hash_tree filters, so our own .bak_* sidecars in
    dst never masquerade as deletable client files.
    """
    s = _resolved_root(src_root)
    d = _resolved_root(dst_root)  # resolve even if missing: fine below
    src_h = hash_tree(s)
    dst_h = hash_tree(d) if d.exists() else {}
    copy = [rel for rel, h in src_h.items() if dst_h.get(rel) != h]
    delete = [rel for rel in dst_h if rel not in src_h]
    return {"copy": sorted(copy), "delete": sorted(delete)}


def emit_robocopy(manifest: dict, src_root: Path, dst_root: Path) -> str:
    """Windows robocopy script TEXT for a field operator.

    Shape (contract): a commented DRY-RUN line first (/L lists actions,
    changes nothing), then one real copy line per file with echo progress
    markers so a hung copy is locatable from the console alone.
    "\n".join only -- no trailing newline games, byte-deterministic output
    so two identical manifests produce identical scripts (diff-friendly).
    """
    s = str(_resolved_root(src_root))
    d = str(_resolved_root(dst_root))
    lines: list[str] = [
        "@echo off",
        "REM drift-tool web deploy -- review before running.",
        "REM Step 1 DRY RUN (/L): prints what WOULD happen, changes nothing:",
    ]
    copies = list(manifest.get("copy", []))
    deletes = list(manifest.get("delete", []))
    # One /L invocation covering every planned file keeps the preview short.
    quoted = " ".join(f'"{c}"' for c in copies) or '"*"'
    lines.append(f'robocopy "{s}" "{d}" {quoted} /L /FP /NS /NC /NDL /NP')
    lines.append("REM Step 2 REAL COPY, one file per line with progress echoes:")
    for i, rel in enumerate(copies, 1):
        name = rel.rsplit("/", 1)[-1]
        parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
        lines.append(f'echo [{i}/{len(copies)}] copying {rel}')
        # robocopy takes <srcdir> <dstdir> <file>; subdirs need explicit creation
        # when the parent doesn't exist yet on the destination box.
        if parent:
            lines.append(f'if not exist "{d}\\{parent}" mkdir "{d}\\{parent}"')
        lines.append(f'robocopy "{s}\\{parent}" "{d}\\{parent}" "{name}"')
    if deletes:
        lines.append("REM DELETIONS (only run this section deliberately):")
        for rel in deletes:
            lines.append(f'del /Q "{d}\\{rel.replace("/", chr(92))}"')
    return "\n".join(lines)


def apply_copy(manifest: dict, src_root: Path, dst_root: Path, backup: bool = True,
               allow_delete: bool = False) -> dict:
    """Perform manifest.copy onto dst (and manifest.delete ONLY if allowed).

    backup=True renames each pre-existing dst file to "<name>.bak_<epoch>"
    BEFORE overwrite -- the rollback story is "move the sidecar back", no
    zip tooling required on an IIS box. Fresh adds have nothing to back up.
    Returns counters + errors[]; individual failures are collected, not
    raised, because a partial deploy must be reportable (house rule:
    bucketed noise beats a stack trace hiding what did land).
    """
    s = _resolved_root(src_root)
    d = _resolved_root(dst_root)
    copied = backed_up = deleted = 0
    errors: list[str] = []
    epoch = int(time.time())  # one stamp per run groups a deploy's sidecars

    def contained(rel: str) -> Path | None:
        """Resolve a manifest relpath against BOTH roots; None if it escapes."""
        cand_s = (s / rel).resolve()
        cand_d = (d / rel).resolve()
        if not (_contained(s, cand_s) and _contained(d, cand_d)):
            errors.append(f"rejected path escaping tree: {rel}")
            return None
        return cand_d

    for rel in manifest.get("copy", []):
        target = contained(rel)
        if target is None:
            continue
        src_f = s / rel
        if not src_f.is_file():  # package changed since manifest was built
            errors.append(f"source vanished: {rel}")
            continue
        try:
            if target.exists():
                if backup:
                    sidecar = target.with_name(target.name + f".bak_{epoch}")
                    shutil.move(str(target), str(sidecar))
                    backed_up += 1
                else:
                    errors.append(f"refused overwrite without backup: {rel}")
                    continue
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_f, target)
            copied += 1
        except OSError as e:
            errors.append(f"{rel}: {e}")

    if allow_delete:
        for rel in manifest.get("delete", []):
            target = contained(rel)
            if target is None:
                continue
            try:
                if target.exists():
                    target.unlink()
                    deleted += 1
            except OSError as e:
                errors.append(f"delete {rel}: {e}")
    elif manifest.get("delete"):
        # Visible refusal, not silence -- matches the DDL deletions posture.
        errors.append(
            f"{len(manifest['delete'])} deletion(s) blocked (allow_delete=False): "
            + ", ".join(manifest["delete"])
        )

    return {"copied": copied, "backed_up": backed_up, "deleted": deleted, "errors": errors}
