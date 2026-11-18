#!/usr/bin/env bash
# stop-demo.sh - stop the AIDB showcase console.
#
# Usage:
#   ./stop-demo.sh              # stop the console, keep the demo data in Postgres
#   ./stop-demo.sh --port 8700  # check this port when verifying (default: dashboard/config.json)
#
# Data is never deleted. To remove the demo objects, use: ./reset-demo.sh --wipe
# Postgres is not touched: this repository does not own your database server.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$ROOT/.run/console.pid"
APP="$ROOT/dashboard/app.py"
PORT=""

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --port)    shift; PORT="${1:-}"; [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "--port needs a number" >&2; exit 1; } ;;
    *)         echo "Unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done
[[ -n "$PORT" ]] || PORT=$(python3 -c "import json; print(json.load(open('$ROOT/dashboard/config.json'))['port'])" 2>/dev/null || echo 8643)

say() { printf '\n=== %s ===\n' "$*"; }
port_busy() { python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('127.0.0.1',$PORT))==0 else 1)"; }

say "1/2 Stop the console"
if [[ -f "$PID_FILE" ]]; then kill "$(cat "$PID_FILE")" 2>/dev/null; fi
pkill -f "$APP" 2>/dev/null
sleep 1
rm -f "$PID_FILE"
if pgrep -f "$APP" >/dev/null 2>&1; then
  pkill -9 -f "$APP" 2>/dev/null; sleep 1
fi
if pgrep -f "$APP" >/dev/null 2>&1; then echo "console still running (see: pgrep -af dashboard/app.py)" >&2; else echo "console stopped"; fi

say "2/2 Verify"
if port_busy; then
  echo "Something still listens on port $PORT. It is not this console (or it did not exit)." >&2
  exit 1
else
  echo "port $PORT is free"
fi
echo
echo "The demo data is still in Postgres. Start again with: ./reset-demo.sh"
exit 0
