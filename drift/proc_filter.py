"""Procedure-name exclusions for Full Update.

Callers that emit DROP of a procedure or function must skip the name when
procedure_excluded returns true, and must skip DROP TYPE instead of dropping
that referencer. The Procedures filter dialog renders default_rules() and
must not copy these tuples.

Contains and Starts with both exclude. Rules combine with OR. A blank value
matches nothing. An unknown op does not match. Tokens are not anchored.
This list is not exclude-from-drift.txt.
"""

_CONTAINS = (
    "alpha", "sap", "bonanza", "integ", "mms", "jawad", "hammoudeh",
    "technical", "niroukh", "api", "medical", "poa", "tax", "asset",
    "thuraya", "cmms", "memo",
)
_STARTS = ("sp", "oms", "sms", "owms")


def default_rules() -> list[dict]:
    """Dialog rows for one Full Update run. A new list on every call."""
    rules = [{"op": "contains", "value": value} for value in _CONTAINS]
    rules.extend({"op": "starts_with", "value": value} for value in _STARTS)
    return rules


def procedure_excluded(bare_name: str, rules: list[dict] | None = None) -> bool:
    """True when a procedure or function name must not be dropped.

    rules=None uses default_rules(). Pass a copied list with a row removed
    to drop that token for this run only.
    """
    if rules is None:
        rules = default_rules()
    name = _bare(bare_name)
    for rule in rules:
        if _matches(name, rule):
            return True
    return False


def _bare(name: str) -> str:
    """Object name, casefolded, after one bracket layer and the last dot.

    [schema].[name] follows compare.bare_name (split on '].['). schema.name
    uses the segment after the last dot, then one surrounding [] layer.
    """
    text = name.strip()
    if "].[" in text:
        text = text.split("].[")[-1]
        if text.endswith("]"):
            text = text[:-1]
    elif len(text) >= 2 and text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    if "." in text:
        text = text.rsplit(".", 1)[-1]
        if len(text) >= 2 and text.startswith("[") and text.endswith("]"):
            text = text[1:-1]
    return text.casefold()


def _matches(name: str, rule: dict) -> bool:
    if not isinstance(rule, dict):
        return False
    value = rule.get("value")
    if not isinstance(value, str):
        return False
    token = value.strip().casefold()
    if not token:
        return False
    op = rule.get("op")
    if op == "contains":
        return token in name
    if op == "starts_with":
        return name.startswith(token)
    return False
