"""ponytail: minimal self-check for S1 -- changelog.py must use diffing.py's
literal-aware normalize_sql, not maintain a second, naive copy of it.
changelog.inspect() itself needs a live restored DB (no dedicated test file
for that, same as dependencies.py/restore.py -- consistent with this
project's existing convention for DB-orchestration modules), but the
normalization it compares with is pure and worth locking down directly.
Run: python3.13 test_changelog.py

changelog.py uses `from . import config, diffing` (package-relative) since
S1 added the diffing import -- same reason test_pipeline.py needs this
sys.path/package-import trick rather than a bare `import changelog`.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import changelog, diffing  # noqa: E402


def test_changelog_delegates_to_diffings_normalize_sql():
    """Not just "produces the same output" -- the actual function object,
    so a future diffing.py improvement (or bugfix) is automatically picked
    up here too, instead of two copies silently drifting apart again."""
    assert changelog.diffing.normalize_sql is diffing.normalize_sql


def test_literal_containing_comment_marker_is_not_corrupted():
    """S1's actual bug: the OLD naive version stripped `--`/`/* */` with no
    string-literal awareness, so a value like N'-- not a comment' inside a
    real T-SQL definition would have its content wrongly treated as a
    comment. This is exactly the class of input the lost-fix tripwire
    compares (logged NewDefinition vs current OBJECT_DEFINITION) --
    getting it wrong could flip the verdict either way."""
    logged = "CREATE PROCEDURE p AS SELECT N'-- not a comment' AS x"
    current_same = "CREATE   PROCEDURE  p  AS  SELECT  N'-- not a comment'  AS  x"  # formatting-only diff
    current_different = "CREATE PROCEDURE p AS SELECT N'totally different literal' AS x"

    assert changelog.diffing.normalize_sql(logged) == changelog.diffing.normalize_sql(current_same), \
        "a formatting-only difference outside the literal must still normalize equal"
    assert changelog.diffing.normalize_sql(logged) != changelog.diffing.normalize_sql(current_different), \
        "a real difference INSIDE the literal must never be masked"


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
