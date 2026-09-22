"""ponytail: minimal self-check for D5a's type-filter logic -- the one part
of compare.py with genuinely new logic; the rest is validated by the full
pipeline/surgical-battery runs, not unit tests (this file didn't exist
before D5a). Run: python3.13 test_compare.py

compare.py uses package-relative imports (`from . import config`), same
situation as pipeline.py (see test_pipeline.py's own docstring) -- needs
drift-tool/ on sys.path and importing through the `drift` package, not a
bare `import compare`."""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift.compare import (bare_name, find_formatting_only, find_settings_only,  # noqa: E402
                            parse_deploy_report, passes_type_filter, qualified_name, type_category)


def test_type_category_maps_known_types():
    assert type_category("SqlProcedure") == "Procedures"
    assert type_category("SqlScalarFunction") == "Functions"
    assert type_category("SqlMultiStatementTableValuedFunction") == "Functions"
    assert type_category("SqlDmlTrigger") == "Triggers"
    assert type_category("SqlForeignKeyConstraint") == "Constraints"


def test_type_category_defaults_unrecognized_to_other():
    """An unrecognized type must fall into a visible, selectable bucket
    (Other), never silently vanish from every possible filter selection."""
    assert type_category("SqlSequence") == "Other"
    assert type_category("SomeFutureSqlPackageType") == "Other"


def test_passes_type_filter_none_or_empty_means_no_filter():
    assert passes_type_filter("SqlProcedure", None) is True
    assert passes_type_filter("SqlProcedure", set()) is True


def test_passes_type_filter_checks_category_membership():
    assert passes_type_filter("SqlProcedure", {"Procedures"}) is True
    assert passes_type_filter("SqlProcedure", {"Views"}) is False
    assert passes_type_filter("SqlSequence", {"Other"}) is True


def test_qualified_name_keeps_table_for_sql_index():
    """D3 Change B: the real, observed sqlpackage shape (work/output/.../
    diff_client_to_105.xml) -- a 3-part bracketed name for SqlIndex, unlike
    every other type's 2-part [schema].[name]."""
    assert qualified_name("[dbo].[JoTaxResult].[IX_JoTaxResult_TranType_TranNo]", "SqlIndex") \
        == "JoTaxResult.IX_JoTaxResult_TranType_TranNo"


def test_qualified_name_matches_bare_name_for_every_non_index_type():
    for obj_type in ("SqlProcedure", "SqlView", "SqlTable", "SqlForeignKeyConstraint", "SqlSequence"):
        name = "[dbo].[Some_Object]"
        assert qualified_name(name, obj_type) == bare_name(name) == "Some_Object"


def test_qualified_name_falls_back_to_bare_for_a_2part_index_name():
    """Defensive: if an index ever arrives without its table qualifier
    (fewer than 3 bracket segments), fall back to bare_name's behavior
    rather than producing a malformed "table.index" key with a wrong split."""
    assert qualified_name("[dbo].[IX_Weird]", "SqlIndex") == "IX_Weird"


_XML_TEMPLATE = """<?xml version="1.0"?>
<DeploymentReport>
  <Operations>
    <Operation Name="Alter">
      <Item Type="SqlProcedure" Value="[dbo].[Pro_X]" />
      <Item Type="SqlTable" Value="[dbo].[T]" />
    </Operation>
    <Operation Name="Create">
      <Item Type="SqlView" Value="[dbo].[V_New]" />
    </Operation>
  </Operations>
</DeploymentReport>
"""


def _write_xml(tmp_path):
    p = tmp_path / "diff.xml"
    p.write_text(_XML_TEMPLATE)
    return p


def test_parse_deploy_report_with_no_filter_keeps_everything():
    with tempfile.TemporaryDirectory() as d:
        xml_path = _write_xml(Path(d))
        result = parse_deploy_report(str(xml_path), [], log=lambda *_: None)
        assert len(result["items"]) == 3
        assert result["filtered_out_count"] == 0


def test_parse_deploy_report_filters_non_selected_types_and_counts_them():
    with tempfile.TemporaryDirectory() as d:
        xml_path = _write_xml(Path(d))
        result = parse_deploy_report(str(xml_path), [], log=lambda *_: None, type_filter={"Procedures"})
        names = [i["type"] for i in result["items"]]
        assert names == ["SqlProcedure"]
        assert result["filtered_out_count"] == 2, "the table and the view must both be counted, not dropped silently"


def test_find_formatting_only_respects_type_filter():
    source = {"Pro_X": ("SqlProcedure", b"\x01"), "V_X": ("SqlView", b"\x01")}
    target = {"Pro_X": ("SqlProcedure", b"\x02"), "V_X": ("SqlView", b"\x02")}
    findings, filtered_out = find_formatting_only(source, target, set(), [], type_filter={"Procedures"})
    assert [f["name"] for f in findings] == ["[dbo].[Pro_X]"]
    assert filtered_out == 1


def test_find_settings_only_respects_type_filter():
    source = {"Pro_X": ("SqlProcedure", {"ansi_nulls": True, "quoted_identifier": True}),
              "V_X": ("SqlView", {"ansi_nulls": True, "quoted_identifier": True})}
    target = {"Pro_X": ("SqlProcedure", {"ansi_nulls": False, "quoted_identifier": True}),
              "V_X": ("SqlView", {"ansi_nulls": False, "quoted_identifier": True})}
    findings, filtered_out = find_settings_only(source, target, set(), [], type_filter={"Views"})
    assert [f["name"] for f in findings] == ["[dbo].[V_X]"]
    assert filtered_out == 1


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
