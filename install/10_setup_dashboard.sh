#!/usr/bin/env bash
# Step 10 - create the Python virtual environment (.venv) and install the console's requirements.
# Safe to run again. Nothing is installed outside the repository folder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }
[ -d "$ROOT/.venv" ] || python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/pip" install -q --upgrade pip
"$ROOT/.venv/bin/pip" install -q -r "$ROOT/dashboard/requirements.txt"
echo "Console environment ready in $ROOT/.venv"
echo "Next: ./install/20_load_demo.sh   (loads the demo data), then ./reset-demo.sh"
