#!/usr/bin/env bash
# Loads the Northwind Outdoors demo into the database psql connects to.
# Connection settings come from env.sh (this folder or the one above) or your own PG* variables.
#
#   bash run_demo_setup.sh                    sample data + models + semantic layer + documents + agents
#   bash run_demo_setup.sh --with-governance  also run the optional read-only-role demo (needs a superuser)
#   bash run_demo_setup.sh --check            only report what is ready
#   bash run_demo_setup.sh --allow-huggingface  add huggingface.co to aidb.egress_allowlist (superuser)
#   bash run_demo_setup.sh --diagnose-egress  show where the egress settings come from (read-only)
#   bash run_demo_setup.sh --from 03          resume at step 03 (skips 01 and 02, so loaded data is not dropped and recreated)
#   bash run_demo_setup.sh --force            continue even if the preflight says downloads are blocked
#   bash run_demo_setup.sh --reset            remove everything the demo created
set -euo pipefail
cd "$(dirname "$0")"

# Connection settings: use env.sh from this folder or the one above it, if present
for e in ./env.sh ../env.sh; do
  if [ -f "$e" ]; then
    . "$e"
    echo "Connection settings loaded from $e -> ${PGUSER:-?}@${PGHOST:-local socket}:${PGPORT:-5432}/${PGDATABASE:-?}"
    break
  fi
done

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

# All script files must sit in this folder next to run_demo_setup.sh. Check before running anything.
need="00_preflight.sql 01_sample_data.sql 02_models_and_credentials.sql 03_semantic_layer.sql 04_documents.sql 05_agents_and_tools.sql check_ready.sql 99_reset.sql"
[ "$ALLOW_HF" = 1 ] && need="$need 00_allow_huggingface.sql 00_diagnose_egress.sql"
[ "$DIAG" = 1 ] && need="$need 00_diagnose_egress.sql"
[ "$GOV" = 1 ] && need="$need 06_optional_governance.sql"
missing=""
for f in $need; do [ -f "$f" ] || missing="$missing $f"; done
if [ -n "$missing" ]; then
  echo "These files are missing from $(pwd):$missing" >&2
  echo "Copy the whole demo-data folder (or clone the whole repository) so every .sql file sits next to this script." >&2
  exit 1
fi

if [ "$CHECK" = 1 ]; then run check_ready.sql; exit 0; fi
if [ "$DIAG" = 1 ]; then run 00_diagnose_egress.sql; exit 0; fi
if [ "$RESET" = 1 ]; then run 99_reset.sql; exit 0; fi
if [ "$ALLOW_HF" = 1 ]; then
  run 00_allow_huggingface.sql
  echo; echo "Now run: bash run_demo_setup.sh"; exit 0
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
  1. Allow Hugging Face (superuser; keeps your existing entries):  bash run_demo_setup.sh --allow-huggingface
     (if that does not change anything, run:  bash run_demo_setup.sh --diagnose-egress)
  2. Ask the server owner to add: huggingface.co, .huggingface.co, hf.co, .hf.co
  3. Work offline: copy the model files into the server's cache (see README section 9)
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
echo "Done. Start the Introspector (../start.sh) and open the Showcase."
