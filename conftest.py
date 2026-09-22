"""pytest path bootstrap for drift-tool.

Legacy modules under drift/ use flat imports (`import ai`). Newer tests use
`from drift import …` and `from app import …`, which need the repo root on
sys.path. Both layouts must work for `python3.13 -m pytest drift/ -q`.
"""
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
_DRIFT = _ROOT / "drift"
for _p in (_ROOT, _DRIFT):
    _s = str(_p)
    if _s not in sys.path:
        sys.path.insert(0, _s)
