"""gatewrap.py -- two-direction IF-block wrapping (PLAN-V4 B.2).
ponytail: minimal self-check, run standalone -- python3.13 test_gatewrap.py

Fixtures mirror test_statements.py proc shapes
("CREATE PROCEDURE dbo.X AS BEGIN ... END"); delta entries mirror
statements.align_statements() output; the cursor fixture mirrors
test_blocks.py's. Direction-matrix spirit per PLAN-V4 B.2/B.9: both
directions x {chain-exists, no-chain, cursor-fallback} plus byte-safety.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import diffing, gatewrap  # noqa: E402


def _proc(body: str) -> str:
    return f"CREATE PROCEDURE dbo.Test\nAS\nBEGIN\n{body}\nEND"


def _delta(tag: str, text: str) -> dict:
    """One align_statements()-shaped entry (client side only matters here)."""
    return {"tag": tag, "master": None,
            "client": {"kind": "SELECT", "condition": None, "text": text}}


CHAIN_BODY = (
    "IF @ClientActive = 33\n"
    "BEGIN\n"
    "    SELECT 'a'\n"
    "END\n"
    "ELSE IF @ClientActive = 165\n"
    "BEGIN\n"
    "    SELECT 'b'\n"
    "END"
)

CURSOR_BODY = (
    "DECLARE c CURSOR FOR SELECT 1\nOPEN c\nFETCH NEXT FROM c INTO @i\n"
    "WHILE @@FETCH_STATUS = 0\nBEGIN\n FETCH NEXT FROM c INTO @i\nEND\n"
    "CLOSE c\nDEALLOCATE c"
)

PLAIN_CHAIN_BODY = (
    "IF @ClientActive = 33\n"
    "BEGIN\n"
    "    SELECT 'a'\n"
    "END"
)


# ---------- splice_up (client_to_105 back-port) ----------

def test_splice_up_appends_to_existing_chain():
    """New client branch lands LAST in an existing chain: order kept, prior
    branches verbatim, exact '@ClientActive = 66' condition emitted."""
    out = gatewrap.splice_up(_proc(CHAIN_BODY),
                             [_delta("changed", "UPDATE C SET X = 9")], 66)
    assert out is not None
    assert out.index("@ClientActive = 33") < out.index("@ClientActive = 165") \
        < out.index("@ClientActive = 66"), out
    assert "ELSE IF @ClientActive = 66" in out, out
    assert out.index("SELECT 'a'") < out.index("SELECT 'b'") \
        < out.index("UPDATE C SET X = 9"), out
    # the new branch is INSIDE the chain segment, before the proc's outer END
    assert out.index("@ClientActive = 66") < out.rindex("END"), out
    # and it re-parses as exactly one more branch than master had
    _, body = diffing.split_param_body(out)
    segs = gatewrap._segment_body(body.strip())
    chains = [s for s in segs if s["kind"] == "IF"]
    branches = gatewrap._parse_chain(chains[0]["text"])
    assert len(branches) == 3, [b["condition"] for b in branches]
    last = branches[-1]
    # _parse_chain keeps an ELSE-IF branch's own IF keyword inside its
    # condition text -- compare gate identity, not raw representation
    assert last["kind"] == "elseif", last
    assert last["condition"].replace("IF ", "", 1) == "@ClientActive = 66", last


def test_splice_up_wraps_whole_body_when_no_chain():
    """No top-level gate chain: whole original body becomes the ELSE path,
    its bytes riding along verbatim."""
    plain_body = "SELECT 1\nSELECT 2"
    out = gatewrap.splice_up(_proc(plain_body),
                             [_delta("added", "INSERT INTO Log VALUES ('x')")], 66)
    assert out is not None
    assert "IF @ClientActive = 66" in out, out
    # _proc wraps in BEGIN..END, so THAT whole text rides inside the ELSE
    assert f"ELSE\nBEGIN\nBEGIN\n{plain_body}\nEND\nEND" in out, out
    assert out.count("INSERT INTO Log VALUES ('x')") == 1, out
    assert out.index("IF @ClientActive = 66") < out.index("ELSE"), out


def test_splice_up_returns_none_on_cursor_proc():
    """Cursor flow is disclosed-fail (PLAN-V4 B.2): None -> AI-merge fallback,
    never a guessed splice of OPEN/FETCH loop structure."""
    out = gatewrap.splice_up(_proc(CURSOR_BODY), [_delta("added", "SELECT 99")], 66)
    assert out is None


def test_splice_up_preserves_other_clients_bodies_byte_for_byte():
    """105's other-clients logic untouched by construction: their branch
    bodies survive verbatim, literals containing gate syntax included."""
    other = (
        "IF @ClientActive = 165\n"
        "BEGIN\n"
        "    UPDATE T SET A = 1 WHERE B IN ('BEGIN fake END')\n"
        "    DELETE FROM T WHERE B = 3\n"
        "END"
    )
    out = gatewrap.splice_up(_proc(other), [_delta("changed", "SELECT 7")], 99)
    assert out is not None
    exact_mid = ("UPDATE T SET A = 1 WHERE B IN ('BEGIN fake END')\n"
                 "    DELETE FROM T WHERE B = 3")
    assert exact_mid in out, out
    assert out.count("@ClientActive = 165") == 1, out
    assert "SELECT 7" in out and "@ClientActive = 99" in out, out


def test_splice_up_empty_deltas_returns_none():
    """Nothing to fold in (no added/changed entries) -> None, never an empty
    or no-op branch."""
    assert gatewrap.splice_up(_proc(CHAIN_BODY), [], 66) is None
    equal_only = [{"tag": "equal", "master": {}, "client": {}}]
    assert gatewrap.splice_up(_proc(CHAIN_BODY), equal_only, 66) is None
    removed_only = [{"tag": "removed", "master": {"text": "SELECT 1"}, "client": None}]
    assert gatewrap.splice_up(_proc(CHAIN_BODY), removed_only, 66) is None


# ---------- preserve_down (105_to_client push) ----------

MASTER_WITH_ELSE = (
    "IF @ClientActive = 33\n"
    "BEGIN\n"
    "    SELECT 'a'\n"
    "END\n"
    "ELSE\n"
    "BEGIN\n"
    "    SELECT 'generic'\n"
    "END"
)


def test_preserve_down_reappends_before_trailing_else():
    """THE disaster guard (PLAN-V4 B.2): the client's own gated branch comes
    back BEFORE master's trailing ELSE -- after ELSE it would never run."""
    client_old = _proc(
        "IF @ClientActive = 33\nBEGIN\n SELECT 'a'\nEND\n"
        "IF @ClientActive = 66\nBEGIN\n UPDATE C SET X = 9\nEND")
    out = gatewrap.preserve_down(_proc(MASTER_WITH_ELSE), client_old)
    assert out is not None
    i_33 = out.index("@ClientActive = 33")
    i_66 = out.index("@ClientActive = 66")
    i_generic = out.index("SELECT 'generic'")
    assert i_33 < i_66 < i_generic, out
    assert "UPDATE C SET X = 9" in out, out


def test_preserve_down_returns_none_when_client_adds_nothing_new():
    """Every client condition already exists in master's chain (normalized
    compare -- diffing.normalize_sql casefolds and collapses space runs):
    zero extra gates -> None -> caller keeps plain master_def."""
    client_old = _proc(
        "IF @CLIENTACTIVE  =  66\nBEGIN\n SELECT 'old'\nEND\nSELECT 5")
    master_new = _proc(
        "IF @ClientActive = 66\nBEGIN\n SELECT 'new'\nEND\nSELECT 6")
    assert gatewrap.preserve_down(master_new, client_old) is None


def test_preserve_down_dedupes_same_condition_branches():
    """A condition duplicated inside the CLIENT's own body is contributed
    once, not once per duplicate."""
    client_old = _proc(
        "IF @ClientActive = 66\nBEGIN\n SELECT 'first'\nEND\n"
        "IF @ClientActive = 66\nBEGIN\n SELECT 'second'\nEND")
    out = gatewrap.preserve_down(_proc(PLAIN_CHAIN_BODY), client_old)
    assert out is not None
    assert out.count("@ClientActive = 66") == 1, out
    assert "SELECT 'first'" in out and "SELECT 'second'" not in out, out


def test_preserve_down_idempotent_second_pass_stable():
    """Applied twice: the second pass finds zero extra gates (its own output
    already carries them), returns None, so the caller keeps the merged def --
    output stable under the documented fallback semantics."""
    client_old = _proc(
        "IF @ClientActive = 66\nBEGIN\n UPDATE C SET X = 9\nEND")
    first = gatewrap.preserve_down(_proc(MASTER_WITH_ELSE), client_old)
    assert first is not None
    second = gatewrap.preserve_down(first, client_old)
    assert second is None                      # converged: nothing left to add
    assert first.count("@ClientActive = 66") == 1, first


def test_preserve_down_multiple_client_gates_keep_order():
    """Several client-only gates ride along together, in their original
    relative order."""
    client_old = _proc(
        "IF @ClientActive = 99\nBEGIN\n SELECT 'n'\nEND\n"
        "IF @ClientActive = 66\nBEGIN\n SELECT 's'\nEND")
    out = gatewrap.preserve_down(_proc(PLAIN_CHAIN_BODY), client_old)
    assert out is not None
    assert out.index("@ClientActive = 99") < out.index("@ClientActive = 66"), out
    assert "SELECT 'n'" in out and "SELECT 's'" in out, out


# ---------- cross-cutting contracts ----------

def test_outputs_are_new_strings_and_inputs_unchanged():
    """Neither function mutates its inputs (strings are immutable anyway):
    what is actually guaranteed is NEW output strings and byte-stable inputs."""
    m1 = _proc(CHAIN_BODY)
    out1 = gatewrap.splice_up(m1, [_delta("changed", "UPDATE C SET X = 9")], 66)
    assert out1 is not None and out1 is not m1 and out1 != m1
    assert m1 == _proc(CHAIN_BODY)
    m2, c2 = _proc(MASTER_WITH_ELSE), _proc(
        "IF @ClientActive = 66\nBEGIN\n UPDATE C SET X = 9\nEND")
    out2 = gatewrap.preserve_down(m2, c2)
    assert out2 is not None and out2 is not m2 and out2 != m2
    assert m2 == _proc(MASTER_WITH_ELSE)
    assert c2 == _proc("IF @ClientActive = 66\nBEGIN\n UPDATE C SET X = 9\nEND")


def test_unbalanced_begin_end_returns_none_for_both():
    """Untrusted structure degrades to fallback in BOTH directions -- never
    a splice over a broken frame, never a raise."""
    unbalanced_master = _proc("IF @ClientActive = 33\nBEGIN\nSELECT 'x'")
    assert gatewrap.splice_up(unbalanced_master,
                              [_delta("added", "SELECT 9")], 66) is None
    good_master = _proc(MASTER_WITH_ELSE)
    unbalanced_client = _proc("IF @ClientActive = 66\nBEGIN\nUPDATE C SET X = 9")
    assert gatewrap.preserve_down(good_master, unbalanced_client) is None
    good_client = _proc("IF @ClientActive = 66\nBEGIN\nUPDATE C SET X = 9\nEND")
    assert gatewrap.preserve_down(unbalanced_master, good_client) is None


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
