#!/usr/bin/env bash
# Step 20 - load the Northwind Outdoors demo (sql/*.sql) into the database psql connects to.
# Connection settings come from env.sh in the repository root, or your own PG* variables.
# Run it from anywhere; it finds the sql/ folder next to install/.
#
#   ./install/20_load_demo.sh                    sample data + models + semantic layer + documents + agents
#   ./install/20_load_demo.sh --with-governance  also run the optional read-only-role demo (needs a superuser)
#   ./install/20_load_demo.sh --check            only report what is ready
#   ./install/20_load_demo.sh --allow-huggingface  add huggingface.co to aidb.egress_allowlist (superuser)
#   ./install/20_load_demo.sh --diagnose-egress  show where the egress settings come from (read-only)
#   ./install/20_load_demo.sh --from 03          resume at step 03 (skips 01 and 02, so loaded data is not dropped and recreated)
#   ./install/20_load_demo.sh --force            continue even if the preflight says downloads are blocked
#   ./install/20_load_demo.sh --reset            remove everything the demo created
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQL_DIR="$ROOT/sql"
[ -d "$SQL_DIR" ] || { echo "Cannot find $SQL_DIR (expected next to install/)." >&2; exit 1; }
cd "$SQL_DIR"

# Connection settings: use env.sh from the repository root, if present
if [ -f "$ROOT/env.sh" ]; then
  . "$ROOT/env.sh"
  echo "Connection settings loaded from $ROOT/env.sh -> ${PGUSER:-?}@${PGHOST:-local socket}:${PGPORT:-5432}/${PGDATABASE:-?}"
fi

CHECK=0; RESET=0; ALLOW_HF=0; GOV=0; FORCE=0; DIAG=0
FROM=1
while [ $# -gt 0 ]; do
  a="$1"; shift
  case "$a" in
    --from) [ $# -gt 0 ] || { echo "--from needs a step number, for example: --from 03" >&2; exit 2; }
            FROM=$((10#$1)); shift ;;
    --check) CHECK=1 ;;
    --reset) RESET=1 ;;
    --allow-huggingface) ALLOW_HF=1 ;;
    --with-governance) GOV=1 ;;
    --force) FORCE=1 ;;
    --diagnose-egress) DIAG=1 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

run() { echo; echo "=== $1"; psql -X -v ON_ERROR_STOP=1 -f "$1"; }

# All SQL files must be in sql/. Check before running anything.
need="00_preflight.sql 01_sample_data.sql 02_models_and_credentials.sql 03_semantic_layer.sql 04_documents.sql 05_agents_and_tools.sql check_ready.sql 99_reset.sql"
[ "$ALLOW_HF" = 1 ] && need="$need 00_allow_huggingface.sql 00_diagnose_egress.sql"
[ "$DIAG" = 1 ] && need="$need 00_diagnose_egress.sql"
[ "$GOV" = 1 ] && need="$need 06_optional_governance.sql"
missing=""
for f in $need; do [ -f "$f" ] || missing="$missing $f"; done
if [ -n "$missing" ]; then
  echo "These files are missing from $(pwd):$missing" >&2
  echo "Clone the whole repository so every .sql file is in $SQL_DIR." >&2
  exit 1
fi

if [ "$CHECK" = 1 ]; then run check_ready.sql; exit 0; fi
if [ "$DIAG" = 1 ]; then run 00_diagnose_egress.sql; exit 0; fi
if [ "$RESET" = 1 ]; then run 99_reset.sql; exit 0; fi
if [ "$ALLOW_HF" = 1 ]; then
  run 00_allow_huggingface.sql
  echo; echo "Now run: ./install/20_load_demo.sh"; exit 0
fi

psql -X -tAc "SELECT 1 FROM pg_extension WHERE extname = 'aidb'" | grep -q 1 \
  || { echo "The aidb extension is not installed in this database. Run: CREATE EXTENSION aidb CASCADE;"; exit 1; }

# Preflight: stop here if the server would refuse the model downloads, instead of failing halfway through.
echo; echo "=== 00_preflight.sql"
pre=$(psql -X -v ON_ERROR_STOP=1 -f 00_preflight.sql 2>&1) || { echo "$pre"; exit 1; }
echo "$pre"
if echo "$pre" | grep -q "an egress allowlist is set"; then
  if [ "$FORCE" = 1 ]; then
    echo; echo "Continuing because of --force. Steps that use a local model will fail until Hugging Face is allowed."
  else
    cat <<'MSG'

Stopping before anything is created: this server only allows outbound connections to the hosts on
aidb.egress_allowlist, and the local models must download their files from Hugging Face once.

Choose one:
  1. Allow Hugging Face (superuser; keeps your existing entries):  ./install/20_load_demo.sh --allow-huggingface
     (if that does not change anything, run:  ./install/20_load_demo.sh --diagnose-egress)
  2. Ask the server owner to add: huggingface.co, .huggingface.co, hf.co, .hf.co
  3. Work offline: copy the model files into the server's cache (see docs/egress.md)
Then run this script again. To load only the plain sample data now, use --force.
MSG
    exit 1
  fi
fi

[ "$FROM" -le 1 ] && run 01_sample_data.sql
[ "$FROM" -le 2 ] && run 02_models_and_credentials.sql
[ "$FROM" -le 3 ] && run 03_semantic_layer.sql
[ "$FROM" -le 4 ] && run 04_documents.sql
[ "$FROM" -le 5 ] && run 05_agents_and_tools.sql
[ "$GOV" = 1 ] && run 06_optional_governance.sql

run check_ready.sql
echo
echo "Done. Start the console with ./reset-demo.sh and open the Showcase at http://127.0.0.1:8643"
