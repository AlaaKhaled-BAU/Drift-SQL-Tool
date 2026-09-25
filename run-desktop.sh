#!/usr/bin/env bash
# Desktop window for the drift tool (Flask + GTK WebKit2).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/.env"
  set +a
fi

# Prefer the 3.12 venv: system PyGObject matches that interpreter.
CANDIDATES=(
  "$ROOT/venv_desktop/bin/python"
  python3.12
  python3.13
  python3
)

PY=""
for candidate in "${CANDIDATES[@]}"; do
  if [[ -x "$candidate" ]] || command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" -c "import flask, sqlglot, gi" >/dev/null 2>&1; then
      PY="$candidate"
      break
    fi
  fi
done

if [[ -z "$PY" ]]; then
  echo "No Python can import flask, sqlglot, and gi (PyGObject)." >&2
  echo "Fix: $ROOT/venv_desktop/bin/python -m pip install flask pymssql sqlglot" >&2
  echo "Also need system packages: python3-gi gir1.2-webkit2-4.1" >&2
  exit 1
fi

exec "$PY" "$ROOT/desktop.py"
