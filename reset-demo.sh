#!/usr/bin/env bash
# reset-demo.sh - reset the AIDB showcase and (re)start the console.
#
# Usage:
#   ./reset-demo.sh                          # restart the console, keep the demo data
#   ./reset-demo.sh --wipe                   # also remove the demo objects and reload them first
#   ./reset-demo.sh --wipe --with-governance # ...and load the optional read-only-role demo (needs a superuser)
#   ./reset-demo.sh --port 8700              # listen on another port (default: dashboard/config.json)
#   ./reset-demo.sh --status                 # show console, port, database and demo readiness, change nothing
#
# --wipe runs sql/99_reset.sql, which drops the "shop" schema and the AIDB objects the demo created.
# It asks for confirmation (or pass --yes). Run it on a test database. Connection settings come from env.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$ROOT/.run"
PID_FILE="$RUN_DIR/console.pid"
LOG_FILE="$RUN_DIR/console.log"
APP="$ROOT/dashboard/app.py"
LOAD="$ROOT/install/20_load_demo.sh"
PORT=""
WIPE=0
GOV=0
YES=0
STATUS_ONLY=0

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)         usage 0 ;;
    --wipe)            WIPE=1 ;;
    --with-governance) GOV=1 ;;
    --yes)             YES=1 ;;
    --status)          STATUS_ONLY=1 ;;
    --port)            shift; PORT="${1:-}"; [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "--port needs a number" >&2; exit 1; } ;;
    *)                 echo "Unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done
if [[ $GOV -eq 1 && $WIPE -eq 0 ]]; then echo "--with-governance goes with --wipe (it loads the optional demo after the reload)." >&2; exit 1; fi

[[ -f "$ROOT/env.sh" ]] && . "$ROOT/env.sh"
[[ -n "$PORT" ]] || PORT=$(python3 -c "import json; print(json.load(open('$ROOT/dashboard/config.json'))['port'])" 2>/dev/null || echo 8643)
API="http://127.0.0.1:$PORT"

say() { printf '\n=== %s ===\n' "$*"; }
port_busy() { python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('127.0.0.1',$PORT))==0 else 1)"; }
console_pids() { pgrep -f "$APP" 2>/dev/null; }
healthy() { curl -s --max-time 3 "$API/api/health" 2>/dev/null | grep -q '"ok": *true'; }
target() { echo "${PGUSER:-$USER}@${PGHOST:-local socket}:${PGPORT:-5432}/${PGDATABASE:-${PGUSER:-$USER}}"; }
aidb_installed() { psql -X -tAc "SELECT 1 FROM pg_extension WHERE extname = 'aidb'" 2>/dev/null | grep -q 1; }
readiness() {  # the readiness report calls aidb functions, so only run it where the extension exists
  if aidb_installed; then "$LOAD" --check 2>&1 | tail -n 25
  else echo "aidb is not installed in this database. Run: CREATE EXTENSION aidb CASCADE;"; fi
}

status() {
  say "Console"
  if [[ -n "$(console_pids)" ]]; then echo "process: running (pid $(console_pids | tr '\n' ' '))"; else echo "process: not running"; fi
  if healthy; then echo "health:  answering on $API"; elif port_busy; then echo "health:  port $PORT is in use but this console is not answering"; else echo "health:  nothing listening on $PORT"; fi
  say "Database"
  echo "target:  $(target)"
  if command -v psql >/dev/null 2>&1 && v=$(psql -X -tAc "SHOW server_version" 2>&1); then
    echo "postgres: $v"
    a=$(psql -X -tAc "SELECT extversion FROM pg_extension WHERE extname = 'aidb'" 2>/dev/null)
    echo "aidb:     ${a:-not installed in this database}"
  else
    echo "postgres: cannot connect (check env.sh, or run install/00_check_prereqs.sh)"
  fi
  say "Demo readiness"
  readiness
}

if [[ $STATUS_ONLY -eq 1 ]]; then status; exit 0; fi

# --- 1. dependencies --------------------------------------------------------
say "1/5 Dependencies"
command -v psql >/dev/null 2>&1 || { echo "psql is not on PATH. Run install/00_check_prereqs.sh." >&2; exit 1; }
if ! v=$(psql -X -tAc "SHOW server_version" 2>&1); then
  echo "Cannot connect to $(target): $v" >&2
  echo "Nothing was stopped or changed. Fix env.sh (cp env.sh.example env.sh) and rerun." >&2
  exit 1
fi
echo "connected to $(target), Postgres $v"
if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
  echo "console environment missing, creating it"
  "$ROOT/install/10_setup_dashboard.sh" || { echo "Setup failed. Nothing else was changed." >&2; exit 1; }
fi
# Confirm a wipe now, before anything is stopped or changed, so a refusal leaves the running demo alone.
if [[ $WIPE -eq 1 ]]; then
  echo "--wipe removes the demo objects (schema shop, AIDB demo models, knowledge bases, tools, agents) in: $(target)"
  if [[ $YES -ne 1 ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Type the database name to confirm: " ans
      [[ "$ans" == "${PGDATABASE:-${PGUSER:-$USER}}" ]] || { echo "Not confirmed. Nothing was stopped or changed." >&2; exit 1; }
    else
      echo "Not a terminal: pass --yes to confirm. Nothing was stopped or changed." >&2; exit 1
    fi
  fi
fi

# --- 2. stop the console ----------------------------------------------------
say "2/5 Stop the console"
if [[ -f "$PID_FILE" ]]; then kill "$(cat "$PID_FILE")" 2>/dev/null; fi
pkill -f "$APP" 2>/dev/null
sleep 1
rm -f "$PID_FILE"
if port_busy; then
  echo "Something else still holds port $PORT. Stop it, or use --port <other>, then rerun." >&2
  exit 1
fi
echo "port $PORT is free"

# --- 3. data ----------------------------------------------------------------
say "3/5 Data"
if [[ $WIPE -eq 1 ]]; then
  "$LOAD" --reset || { echo "Reset failed, see above." >&2; exit 1; }
  if [[ $GOV -eq 1 ]]; then "$LOAD" --with-governance; else "$LOAD"; fi || {
    echo "Reload failed, see above. Fix the error and run $LOAD again (it is safe to repeat), then ./reset-demo.sh." >&2; exit 1; }
else
  echo "keeping existing data (use --wipe to remove and reload the demo objects)"
fi

# --- 4. start ---------------------------------------------------------------
say "4/5 Start the console"
mkdir -p "$RUN_DIR"
nohup "$ROOT/.venv/bin/python" "$APP" --port "$PORT" >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
for ((i = 0; i < 20; i++)); do healthy && break; sleep 1; done
if ! healthy; then
  echo "The console did not answer on $API after 20 s. Last log lines:" >&2
  tail -n 15 "$LOG_FILE" >&2
  exit 1
fi
echo "console started (pid $(cat "$PID_FILE")), log: $LOG_FILE"

# --- 5. verify --------------------------------------------------------------
say "5/5 Verify"
readiness
echo
echo "Console:        $API   (press Connect & scan, then Start the guided showcase)"
echo "Stop it:        ./stop-demo.sh"
echo "Full check:     ./install/99_smoke_test.sh"
