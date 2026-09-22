"""ponytail: minimal self-check, not a framework. Run: python3.13 test_ai_merge.py
No real network calls -- _call is monkeypatched to simulate DeepSeek's
success/retryable/non-retryable response shapes, same pattern test_ai.py uses
for OpenRouter fixtures. JSON-extraction itself is covered by
test_ai_common.py (shared function, tested once, not duplicated here)."""
import ai_merge
import config


def test_build_prompt_includes_all_curated_pieces():
    delta = [{"tag": "added", "master": None,
              "client": {"kind": "IF", "condition": "@ClientActive = 165", "text": "IF @ClientActive = 165 BEGIN SELECT 1 END"}}]
    p = ai_merge.build_prompt("CREATE PROC X AS SELECT 1", "CREATE PROC X AS IF @ClientActive = 165 SELECT 1", delta, "165")
    assert "165" in p and "CREATE PROC X AS SELECT 1" in p and "@ClientActive = 165" in p, p
    assert "[added]" in p, p


def test_sanity_check_balanced_ok():
    r = ai_merge._sanity_check_sql("CREATE PROC X AS BEGIN IF @a=1 BEGIN SELECT 1 END END")
    assert r["looks_ok"], r


def test_sanity_check_unbalanced_flagged():
    r = ai_merge._sanity_check_sql("CREATE PROC X AS BEGIN SELECT 1")  # missing END
    assert not r["looks_ok"], r


def test_sanity_check_case_expression_not_mistaken_for_unbalanced():
    r = ai_merge._sanity_check_sql("CREATE PROC X AS SELECT CASE WHEN 1=1 THEN 'a' ELSE 'b' END")
    assert r["looks_ok"], r


def test_sanity_check_empty_flagged():
    r = ai_merge._sanity_check_sql("")
    assert not r["looks_ok"], r


def test_propose_merge_no_key_configured():
    orig = config.deepseek_key
    config.deepseek_key = lambda: None
    try:
        r = ai_merge.propose_merge("m", "c", [{"tag": "added", "client": {"kind": "SET", "condition": None, "text": "x"}}], "1")
        assert r == {"ok": False, "error": "No DeepSeek key configured (drift-tool/work/.deepseek_key missing)."}
    finally:
        config.deepseek_key = orig


def test_propose_merge_oversized_master_def_short_circuits():
    """Measured live (2026-07-29): a real 52KB proc silently truncated even
    at the 8192-token ceiling, since the prompt asks the model to echo the
    whole existing body back. Must refuse before spending a call, not
    discover the truncation after paying for it."""
    orig_key, orig_call = config.deepseek_key, ai_merge._call
    config.deepseek_key = lambda: "fake-key"
    calls = []
    ai_merge._call = lambda *a, **k: calls.append(1) or _GOOD_JSON
    try:
        big_master = "CREATE PROC X AS SELECT 1 -- " + ("x" * (ai_merge._MAX_MASTER_DEF_BYTES + 1))
        r = ai_merge.propose_merge(big_master, "c", _DELTA, "1")
        assert r["ok"] is False and "too large" in r["error"], r
        assert not calls, "must not call the network when master_def is oversized"
    finally:
        config.deepseek_key, ai_merge._call = orig_key, orig_call


def test_propose_merge_empty_delta_short_circuits():
    orig_key, orig_call = config.deepseek_key, ai_merge._call
    config.deepseek_key = lambda: "fake-key"
    calls = []
    ai_merge._call = lambda *a, **k: calls.append(1) or "{}"
    try:
        r = ai_merge.propose_merge("m", "c", [], "1")
        assert r["ok"] is False and "delta" in r["error"], r
        assert not calls, "must not call the network when there's no delta"
    finally:
        config.deepseek_key, ai_merge._call = orig_key, orig_call


_DELTA = [{"tag": "added", "master": None, "client": {"kind": "SET", "condition": None, "text": "SET @x = 1"}}]
_GOOD_JSON = '{"proposed_master_def": "CREATE PROC X AS SELECT 1", "approach": "wrapped_whole_body", "warning": ""}'


def test_propose_merge_retries_once_then_succeeds():
    orig_key, orig_call = config.deepseek_key, ai_merge._call
    config.deepseek_key = lambda: "fake-key"
    calls = []

    def fake_call(key, prompt, timeout, **kw):
        calls.append(1)
        if len(calls) == 1:
            raise ai_merge._RetryableError("HTTP 429")
        return _GOOD_JSON

    ai_merge._call = fake_call
    try:
        r = ai_merge.propose_merge("CREATE PROC X AS SELECT 1", "c", _DELTA, "1")
        assert len(calls) == 2, calls
        assert r["ok"] is True and r["approach"] == "wrapped_whole_body", r
        assert r["sanity_check"]["looks_ok"], r
    finally:
        config.deepseek_key, ai_merge._call = orig_key, orig_call


def test_propose_merge_both_attempts_fail_clean_error():
    orig_key, orig_call = config.deepseek_key, ai_merge._call
    config.deepseek_key = lambda: "fake-key"
    calls = []

    def fake_call(key, prompt, timeout, **kw):
        calls.append(1)
        raise ai_merge._RetryableError("HTTP 503")

    ai_merge._call = fake_call
    try:
        r = ai_merge.propose_merge("m", "c", _DELTA, "1")
        assert len(calls) == 2, calls
        assert r == {"ok": False, "error": "DeepSeek unavailable after retry: HTTP 503"}
    finally:
        config.deepseek_key, ai_merge._call = orig_key, orig_call


def test_propose_merge_non_retryable_error_no_second_attempt():
    orig_key, orig_call = config.deepseek_key, ai_merge._call
    config.deepseek_key = lambda: "fake-key"
    calls = []

    def fake_call(key, prompt, timeout, **kw):
        calls.append(1)
        raise RuntimeError("HTTP 401: bad key")

    ai_merge._call = fake_call
    try:
        r = ai_merge.propose_merge("m", "c", _DELTA, "1")
        assert len(calls) == 1, calls  # non-retryable -- must not retry
        assert r["ok"] is False and "401" in r["error"], r
    finally:
        config.deepseek_key, ai_merge._call = orig_key, orig_call


def test_propose_merge_unstructured_fallback_on_garbage_json():
    orig_key, orig_call = config.deepseek_key, ai_merge._call
    config.deepseek_key = lambda: "fake-key"
    ai_merge._call = lambda *a, **k: "I cannot answer this."
    try:
        r = ai_merge.propose_merge("m", "c", _DELTA, "1")
        assert r["ok"] is True and r.get("unstructured") is True, r
    finally:
        config.deepseek_key, ai_merge._call = orig_key, orig_call


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\n{len(tests)}/{len(tests)} passed")
