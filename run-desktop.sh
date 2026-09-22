#!/usr/bin/env bash
# Desktop window for the drift tool (GTK WebKit via pywebview).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Prefer the 3.12 venv: system PyGObject matches that interpreter.
# python3.13 can import pywebview but not GTK bindings on this machine.
CANDIDATES=(
  "$ROOT/venv_desktop/bin/python"
  python3.12
  python3.13
  python3
)

PY=""
for candidate in "${CANDIDATES[@]}"; do
  if [[ -x "$candidate" ]] || command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" -c "import webview, flask, sqlglot, gi" >/dev/null 2>&1; then
      PY="$candidate"
      break
    fi
  fi
done

if [[ -z "$PY" ]]; then
  echo "No Python can import webview, flask, sqlglot, and gi." >&2
  echo "Fix: $ROOT/venv_desktop/bin/python -m pip install flask pymssql sqlglot pywebview" >&2
  exit 1
fi

exec "$PY" "$ROOT/desktop.py"
