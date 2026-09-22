"""ponytail: minimal self-check, not a framework. Run: python3.13 test_diffing.py"""
from diffing import diff_programmable, diff_columns

def test_comment_only_not_flagged_as_real():
    a = "CREATE PROCEDURE dbo.X @Y int AS\nBEGIN\n  SELECT 1\nEND"
    b = "CREATE PROCEDURE dbo.X @Y int AS\nBEGIN\n  -- note\n  SELECT 1\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "formatting_only", r

def test_param_only_change():
    a = "CREATE PROCEDURE dbo.X @Y int AS\nBEGIN\n  SELECT 1\n  SELECT 2\nEND"
    b = "CREATE PROCEDURE dbo.X @Y int, @Z smallint = 1 AS\nBEGIN\n  SELECT 1\n  SELECT 2\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "param", r

def test_body_only_change():
    a = "CREATE PROCEDURE dbo.X @Y int AS\nBEGIN\n  SELECT 1\nEND"
    b = "CREATE PROCEDURE dbo.X @Y int AS\nBEGIN\n  SELECT 1\n  ORDER BY Y\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "body", r

def test_both_changed():
    a = "CREATE PROCEDURE dbo.X @Y int AS\nBEGIN\n  SELECT 1\nEND"
    b = "CREATE PROCEDURE dbo.X @Y int, @Z int AS\nBEGIN\n  SELECT 2\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "both", r

def test_identical_is_none():
    a = "CREATE PROCEDURE dbo.X AS\nSELECT 1"
    r = diff_programmable(a, a)
    assert r["change_kind"] == "none", r

def _col(name, type_, max_length=0, precision=0, scale=0, nullable=True, is_pk=False):
    return {"name": name, "type": type_, "max_length": max_length,
            "precision": precision, "scale": scale, "nullable": nullable, "is_pk": is_pk}

def test_column_added():
    m = [_col("A", "int", is_pk=True, nullable=False)]
    c = [_col("A", "int", is_pk=True, nullable=False), _col("B", "nvarchar", max_length=100)]
    r = diff_columns(m, c)
    assert r["added"] == ["B"] and r["removed"] == [] and not r["retyped"], r

def test_column_removed():
    m = [_col("A", "int", is_pk=True, nullable=False), _col("B", "int")]
    c = [_col("A", "int", is_pk=True, nullable=False)]
    r = diff_columns(m, c)
    assert r["removed"] == ["B"] and r["added"] == [], r

def test_column_retyped():
    m = [_col("A", "nvarchar", max_length=100)]
    c = [_col("A", "int")]
    r = diff_columns(m, c)
    assert len(r["retyped"]) == 1 and r["retyped"][0]["name"] == "A", r

def test_column_length_only_change_is_retyped():
    """nvarchar(50) -> nvarchar(4000): same base type, different width -- this
    is the exact gap a bare type-name compare would miss (see diffing.py's
    rendered_type). Real structural change, must be caught."""
    m = [_col("Notes", "nvarchar", max_length=100)]   # nvarchar(50): max_length in bytes = 2x chars
    c = [_col("Notes", "nvarchar", max_length=8000)]  # nvarchar(4000)
    r = diff_columns(m, c)
    assert len(r["retyped"]) == 1 and r["retyped"][0]["name"] == "Notes", r

def test_column_same_length_not_flagged():
    m = [_col("Notes", "nvarchar", max_length=100)]
    c = [_col("Notes", "nvarchar", max_length=100)]
    r = diff_columns(m, c)
    assert r["retyped"] == [] and r["added"] == [] and r["removed"] == [], r

# --- L-4 adversarial cases: literal/comment content must never corrupt
# normalization or the param/body split point. ---

def test_as_inside_string_literal_not_split_point():
    """A default value like N'Status AS Of' must not be mistaken for the
    real parameter/body boundary -- the split must land at the true AS."""
    a = "CREATE PROCEDURE dbo.X @Y nvarchar(20) = N'Status AS Of' AS\nBEGIN\n  SELECT @Y\nEND"
    b = "CREATE PROCEDURE dbo.X @Y nvarchar(20) = N'Status AS Of' AS\nBEGIN\n  SELECT @Y, 1\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "body", r  # not "param" -- the literal AS didn't fool the split

def test_double_dash_inside_string_literal_preserved():
    """A literal containing '--' must survive normalization byte-exact --
    stripping it as a comment would hide a genuine data-literal change."""
    a = "CREATE PROCEDURE dbo.X AS\nBEGIN\n  SELECT '--kept-a'\nEND"
    b = "CREATE PROCEDURE dbo.X AS\nBEGIN\n  SELECT '--kept-b'\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "body", r  # genuinely different literals, must not vanish as "none"

def test_comment_inside_body_not_mistaken_for_as_split():
    """A comment containing the word AS, before the real standalone AS,
    must not be matched as the split point."""
    a = "CREATE PROCEDURE dbo.X -- uses AS later\n@Y int\nAS\nBEGIN\n  SELECT 1\nEND"
    b = "CREATE PROCEDURE dbo.X -- uses AS later\n@Y int, @Z int\nAS\nBEGIN\n  SELECT 1\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "param", r

def test_bracketed_identifier_named_as_not_split_point():
    """A column/identifier literally named [AS] must not be mistaken for
    the standalone-AS split point."""
    a = "CREATE VIEW dbo.X AS\nSELECT [AS] FROM dbo.T"
    b = "CREATE VIEW dbo.X AS\nSELECT [AS], [Other] FROM dbo.T"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "body", r

def test_case_change_inside_literal_is_real_change():
    """Literal content case must be preserved -- casefold() must apply only
    to code, never to string-literal data (e.g. 'Active' vs 'active' are
    different data values, not a formatting difference)."""
    a = "CREATE PROCEDURE dbo.X AS\nBEGIN\n  UPDATE T SET Status = 'Active'\nEND"
    b = "CREATE PROCEDURE dbo.X AS\nBEGIN\n  UPDATE T SET Status = 'active'\nEND"
    r = diff_programmable(a, b)
    assert r["change_kind"] == "body", r

if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
