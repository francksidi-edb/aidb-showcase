#!/usr/bin/env bash
# AIDB Introspector — needs Python 3 and the `psql` client on PATH.
set -e
cd "$(dirname "$0")"
# Connection settings (PGHOST, PGUSER, ...) if env.sh sits next to this script
if [ -f ./env.sh ]; then . ./env.sh; fi
[ -d venv ] || python3 -m venv venv
source venv/bin/activate
pip install -q flask
python3 aidb_introspect_server.py
