"""Decide which client_to_105 findings belong on the Client changes list."""

try:
    from .proc_filter import procedure_excluded
    from .proc_lens import compare_procs
except ImportError:
    from proc_filter import procedure_excluded
    from proc_lens import compare_procs

_NAME_FILTER_TYPES = {
    "SqlProcedure",
    "SqlScalarFunction",
    "SqlInlineTableValuedFunction",
    "SqlMultiStatementTableValuedFunction",
}
_NOISE = {"formatting_only", "no_difference"}


def classify_client_change(finding: dict, client_active_id, rules=None) -> dict:
    """Return list/kind/inspect/reason for one finding.

    list True means the name appears after Show changes.
    inspect "procedure" means the diff waits for Inspect.
    inspect "immediate" means a click opens the existing rich diff.
    """
    role = finding.get("role")
    if role == "only_on_other":
        return _off("only_on_105")
    if finding.get("category") in _NOISE:
        return _off("noise")
    scope = finding.get("scope") or {}
    if scope.get("irrelevant_to_client"):
        return _off("noise")
    if finding.get("type") in _NAME_FILTER_TYPES and procedure_excluded(
        finding.get("bare_name") or finding.get("name") or "", rules
    ):
        return _off("name_excluded")
    if role == "added":
        inspect = "procedure" if finding.get("type") == "SqlProcedure" else "immediate"
        return {"list": True, "kind": "added", "inspect": inspect, "reason": None}
    if finding.get("type") == "SqlTable" and role == "modified" and finding.get("columns"):
        cols = finding["columns"]
        if not cols.get("added") and not cols.get("retyped"):
            return _off("only_on_105")
    if finding.get("type") != "SqlProcedure" or role != "modified":
        inspect = "immediate" if role == "modified" else None
        listed = role == "modified"
        return {
            "list": listed,
            "kind": "modified" if listed else "skipped",
            "inspect": inspect if listed else None,
            "reason": None,
        }
    if client_active_id is None or str(client_active_id).strip() == "":
        return _off("needs_client_active", "Enter a ClientActive ID to compare procedures.")
    lens = compare_procs(
        finding.get("master_def") or "",
        finding.get("client_def") or "",
        client_active_id,
        "active_read",
        direction="client_to_105",
    )
    if not lens.get("ok"):
        return _off("trim_failed", lens.get("reason") or "trim failed")
    if lens.get("identical"):
        return _off("identical_after_trim")
    return {"list": True, "kind": "trimmed_diff", "inspect": "procedure", "reason": None}


def _off(kind: str, reason: str | None = None) -> dict:
    return {"list": False, "kind": kind, "inspect": None, "reason": reason}
