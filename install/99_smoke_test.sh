#!/usr/bin/env bash
# Smoke test: console up -> page and logo served -> API guard works -> demo readiness report.
# Start the console first with ./reset-demo.sh. Changes nothing in the database.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/env.sh" ] && . "$ROOT/env.sh"
PORT="${PORT:-$(python3 -c "import json; print(json.load(open('$ROOT/dashboard/config.json'))['port'])" 2>/dev/null || echo 8643)}"
URL="http://127.0.0.1:$PORT"
bad=0
check() {  # check <label> <expected-http-code> <curl args...>
  local label=$1 want=$2 got; shift 2
  got=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@") || got=000
  if [ "$got" = "$want" ]; then printf '  ok    %s\n' "$label"; else printf '  FAIL  %s (got HTTP %s, wanted %s)\n' "$label" "$got" "$want" >&2; bad=1; fi
}

echo "Console at $URL"
check "health endpoint answers"                200 "$URL/api/health"
check "page is served"                         200 "$URL/"
check "EDB logo is served"                     200 "$URL/static/edb_logo.png"
check "API refuses a foreign Host header"      403 -H "Host: evil.example" "$URL/api/health"
check "POST without the page's header refused" 403 -X POST "$URL/api/catalog"

echo "Demo readiness (read-only)"
if command -v psql >/dev/null 2>&1 && psql -X -tAc "SELECT 1" >/dev/null 2>&1; then
  if psql -X -tAc "SELECT 1 FROM pg_extension WHERE extname = 'aidb'" | grep -q 1; then
    "$ROOT/install/20_load_demo.sh" --check || bad=1
  else
    echo "  skipped: the aidb extension is not installed in this database (CREATE EXTENSION aidb CASCADE;)"
  fi
else
  echo "  skipped: psql cannot connect (set env.sh, see install/00_check_prereqs.sh)"
fi

echo
if [ "$bad" = 0 ]; then echo "Smoke test passed."; else echo "Smoke test found problems (see FAIL lines)." >&2; exit 1; fi
