#!/usr/bin/env bash
# Step 00 - check the machine before installing anything. Read-only: changes nothing.
# Needs: python3 (3.8+), the psql client, and a Postgres database you can reach.
# Connection settings come from env.sh in the repository root, or your own PG* variables.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/env.sh" ] && . "$ROOT/env.sh"

bad=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; bad=1; }
warn() { printf '  warn  %s\n' "$*"; }

echo "Connection: ${PGUSER:-$USER}@${PGHOST:-local socket}:${PGPORT:-5432}/${PGDATABASE:-${PGUSER:-$USER}}"
[ -f "$ROOT/env.sh" ] || warn "no env.sh found. Using your PG* variables or psql defaults (cp env.sh.example env.sh to set them)"

echo "Tools"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'; then
  ok "python3 $(python3 -c 'import platform; print(platform.python_version())')"
else
  fail "python3 3.8 or newer is required"
fi
python3 -c 'import venv' 2>/dev/null && ok "python3 venv module" || fail "python3 venv module is missing (Debian/Ubuntu: apt install python3-venv)"
if command -v psql >/dev/null 2>&1; then ok "$(psql --version)"; else fail "psql is not on PATH (the console runs every query through it)"; fi

echo "Database"
if command -v psql >/dev/null 2>&1; then
  if ver=$(psql -X -tAc "SHOW server_version" 2>&1); then
    ok "connected, Postgres $ver"
    inst=$(psql -X -tAc "SELECT extversion FROM pg_extension WHERE extname = 'aidb'" 2>/dev/null)
    avail=$(psql -X -tAc "SELECT default_version FROM pg_available_extensions WHERE name = 'aidb'" 2>/dev/null)
    if [ -n "$inst" ]; then
      ok "aidb $inst is installed in this database"
    elif [ -n "$avail" ]; then
      warn "aidb $avail is available but not installed here. Run: CREATE EXTENSION aidb CASCADE;"
    else
      fail "the aidb extension is not available on this server (install the EDB AIDB package first)"
    fi
  else
    fail "cannot connect: $ver"
  fi
fi

echo
if [ "$bad" = 0 ]; then echo "Ready. Next: ./install/10_setup_dashboard.sh"; else echo "Fix the FAIL lines above, then run this again." >&2; exit 1; fi
