"""ponytail: minimal self-check for _enrich()'s D1 no_difference reclassification
-- the one branch in this file with real logic and no prior test coverage
(everything else in pipeline.py is DB-orchestration, exercised by the full
integration/surgical-battery runs instead). Run: python3.13 test_pipeline.py

Unlike this directory's other test_*.py files, pipeline.py can't be loaded
as a bare top-level module -- it uses real `from . import (...)` package-
relative imports internally (it's normally only ever reached via
`from drift import pipeline`, never run standalone), so a plain
`import pipeline` here raises "attempted relative import with no known
parent package". Fixed by putting drift-tool/ (the parent of this
package) on sys.path and importing pipeline properly through the `drift`
package -- same technique setup/*.py scripts already use to reach into
this package from outside it -- rather than changing pipeline.py's own
import style to accommodate a test runner.
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import pipeline  # noqa: E402


def _enrich(item, master_defs=None, client_defs=None, master_settings=None, client_settings=None):
    return pipeline._enrich(
        item, "client_to_105",
        master_defs or {}, client_defs or {}, {}, {},
        attribution_by_name={}, master_callers={}, client_callers={},
        master_settings=master_settings, client_settings=client_settings,
    )


def test_identical_captured_text_demotes_to_no_difference():
    """The measured real-data bug (work/output/1784497700_5ff79b): SqlPackage
    flagged an FK as changed (category=structural from parse_deploy_report),
    but the captured text on both sides is byte-identical -- nothing this
    tool can compare actually differs."""
    item = {"name": "[dbo].[FK_X]", "type": "SqlForeignKeyConstraint", "role": "modified",
            "category": "structural", "action": "Alter"}
    text = "ALTER TABLE [T] ADD CONSTRAINT [FK_X] FOREIGN KEY (A) REFERENCES [U] (A);"
    f = _enrich(item, master_defs={"FK_X": text}, client_defs={"FK_X": text})
    assert f["change_kind"] == "none"
    assert f["category"] == "no_difference", f["category"]
    assert "no_difference" not in f["summary"]  # human summary text, not the raw enum


def test_disabled_fk_with_d1a_flags_stays_structural_not_demoted():
    """The hard prerequisite this reclassification depends on (D1a): a
    NOCHECK-disabled FK must NOT reconstruct to identical text, or this
    exact demotion would turn a real, dangerous drift into a false
    'no difference'. Mirrors the flag format inspect_objects.py actually
    emits ([FLAGS: ...], never a -- comment -- see that module's docstring
    for why comment-style would be silently stripped by normalize_sql)."""
    item = {"name": "[dbo].[FK_X]", "type": "SqlForeignKeyConstraint", "role": "modified",
            "category": "structural", "action": "Alter"}
    base = "ALTER TABLE [T] ADD CONSTRAINT [FK_X] FOREIGN KEY (A) REFERENCES [U] (A);"
    f = _enrich(item, master_defs={"FK_X": base}, client_defs={"FK_X": base + "  [FLAGS: DISABLED, NOT TRUSTED]"})
    assert f["change_kind"] == "structural", f["change_kind"]
    assert f["category"] == "structural", "a disabled FK must never be demoted to no_difference"


def test_settings_only_difference_is_never_demoted():
    """change_kind gets upgraded "none" -> "settings" by the L-11 settings
    sweep a few lines above the D1 check -- that upgrade must win, not get
    re-demoted back to no_difference immediately after."""
    item = {"name": "[dbo].[Pro_X]", "type": "SqlProcedure", "role": "modified",
            "category": "structural", "action": "Alter"}
    text = "CREATE PROCEDURE [Pro_X] AS SELECT 1"
    f = _enrich(
        item, master_defs={"Pro_X": text}, client_defs={"Pro_X": text},
        master_settings={"Pro_X": {"ansi_nulls": True, "quoted_identifier": True}},
        client_settings={"Pro_X": {"ansi_nulls": False, "quoted_identifier": True}},
    )
    assert f["change_kind"] == "settings", f["change_kind"]
    assert f["category"] == "structural", "a settings-only difference must never be demoted"


def test_added_finding_has_no_change_kind_and_is_never_demoted():
    """Single-sided findings (added/only_on_other) never get a change_kind
    at all -- absence of a diff must never be read as 'confirmed same'."""
    item = {"name": "[dbo].[FK_New]", "type": "SqlForeignKeyConstraint", "role": "added",
            "category": "structural", "action": "Create"}
    f = _enrich(item, master_defs={}, client_defs={"FK_New": "ALTER TABLE [T] ADD CONSTRAINT [FK_New] ..."})
    assert f.get("change_kind") is None
    assert f["category"] == "structural"


def test_table_with_identical_columns_also_demotes():
    """SqlTable takes a different code path (diff_columns, not
    diff_programmable) but the D1 check runs unconditionally after the
    whole if/elif chain, keyed only on the resulting change_kind -- must
    catch this branch too, not just the captured-definition one. Real
    motivation: SqlPackage's own table-rebuild planner sometimes reports a
    table as modified purely because of an unrelated FK/constraint change,
    with the table's own column set genuinely untouched (VALIDATION.md
    §10.2's documented FK-cascade asymmetry)."""
    item = {"name": "[dbo].[T]", "type": "SqlTable", "role": "modified",
            "category": "structural", "action": "Alter"}
    cols = [{"name": "ID", "type": "int", "max_length": 4, "precision": 10, "scale": 0,
             "nullable": False, "is_pk": True}]
    f = pipeline._enrich(
        item, "client_to_105", {}, {}, {"T": cols}, {"T": cols},
        attribution_by_name={}, master_callers={}, client_callers={},
    )
    assert f["change_kind"] == "none"
    assert f["category"] == "no_difference"


def test_formatting_only_category_is_left_alone():
    """D1 only ever touches category=="structural" -- formatting_only findings
    already have their own correct, separate bucket and must not be
    reclassified a second time."""
    item = {"name": "[dbo].[Pro_Y]", "type": "SqlProcedure", "role": "modified",
            "category": "formatting_only", "action": "Alter"}
    f = _enrich(item, master_defs={"Pro_Y": "create proc Pro_Y as select 1"},
                client_defs={"Pro_Y": "CREATE   PROC Pro_Y AS SELECT 1"})
    assert f["category"] == "formatting_only"


def test_capture_hash_bytes_round_trip_through_hex_encoding():
    """D5d: HASHBYTES returns raw bytes -- not JSON-serializable. _write_capture
    hex-encodes them; _load_capture must reconstruct byte-identical values, or
    a recompare()'s find_formatting_only would silently compare the wrong
    thing (a hex STRING against raw BYTES never equal no matter what)."""
    with tempfile.TemporaryDirectory() as d:
        run_dir = Path(d)
        raw = b"\x01\x02\xff\x00\xab"
        pipeline._write_capture(
            run_dir,
            master_defs={"X": "def"}, client_defs={}, master_cols={}, client_cols={},
            master_hashes={"X": ("SqlProcedure", raw)}, client_hashes={"X": ("SqlProcedure", raw)},
            master_all_settings={"X": ("SqlProcedure", {"ansi_nulls": True, "quoted_identifier": True})},
            client_all_settings={},
            master_callers={}, client_callers={}, attribution_rows=[], lost_fixes=[],
        )
        loaded = pipeline._load_capture(run_dir)
        assert loaded["master_hashes"]["X"] == ("SqlProcedure", raw)
        assert loaded["master_all_settings"]["X"] == ("SqlProcedure", {"ansi_nulls": True, "quoted_identifier": True})
        assert loaded["master_defs"] == {"X": "def"}


def test_recompare_refuses_when_capture_json_missing():
    """A run from before this feature existed (or interrupted before the
    persist_capture phase) must refuse with a clear reason, never silently
    proceed with partial/absent data."""
    original_output_dir = pipeline.config.OUTPUT_DIR
    try:
        with tempfile.TemporaryDirectory() as d:
            run_dir = Path(d) / "run_output" / "fake_run"
            run_dir.mkdir(parents=True)
            (run_dir / "meta.json").write_text(json.dumps({"directions": ["client_to_105"]}))
            pipeline.config.OUTPUT_DIR = run_dir.parent
            try:
                pipeline.recompare("fake_run", "client_to_105", log=lambda *_: None)
                raise AssertionError("expected recompare to refuse")
            except RuntimeError as e:
                assert "capture data" in str(e)
    finally:
        pipeline.config.OUTPUT_DIR = original_output_dir


def test_recompare_refuses_when_source_backup_changed():
    """Cache-key mismatch (size/mtime) must refuse rather than serve a
    re-compare against a .dacpac pair that no longer matches its source."""
    original_output_dir = pipeline.config.OUTPUT_DIR
    try:
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            run_dir = base / "run_output" / "fake_run"
            run_dir.mkdir(parents=True)
            bak = base / "master.bak"
            bak.write_bytes(b"original content")
            st = bak.stat()
            meta = {
                "directions": ["client_to_105"],
                "bak_cache_key": {
                    "master": {"path": str(bak), "size": st.st_size, "mtime": st.st_mtime},
                    "client": {"path": str(bak), "size": st.st_size, "mtime": st.st_mtime},
                },
            }
            (run_dir / "meta.json").write_text(json.dumps(meta))
            (run_dir / "capture.json").write_text(json.dumps({
                "master_defs": {}, "client_defs": {}, "master_cols": {}, "client_cols": {},
                "master_hashes": {}, "client_hashes": {}, "master_all_settings": {}, "client_all_settings": {},
                "master_callers": {}, "client_callers": {}, "attribution_rows": [], "lost_fixes": [],
            }))
            bak.write_bytes(b"a completely different, longer content")  # size now differs

            pipeline.config.OUTPUT_DIR = run_dir.parent
            try:
                pipeline.recompare("fake_run", "client_to_105", log=lambda *_: None)
                raise AssertionError("expected recompare to refuse")
            except RuntimeError as e:
                assert "changed" in str(e)
    finally:
        pipeline.config.OUTPUT_DIR = original_output_dir





# ---------- PLAN-V4 B.2a: ClientActive scope annotation ----------

def _gated_pair():
    """Master and client bodies that differ ONLY inside another client's
    (client 165's) gated branch -- identical for THIS client (66)."""
    shared = "SELECT 'shared-logic'"
    master = ("CREATE PROC dbo.Z AS\nBEGIN\n"
              "IF @ClientActive = 165\nBEGIN\n SELECT 'spartan-old'\nEND\n"
              + shared + "\nEND")
    client = ("CREATE PROC dbo.Z AS\nBEGIN\n"
              "IF @ClientActive = 165\nBEGIN\n SELECT 'spartan-brand-new'\nEND\n"
              + shared + "\nEND")
    return master, client


def test_scope_annotation_flags_irrelevant_when_fingerprints_match():
    mdef, cdef = _gated_pair()
    f = _enrich({"name": "[dbo].[Z]", "type": "SqlProcedure", "role": "modified",
                 "category": "structural", "action": "Alter"},
                master_defs={"Z": mdef}, client_defs={"Z": cdef},
                ) if False else pipeline._enrich(
        {"name": "[dbo].[Z]", "bare_name": "Z", "type": "SqlProcedure", "role": "modified",
         "category": "structural", "action": "Alter"},
        "client_to_105", {"Z": mdef}, {"Z": cdef}, {}, {},
        attribution_by_name={}, master_callers={}, client_callers={},
        client_active_id="66")
    assert f.get("scope"), f
    assert f["scope"]["irrelevant_to_client"] is True, f["scope"]
    assert f["scope"]["master"]["excluded"] == 1, f["scope"]
    # detection untouched: category/change_kind stay as they were
    assert f["category"] == "structural" and f["change_kind"] == "body", (f["category"], f["change_kind"])


def test_no_active_id_means_zero_behavior_change():
    mdef, cdef = _gated_pair()
    f = pipeline._enrich(
        {"name": "[dbo].[Z]", "bare_name": "Z", "type": "SqlProcedure", "role": "modified",
         "category": "structural", "action": "Alter"},
        "client_to_105", {"Z": mdef}, {"Z": cdef}, {}, {},
        attribution_by_name={}, master_callers={}, client_callers={})
    assert "scope" not in f


def test_shared_code_difference_is_never_irrelevant():
    mdef, cdef = _gated_pair()
    cdef2 = cdef.replace("SELECT 'shared-logic'", "SELECT 'shared-changed'")
    f = pipeline._enrich(
        {"name": "[dbo].[Z]", "bare_name": "Z", "type": "SqlProcedure", "role": "modified",
         "category": "structural", "action": "Alter"},
        "client_to_105", {"Z": mdef}, {"Z": cdef2}, {}, {},
        attribution_by_name={}, master_callers={}, client_callers={},
        client_active_id="66")
    assert not f["scope"].get("irrelevant_to_client"), f["scope"]


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
