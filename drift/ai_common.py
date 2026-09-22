"""Shared, provider-agnostic helpers for the two AI modules (ai.py's advisory
triage, ai_merge.py's merge generation). Only the defensive JSON-extraction
logic lives here -- everything else about the two callers (models, prompts,
retry policy, risk profile) stays deliberately separate. One implementation
of "how do we pull JSON out of a possibly-messy LLM response" instead of two
copies that could silently drift apart.
"""
import json


def extract_json(text: str):
    """Defensive extraction, in the order actually observed live against
    OpenRouter/DeepSeek-shaped responses:
      1. the whole trimmed response, minus markdown fences (well-behaved models)
      2. the LAST balanced top-level {...} block (reasoning-then-JSON models
         put the answer at the end, after their chain-of-thought)
      3. the FIRST balanced top-level {...} block (fenced-JSON-with-trailing-
         prose models)
    Returns a dict or None -- never raises, so a model that returns garbage
    degrades to an "unstructured" raw-text path instead of a 500."""
    stripped = text.strip()
    for fence in ("```json", "```"):
        if stripped.startswith(fence):
            stripped = stripped[len(fence):]
        if stripped.endswith("```"):
            stripped = stripped[: -3]
    stripped = stripped.strip()
    candidate = _try_parse(stripped)
    if candidate is not None:
        return candidate

    blocks = _balanced_brace_blocks(text)
    for block in reversed(blocks):  # last-first: matches the reasoning-then-JSON pattern seen live
        candidate = _try_parse(block)
        if candidate is not None:
            return candidate
    return None


def _try_parse(s: str):
    try:
        v = json.loads(s)
        return v if isinstance(v, dict) else None
    except (json.JSONDecodeError, ValueError):
        return None


def _balanced_brace_blocks(text: str) -> list:
    blocks, depth, start = [], 0, None
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            if depth > 0:
                depth -= 1
                if depth == 0 and start is not None:
                    blocks.append(text[start : i + 1])
    return blocks
