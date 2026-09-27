#!/usr/bin/env bash
# Linux twin of build-windows.bat: dist/DriftTool/DriftTool from a clean venv.
set -euo pipefail
cd "$(dirname "$0")"

[[ -x .build-venv/bin/python ]] || python3 -m venv .build-venv
.build-venv/bin/python -m pip install -q --upgrade pip
.build-venv/bin/python -m pip install -q -r requirements.txt pyinstaller
.build-venv/bin/python -m PyInstaller --noconfirm --clean drift-tool.spec

[[ -f .env ]] && cp .env dist/DriftTool/.env
echo "Built: dist/DriftTool/DriftTool"
