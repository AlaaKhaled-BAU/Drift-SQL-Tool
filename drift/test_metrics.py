"""ponytail: minimal self-check for sample_accuracy()'s extended-type widening
(the follow-up that replaced is_programmable/_PROGRAMMABLE_TYPES with
is_text_captured/_TEXT_CAPTURED_TYPES). sample_accuracy() reads sidecar files
straight off disk (workspace_dir / f["path"] + ".master.sql"/".client.sql"),
so this writes real temp fixtures matching what report_writer.py actually
produces, rather than mocking file I/O. Run: python3.13 test_metrics.py
"""
import shutil
import tempfile
from pathlib import Path

import metrics


def _write(base: Path, master_text, client_text):
    base.parent.mkdir(parents=True, exist_ok=True)
    if master_text is not None:
        Path(str(base) + ".master.sql").write_text(master_text)
    if client_text is not None:
        Path(str(base) + ".client.sql").write_text(client_text)


def test_fk_no_difference_finding_is_confirmed_not_limitation():
    """The exact regression this widening exists to fix: before it, ANY
    FK/index/constraint/sequence/synonym/table-type/UDT finding fell to
    `limitation` regardless of what was actually on disk, because
    is_programmable was False for all of them and the has_m/has_c read
    never even ran. A genuinely-identical FK must now report `confirmed`."""
    tmp = Path(tempfile.mkdtemp())
    try:
        text = "ALTER TABLE [T] ADD CONSTRAINT [FK_X] FOREIGN KEY (A) REFERENCES [U] (A);"
        _write(tmp / "05_no_difference/other/FK_X", text, text)
        index = {"findings": [{
            "id": "x_00000", "name": "[dbo].[FK_X]", "type": "SqlForeignKeyConstraint",
            "role": "modified", "category": "no_difference",
            "path": "05_no_difference/other/FK_X",
        }]}
        result = metrics.sample_accuracy(tmp, index, sample_size=10, seed=0)
        assert result["confirmed"] == 1, result
        assert result["anomaly"] == 0, result
        assert result["limitation_uncaptured_type"] == 0, result
    finally:
        shutil.rmtree(tmp)


def test_fk_modified_with_real_text_difference_is_confirmed():
    """Same widening, ordinary 'modified' role (not no_difference) -- an FK
    that genuinely differs must independently re-confirm as modified, not
    fall to limitation either."""
    tmp = Path(tempfile.mkdtemp())
    try:
        _write(tmp / "02_modified/other/FK_Y", "...ON DELETE NO_ACTION;", "...ON DELETE CASCADE;")
        index = {"findings": [{
            "id": "y_00000", "name": "[dbo].[FK_Y]", "type": "SqlForeignKeyConstraint",
            "role": "modified", "category": "structural",
            "path": "02_modified/other/FK_Y",
        }]}
        result = metrics.sample_accuracy(tmp, index, sample_size=10, seed=0)
        assert result["confirmed"] == 1, result
        assert result["limitation_uncaptured_type"] == 0, result
    finally:
        shutil.rmtree(tmp)


def test_role_membership_still_reports_as_limitation():
    """SqlRole has no getter anywhere in inspect_objects.py -- must still
    honestly report as not-independently-checkable, not silently guess."""
    tmp = Path(tempfile.mkdtemp())
    try:
        index = {"findings": [{
            "id": "z_00000", "name": "[dbo].[SomeRole]", "type": "SqlRole",
            "role": "modified", "category": "structural",
            "path": "02_modified/other/SomeRole",
        }]}
        result = metrics.sample_accuracy(tmp, index, sample_size=10, seed=0)
        assert result["limitation_uncaptured_type"] == 1, result
        assert result["confirmed"] == 0 and result["anomaly"] == 0
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
