"""ponytail: minimal self-check, not a framework. Run: python3.13 test_ai_common.py
No network here on purpose -- these are fixture strings captured from real
live OpenRouter responses during development (see ai.py's module docstring),
so the parser is tested against what models actually do, not a guess. Moved
from test_ai.py when extract_json moved to ai_common.py (shared with
ai_merge.py) -- same fixtures, same assertions, just testing the shared
function directly instead of through ai.py's old private name."""
from ai_common import extract_json


def test_clean_json_no_fences():
    text = '{"explanation": "x", "risk_flags": [], "equivalence_guess": {"is_likely_equivalent": true, "confidence": "high", "reasoning": "y"}, "recommendation": "skip_likely_noise", "recommendation_reasoning": "z"}'
    r = extract_json(text)
    assert r is not None and r["recommendation"] == "skip_likely_noise", r


def test_markdown_fenced_json():
    text = '```json\n{"explanation": "x", "recommendation": "back_port"}\n```'
    r = extract_json(text)
    assert r is not None and r["recommendation"] == "back_port", r


def test_reasoning_preamble_then_complete_json():
    """Real pattern observed live from nvidia/nemotron-3-super-120b-a12b:free:
    the model 'thinks out loud' first, THEN emits the JSON at the end. Must
    extract the trailing block, not fail because of the leading prose."""
    text = (
        "We need to output JSON with fields: explanation, risk_flags...\n"
        "So the change is likely functionally equivalent since assignments are independent.\n"
        '{"explanation": "Reordered two independent SET statements; no behavior change.", '
        '"risk_flags": ["order_change"], '
        '"equivalence_guess": {"is_likely_equivalent": true, "confidence": "high", "reasoning": "independent vars"}, '
        '"recommendation": "skip_likely_noise", "recommendation_reasoning": "pure reorder"}'
    )
    r = extract_json(text)
    assert r is not None and r["recommendation"] == "skip_likely_noise", r
    assert "Reordered" in r["explanation"], r


def test_truncated_response_with_no_complete_json_returns_none():
    """Real pattern observed live: same model, but cut off by max_tokens before
    ever reaching the JSON. There is no valid JSON to find -- must return None
    (triggering the 'unstructured, show raw text' path), not crash or hallucinate
    a parse."""
    text = (
        "We need to output JSON with fields: explanation, risk_flags (array of strings)...\n"
        "Recommendation: Since likely equivalent and low risk, could be \"skip_likely_noise\" or \"back_port\"? The"
    )
    r = extract_json(text)
    assert r is None, r


def test_garbage_text_returns_none():
    r = extract_json("I cannot answer this request.")
    assert r is None, r


def test_empty_string_returns_none():
    r = extract_json("")
    assert r is None


def test_last_block_wins_over_first_when_both_present():
    """A model that emits an incomplete draft JSON block, then corrects itself
    with a complete one -- the reasoning-then-JSON pattern generalized. Must
    pick the block that actually parses, preferring the later one."""
    text = '{"draft": true} then reconsidered: {"recommendation": "back_port", "explanation": "final"}'
    r = extract_json(text)
    assert r is not None and r["recommendation"] == "back_port", r


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
