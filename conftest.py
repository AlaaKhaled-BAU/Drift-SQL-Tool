"""pytest path bootstrap for drift-tool.

Engine modules under drift/ use flat imports in a few legacy scripts.
Tests use `from drift import …` and `from app import …` with the app root on
sys.path.
"""
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
_DRIFT = _ROOT / "drift"
for _p in (_ROOT, _DRIFT):
    _s = str(_p)
    if _s not in sys.path:
        sys.path.insert(0, _s)
