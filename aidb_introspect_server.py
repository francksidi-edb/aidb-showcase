#!/usr/bin/env python3
"""
aidb_introspect_server.py — local backend for the "AIDB 7.8 Introspector".

Same approach as aidb_server.py (Discover AIDB): every query runs through the
real `psql` binary, so it works on machines where security agents allow psql
but block other processes from reaching Postgres.

What it does (read-only by design):
  * /api/catalog     one JSON snapshot of the aidb schema straight from pg_catalog:
                     extension + versions, every function with its signature,
                     tables/views + columns, types/enums, aidb.* GUCs, workers.
  * /api/inventory   live objects via aidb's own list_* functions (models, KBs,
                     tools, volumes, aliases, pipeline errors, ...), run in parallel,
                     each one allowed to fail on its own.
  * /api/function    pg_get_functiondef() for one aidb function.
  * /api/browse      first N rows of one aidb table/view (credentials redacted).
  * /api/console     ad-hoc SQL in a READ ONLY transaction with a statement timeout.

Setup:
    pip install flask
    python3 aidb_introspect_server.py
    open http://127.0.0.1:8643

Binds to 127.0.0.1 only. Values that end up in SQL go through sql_literal()
or a strict identifier check — nothing is interpolated raw.
"""

import csv
import io
import json
import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor

from flask import Flask, request, jsonify, send_from_directory

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, ".aidb_introspect_config.json")
LEGACY_CONFIG_PATH = os.path.join(BASE_DIR, ".aidb_local_config.json")  # from Discover AIDB
PAGE = "aidb_introspect.html"
PORT = 8643
PSQL_TIMEOUT_SECONDS = 60

app = Flask(__name__, static_folder=None)
app.config["SEND_FILE_MAX_AGE_DEFAULT"] = 0
# Keep column order exactly as Postgres returns it.
app.config["JSON_SORT_KEYS"] = False
try:
    app.json.sort_keys = False
except AttributeError:
    pass

@app.before_request
def guard_local_api():
    """Only this page may call the API: reject other hosts (DNS rebinding) and
    cross-site POSTs (a custom header forces a CORS preflight we never approve)."""
    host = (request.host or "").split(":")[0]
    if host not in ("127.0.0.1", "localhost"):
        return jsonify({"ok": False, "error": "Forbidden host."}), 403
    if request.method == "POST" and request.headers.get("X-Requested-By") != "aidb-introspect":
        return jsonify({"ok": False, "error": "Missing X-Requested-By header."}), 403


IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
# Keys/columns whose values are never sent to the browser.
SECRET_KEY_RE = re.compile(
    r"(api_?key|secret|passw(or)?d|bearer|basic_auth|auth_header|^headers$|private_key|access_key)",
    re.I,
)
REDACTED = "••• redacted •••"
FLAG_KEY_RE = re.compile(r"^(has|is|can|uses?|requires?)_", re.I)   # has_secret = true/false, not a secret


def is_secret_key(key):
    key = str(key)
    return bool(SECRET_KEY_RE.search(key)) and not FLAG_KEY_RE.match(key)
# aidb.list_models() returns options as text[] like {"config={\"model\": ...}"}
KV_JSON_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(\{.*\}|\[.*\])$", re.S)


# -----------------------------------------------------------------------
# helpers (sql_literal / run_psql reused from aidb_server.py)
# -----------------------------------------------------------------------
def sql_literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, tuple)):
        return "ARRAY[" + ", ".join(sql_literal(v) for v in value) + "]"
    return "'" + str(value).replace("'", "''") + "'"


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def conn_info_from_request(body):
    return {
        "host": (body.get("host") or "").strip(),
        "port": (body.get("port") or "").strip(),
        "dbname": (body.get("dbname") or "").strip(),
        "user": (body.get("user") or "").strip(),
        "password": body.get("password") or "",
    }


def _notices(stderr):
    return [l.strip() for l in (stderr or "").splitlines()
            if l.strip().startswith(("WARNING", "NOTICE", "INFO"))]


def run_psql(conn_info, sql, mode="csv", read_only=False, timeout_ms=None):
    """Run SQL via psql.
    mode="csv"  -> rows as list of dicts + column order
    mode="json" -> query must return one json value; returned parsed
    Empty connection fields are simply omitted so psql falls back to
    PGHOST/PGPORT/... env vars or the local Unix socket (like plain `psql`)."""
    env = os.environ.copy()
    if conn_info.get("password"):
        env["PGPASSWORD"] = conn_info["password"]
    opts = []
    if read_only:
        opts.append("-c default_transaction_read_only=on")
    if timeout_ms:
        opts.append(f"-c statement_timeout={int(timeout_ms)}")
    if opts:
        env["PGOPTIONS"] = (env.get("PGOPTIONS", "") + " " + " ".join(opts)).strip()
    env["PGAPPNAME"] = "aidb_introspect"

    cmd = ["psql", "-X", "-v", "ON_ERROR_STOP=1"]
    for flag, key in (("-h", "host"), ("-p", "port"), ("-d", "dbname"), ("-U", "user")):
        if conn_info.get(key):
            cmd += [flag, conn_info[key]]
    cmd += ["--csv"] if mode == "csv" else ["-A", "-t", "-q"]
    cmd += ["-c", sql]

    try:
        r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=PSQL_TIMEOUT_SECONDS)
    except FileNotFoundError:
        return {"ok": False, "error": "`psql` isn't on PATH for this process. Install the Postgres client and make sure the shell that starts this server can run `psql`."}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"psql didn't respond within {PSQL_TIMEOUT_SECONDS}s."}

    notices = _notices(r.stderr)
    if r.returncode != 0:
        err = "\n".join(l for l in (r.stderr or "").splitlines() if l.strip() not in notices).strip()
        return {"ok": False, "error": err or f"psql exited with code {r.returncode}", "notices": notices}

    if mode == "json":
        out = r.stdout.strip()
        try:
            return {"ok": True, "data": json.loads(out) if out else None, "notices": notices}
        except json.JSONDecodeError as e:
            return {"ok": False, "error": f"Couldn't parse psql output as JSON: {e}", "notices": notices}

    reader = csv.DictReader(io.StringIO(r.stdout))
    rows = list(reader)
    return {"ok": True, "columns": reader.fieldnames or [], "rows": rows, "notices": notices}


def redact(value):
    """Recursively blank out anything stored under a secret-looking key."""
    if isinstance(value, dict):
        return {k: (REDACTED if is_secret_key(k) and v not in (None, "", {}, [], True, False) else redact(v))
                for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, str):
        m = KV_JSON_RE.match(value)
        if m:
            try:
                inner = json.loads(m.group(2))
                return m.group(1) + "=" + json.dumps(redact(inner), ensure_ascii=False)
            except (json.JSONDecodeError, TypeError):
                pass
    if isinstance(value, str) and value[:1] in "{[":
        try:
            parsed = json.loads(value)
            if isinstance(parsed, (dict, list)):
                return json.dumps(redact(parsed), ensure_ascii=False)
        except (json.JSONDecodeError, TypeError):
            pass
    return value


def parse_options(opts):
    """['config={"n_ctx": 512, ...}'] -> {'config': {'n_ctx': 512, ...}}"""
    out = {}
    for o in opts or []:
        m = KV_JSON_RE.match(o) if isinstance(o, str) else None
        if m:
            try:
                out[m.group(1)] = json.loads(m.group(2))
                continue
            except json.JSONDecodeError:
                pass
        out.setdefault("_unparsed", []).append(o)
    return out


def json_rows_sql(inner):
    return f"SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) FROM ({inner}) t"


# -----------------------------------------------------------------------
# catalog query — one round trip
# -----------------------------------------------------------------------
CATALOG_SQL = r"""
WITH ns AS (SELECT oid FROM pg_namespace WHERE nspname = 'aidb'),
ext AS (SELECT e.* FROM pg_extension e WHERE e.extname = 'aidb')
SELECT json_build_object(
  'extension', (SELECT json_build_object(
        'version', ext.extversion,
        'schema', (SELECT nspname FROM pg_namespace WHERE oid = ext.extnamespace),
        'owner', pg_get_userbyid(ext.extowner),
        'relocatable', ext.extrelocatable,
        'requires', (SELECT requires FROM pg_available_extension_versions v
                     WHERE v.name = 'aidb' AND v.version = ext.extversion LIMIT 1),
        'comment', obj_description(ext.oid, 'pg_extension')) FROM ext),
  'available', (SELECT json_build_object(
        'default_version', (SELECT default_version FROM pg_available_extensions WHERE name = 'aidb'),
        'versions', (SELECT coalesce(json_agg(version ORDER BY version), '[]'::json)
                     FROM pg_available_extension_versions WHERE name = 'aidb'))),
  'server', json_build_object(
        'version', version(),
        'server_version', current_setting('server_version'),
        'database', current_database(),
        'user', current_user,
        'is_superuser', (SELECT rolsuper FROM pg_roles WHERE rolname = current_user),
        'shared_preload_libraries', current_setting('shared_preload_libraries', true),
        'installed_extensions', (SELECT json_agg(json_build_object('name', extname, 'version', extversion) ORDER BY extname) FROM pg_extension)),
  'functions', (SELECT coalesce(json_agg(json_build_object(
        'oid', p.oid,
        'name', p.proname,
        'args', pg_get_function_arguments(p.oid),
        'identity_args', pg_get_function_identity_arguments(p.oid),
        'result', pg_get_function_result(p.oid),
        'kind', p.prokind,
        'lang', l.lanname,
        'volatility', p.provolatile,
        'security_definer', p.prosecdef,
        'strict', p.proisstrict,
        'returns_set', p.proretset,
        'nargs', p.pronargs,
        'ndefaults', p.pronargdefaults,
        'comment', obj_description(p.oid, 'pg_proc'),
        'owner', pg_get_userbyid(p.proowner),
        'can_execute', has_function_privilege(p.oid, 'EXECUTE'),
        'ext_member', EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass
                              AND d.objid = p.oid AND d.deptype = 'e')
      ) ORDER BY p.proname, p.oid), '[]'::json)
      FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
      WHERE p.pronamespace = (SELECT oid FROM ns)),
  'relations', (SELECT coalesce(json_agg(json_build_object(
        'name', c.relname,
        'kind', c.relkind,
        'est_rows', c.reltuples::bigint,
        'size', pg_total_relation_size(c.oid),
        'comment', obj_description(c.oid, 'pg_class'),
        'can_select', has_table_privilege(c.oid, 'SELECT'),
        'ext_member', EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass
                              AND d.objid = c.oid AND d.deptype = 'e'),
        'columns', (SELECT coalesce(json_agg(json_build_object(
                        'name', a.attname,
                        'type', format_type(a.atttypid, a.atttypmod),
                        'notnull', a.attnotnull,
                        'comment', col_description(c.oid, a.attnum)) ORDER BY a.attnum), '[]'::json)
                    FROM pg_attribute a
                    WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped)
      ) ORDER BY c.relname), '[]'::json)
      FROM pg_class c
      WHERE c.relnamespace = (SELECT oid FROM ns) AND c.relkind IN ('r','v','m','f','p')),
  'sequences', (SELECT coalesce(json_agg(c.relname ORDER BY c.relname), '[]'::json)
      FROM pg_class c WHERE c.relnamespace = (SELECT oid FROM ns) AND c.relkind = 'S'),
  'types', (SELECT coalesce(json_agg(json_build_object(
        'name', t.typname,
        'kind', t.typtype,
        'labels', (SELECT json_agg(enumlabel ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid = t.oid),
        'base', CASE WHEN t.typtype = 'd' THEN format_type(t.typbasetype, t.typtypmod) END,
        'check', CASE WHEN t.typtype = 'd' THEN (SELECT string_agg(pg_get_constraintdef(co.oid), ' AND ')
                                                 FROM pg_constraint co WHERE co.contypid = t.oid) END,
        'fields', CASE WHEN t.typtype = 'c' THEN (SELECT json_agg(json_build_object(
                        'name', a.attname, 'type', format_type(a.atttypid, a.atttypmod)) ORDER BY a.attnum)
                   FROM pg_attribute a WHERE a.attrelid = t.typrelid AND a.attnum > 0 AND NOT a.attisdropped) END,
        'comment', obj_description(t.oid, 'pg_type')
      ) ORDER BY t.typname), '[]'::json)
      FROM pg_type t
      WHERE t.typnamespace = (SELECT oid FROM ns)
        AND t.typtype IN ('e','d','c','b')
        AND t.typname NOT LIKE '\_%'
        AND (t.typtype <> 'c' OR EXISTS (SELECT 1 FROM pg_class rc
                                         WHERE rc.oid = t.typrelid AND rc.relkind = 'c'))),
  'settings', (SELECT coalesce(json_agg(json_build_object(
        'name', name, 'setting', setting, 'unit', unit, 'context', context, 'source', source,
        'boot_val', boot_val, 'reset_val', reset_val, 'vartype', vartype,
        'enumvals', enumvals, 'short_desc', short_desc) ORDER BY name), '[]'::json)
      FROM pg_settings WHERE name LIKE 'aidb.%'),
  'event_triggers', (SELECT coalesce(json_agg(json_build_object(
        'name', et.evtname, 'event', et.evtevent, 'enabled', et.evtenabled,
        'function', et.evtfoid::regproc::text, 'tags', et.evttags)), '[]'::json)
      FROM pg_event_trigger et JOIN pg_proc p ON p.oid = et.evtfoid
      WHERE p.pronamespace = (SELECT oid FROM ns)),
  'workers', (SELECT coalesce(json_agg(json_build_object(
        'pid', pid, 'backend_type', backend_type, 'application_name', application_name,
        'state', state, 'backend_start', backend_start, 'datname', datname)), '[]'::json)
      FROM pg_stat_activity
      WHERE (backend_type ILIKE '%aidb%' OR application_name ILIKE '%aidb%')
        AND application_name <> 'aidb_introspect')
);
"""



# -----------------------------------------------------------------------
# inventory — aidb's own list/stat functions, each independently
# -----------------------------------------------------------------------
INVENTORY = [
    ("models", "Models", "SELECT * FROM aidb.list_models()"),
    ("credentials", "Model credentials (7.8+)",
     "SELECT name, owner, endpoint, shared, has_secret, can_use FROM aidb.credentials"),
    ("list_providers", "Providers (7.8+)", "SELECT * FROM aidb.list_providers()"),
    ("providers", "Model providers view", "SELECT * FROM aidb.model_providers"),
    ("semantic_kbs", "Semantic KBs", "SELECT * FROM aidb.list_semantic_kbs()"),
    ("semantic_kb_stats", "Semantic KB stats",
     "SELECT k.name AS kb_name, s.* FROM aidb.list_semantic_kbs() k, LATERAL aidb.semantic_kb_stats(k.name) s"),
    ("native_tools", "Native & SQL tools",
     "SELECT name, tool_type, read_only, description FROM aidb.list_native_tools()"),
    ("mcp_tools", "Cached MCP tools",
     "SELECT name, tool_type, read_only, description FROM aidb.list_cached_mcp_tools()"),
    ("semantic_aliases", "Semantic aliases", "SELECT * FROM aidb.get_semantic_aliases()"),
    ("volumes", "Volumes", "SELECT * FROM aidb.list_volumes()"),
    ("pipeline_errors", "Pipeline error summary", "SELECT * FROM aidb.get_all_error_summaries()"),
    ("leaked_credentials", "Leaked-credential audit",
     "SELECT model_name, left(detected_key, 4) || '…' AS detected_key_prefix, detected_at "
     "FROM aidb.audit_leaked_credentials()"),
]


@app.route("/api/inventory", methods=["POST"])
def inventory():
    ci = conn_info_from_request(request.get_json(force=True))

    def one(item):
        key, label, inner = item
        r = run_psql(ci, json_rows_sql(inner), mode="json", read_only=True, timeout_ms=30000)
        entry = {"key": key, "label": label, "sql": inner + ";", "ok": r["ok"]}
        if r["ok"]:
            rows = r["data"] or []
            if key == "models":
                for row in rows:
                    row["options"] = parse_options(row.get("options"))
            entry["rows"] = redact(rows)
        else:
            entry["error"] = r["error"]
        return entry

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(one, INVENTORY))
    return jsonify({"ok": True, "items": results})


# -----------------------------------------------------------------------
# routes
# -----------------------------------------------------------------------
@app.route("/")
def index():
    resp = send_from_directory(BASE_DIR, PAGE, conditional=False, etag=False, last_modified=False)
    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    return resp


@app.route("/api/local-config", methods=["GET"])
def get_local_config():
    for path in (CONFIG_PATH, LEGACY_CONFIG_PATH):
        if os.path.exists(path):
            try:
                with open(path) as f:
                    c = json.load(f)
                keep = {k: c.get(k) for k in ("host", "port", "dbname", "user", "password") if c.get(k)}
                return jsonify({"ok": True, "config": keep, "from": os.path.basename(path)})
            except Exception as e:
                return jsonify({"ok": False, "error": f"Couldn't read {os.path.basename(path)}: {e}"})
    return jsonify({"ok": True, "config": {}})


@app.route("/api/local-config", methods=["POST"])
def save_local_config():
    body = request.get_json(force=True)
    keep = {k: body.get(k, "") for k in ("host", "port", "dbname", "user")}
    if body.get("savePassword"):
        keep["password"] = body.get("password", "")
    try:
        with open(CONFIG_PATH, "w") as f:
            json.dump(keep, f, indent=2)
        os.chmod(CONFIG_PATH, 0o600)
    except Exception as e:
        return jsonify({"ok": False, "error": f"Couldn't save settings: {e}"})
    return jsonify({"ok": True})


@app.route("/api/catalog", methods=["POST"])
def catalog():
    ci = conn_info_from_request(request.get_json(force=True))
    r = run_psql(ci, CATALOG_SQL, mode="json", read_only=True, timeout_ms=60000)
    if not r["ok"]:
        return jsonify(r)
    data = r["data"] or {}
    if not data.get("extension"):
        return jsonify({"ok": False, "notices": r["notices"],
                        "error": "Connected, but the aidb extension isn't installed in this database. "
                                 "Run CREATE EXTENSION aidb CASCADE; (or pick the right database)."})
    return jsonify({"ok": True, "catalog": data, "notices": r["notices"]})


@app.route("/api/function", methods=["POST"])
def function_def():
    body = request.get_json(force=True)
    ci = conn_info_from_request(body)
    try:
        oid = int(body.get("oid"))
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "oid must be an integer."})
    sql = f"""
        SELECT json_build_object(
          'definition', CASE WHEN p.prokind = 'a' THEN NULL ELSE pg_get_functiondef(p.oid) END,
          'aggregate', CASE WHEN p.prokind = 'a' THEN (
              SELECT json_build_object('transfn', a.aggtransfn::text, 'finalfn', a.aggfinalfn::text,
                                       'state_type', format_type(a.aggtranstype, NULL))
              FROM pg_aggregate a WHERE a.aggfnoid = p.oid) END,
          'probin', p.probin,
          'acl', p.proacl::text,
          'config', p.proconfig,
          'cost', p.procost,
          'rows', p.prorows,
          'parallel', p.proparallel)
        FROM pg_proc p
        WHERE p.oid = {oid} AND p.pronamespace = 'aidb'::regnamespace;
    """
    r = run_psql(ci, sql, mode="json", read_only=True, timeout_ms=15000)
    if r["ok"] and r["data"] is None:
        return jsonify({"ok": False, "error": "That function isn't in the aidb schema."})
    return jsonify(r)


@app.route("/api/browse", methods=["POST"])
def browse():
    body = request.get_json(force=True)
    ci = conn_info_from_request(body)
    name = body.get("relation", "")
    if not IDENT_RE.match(name):
        return jsonify({"ok": False, "error": "Relation name must be a plain identifier."})
    try:
        limit = max(1, min(int(body.get("limit", 50)), 500))
    except (TypeError, ValueError):
        limit = 50
    q = f"aidb.{quote_ident(name)}"
    sql = f"""
        SELECT json_build_object(
          'exists', EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = 'aidb'::regnamespace AND relname = {sql_literal(name)}),
          'total', (SELECT count(*) FROM {q}),
          'rows', (SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) FROM (SELECT * FROM {q} LIMIT {limit}) t));
    """
    r = run_psql(ci, sql, mode="json", read_only=True, timeout_ms=30000)
    if r["ok"]:
        r["data"]["rows"] = redact(r["data"]["rows"])
    return jsonify(r)


# -----------------------------------------------------------------------
# SQL editor
# -----------------------------------------------------------------------
# psql meta-commands the editor accepts: describe/list commands only.
# Anything that can touch files or the shell (\! \o \w \i \copy \g file, backticks, pipes) is refused.
META_ALLOWED = re.compile(
    r"^\\(d[A-Za-z]*\+?|l\+?|x(\s+(on|off|auto))?|conninfo|sf\+?|sv\+?|dconfig\+?)(\s+[^\\`|]*)?$"
)
# Stops accidental writes in read-only mode (not a security boundary against a determined user).
READ_ONLY_ESCAPES = re.compile(
    r"transaction_read_only|read\s+write|session\s+characteristics|^\s*(commit|end|rollback|abort|begin|start)\b",
    re.I,
)
TEXT_SECRET_RE = re.compile(
    r"((?:api_?key|secret(?:_key)?|passw(?:or)?d|bearer|basic_auth|auth_header|private_key|access_key)"
    r"(?:\\|\")*\s*[:=]\s*(?:\\|\")*)([^\"\\,{\[}\s][^\"\\,}]*)",
    re.I,
)
MAX_ROWS_PER_RESULT = 5000


def redact_text(text):
    return TEXT_SECRET_RE.sub(lambda m: m.group(1) + REDACTED, text or "")


def _strip_comments(s):
    return re.sub(r"--[^\n]*|/\*.*?\*/", "", s, flags=re.S).strip()


def split_script(text):
    """Split an editor buffer into SQL statements and psql meta-command lines,
    respecting quotes, dollar-quoting and comments."""
    stmts, buf, i, n = [], [], 0, len(text)

    def flush():
        stmt = "".join(buf).strip()
        buf.clear()
        if _strip_comments(stmt):
            stmts.append({"kind": "sql", "text": stmt})

    while i < n:
        c = text[i]
        if text.startswith("--", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            buf.append(text[i:j]); i = j; continue
        if text.startswith("/*", i):
            depth, j = 0, i
            while j < n:
                if text.startswith("/*", j): depth += 1; j += 2
                elif text.startswith("*/", j):
                    depth -= 1; j += 2
                    if depth == 0: break
                else: j += 1
            buf.append(text[i:j]); i = j; continue
        if c == "'":
            e_str = i > 0 and text[i - 1] in "eE" and (i < 2 or not (text[i - 2].isalnum() or text[i - 2] == "_"))
            j = i + 1
            while j < n:
                if e_str and text[j] == "\\": j += 2; continue
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'": j += 2; continue
                    break
                j += 1
            buf.append(text[i:j + 1]); i = j + 1; continue
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == '"':
                    if j + 1 < n and text[j + 1] == '"': j += 2; continue
                    break
                j += 1
            buf.append(text[i:j + 1]); i = j + 1; continue
        if c == "$" and not (i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_")):
            m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", text[i:])
            if m:
                tag = m.group(0)
                j = text.find(tag, i + len(tag))
                j = n if j < 0 else j + len(tag)
                buf.append(text[i:j]); i = j; continue
        if c == "\\":
            if _strip_comments("".join(buf)):
                raise ValueError("psql meta-commands must start on their own line (end the SQL before it with ';'). "
                                 "Inline commands such as \\g or \\gx aren't supported.")
            buf.clear()
            j = text.find("\n", i)
            j = n if j < 0 else j
            stmts.append({"kind": "meta", "text": text[i:j].strip()})
            i = j; continue
        if c == ";":
            flush(); i += 1; continue
        buf.append(c); i += 1
    flush()
    return stmts


def expand_record_call(stmt, expandable):
    """`SELECT aidb.list_models()` -> `SELECT * FROM aidb.list_models()` so records become columns."""
    m = re.match(r"^\s*select\s+(aidb\.([a-z_][a-z0-9_]*))\s*\(", stmt, re.I | re.S)
    if not m or m.group(2).lower() not in expandable:
        return None
    depth, j, inq = 0, m.end() - 1, False
    while j < len(stmt):
        ch = stmt[j]
        if ch == "'":
            inq = not inq
        elif not inq:
            if ch == "(": depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0: break
        j += 1
    if depth != 0 or stmt[j + 1:].strip():
        return None
    return "SELECT * FROM " + stmt[m.start(1):j + 1]


def run_script(conn_info, script, fmt, read_only, timeout_s, echo=False):
    env = os.environ.copy()
    if conn_info.get("password"):
        env["PGPASSWORD"] = conn_info["password"]
    opts = [f"-c statement_timeout={int(timeout_s) * 1000}"]
    if read_only:
        opts.append("-c default_transaction_read_only=on")
    env["PGOPTIONS"] = (env.get("PGOPTIONS", "") + " " + " ".join(opts)).strip()
    env["PGAPPNAME"] = "aidb_introspect"
    cmd = ["psql", "-X", "-P", "pager=off"]
    for flag, key in (("-h", "host"), ("-p", "port"), ("-d", "dbname"), ("-U", "user")):
        if conn_info.get(key):
            cmd += [flag, conn_info[key]]
    if fmt == "grid":
        cmd += ["--csv", "-q", "-v", "ON_ERROR_STOP=1"]
    elif echo:
        cmd += ["-a"]
    cmd += ["-f", "-"]
    try:
        streams = ({"stdout": subprocess.PIPE, "stderr": subprocess.PIPE} if fmt == "grid"
                   else {"stdout": subprocess.PIPE, "stderr": subprocess.STDOUT})  # keep errors in order
        return subprocess.run(cmd, env=env, input=script, text=True, timeout=timeout_s + 15, **streams), None
    except FileNotFoundError:
        return None, "`psql` isn't on PATH for this process."
    except subprocess.TimeoutExpired:
        return None, f"No answer from psql within {timeout_s + 15}s."


def _clean_err(line):
    return re.sub(r"^psql:<stdin>:\d+:\s*", "", line)


@app.route("/api/console", methods=["POST"])
def console():
    body = request.get_json(force=True)
    ci = conn_info_from_request(body)
    fmt = "text" if body.get("format") == "text" else "grid"
    read_only = not body.get("allowWrites")
    try:
        timeout_s = max(5, min(int(body.get("timeout", 30)), 900))
    except (TypeError, ValueError):
        timeout_s = 30
    expandable = {f.lower() for f in (body.get("expandFunctions") or []) if isinstance(f, str) and IDENT_RE.match(f)}
    do_expand = bool(body.get("expandRecords"))

    try:
        stmts = split_script(body.get("sql") or "")
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)})
    if not stmts:
        return jsonify({"ok": False, "error": "Type a query first."})

    for st in stmts:
        if st["kind"] == "meta" and not META_ALLOWED.match(st["text"]):
            return jsonify({"ok": False, "error": f"{st['text'].split()[0]} isn't allowed here. The editor accepts SQL plus "
                            "the psql describe commands (\\d…, \\l, \\sf, \\sv, \\x, \\conninfo)."})
        if st["kind"] == "sql" and read_only and READ_ONLY_ESCAPES.search(_strip_comments(st["text"])):
            return jsonify({"ok": False, "error": "Transaction control and read-only overrides are blocked in read-only mode. "
                            "Tick 'Allow writes' if you really mean it."})
        if st["kind"] == "sql" and do_expand:
            x = expand_record_call(st["text"], expandable)
            if x:
                st["expanded_from"] = st["text"]
                st["text"] = x

    def line(st):
        return st["text"] if st["kind"] == "meta" else st["text"] + ";"

    # ---------- psql text: exactly what a terminal session would print ----------
    if fmt == "text":
        script = ("\\x on\n" if body.get("vertical") else "") + "\n".join(line(st) for st in stmts) + "\n"
        proc, err = run_script(ci, script, "text", read_only, timeout_s, echo=bool(body.get("echo", True)))
        if err:
            return jsonify({"ok": False, "error": err})
        out = "\n".join(_clean_err(l) if l.startswith("psql:<stdin>") else l for l in proc.stdout.splitlines())
        return jsonify({"ok": True, "format": "text", "output": redact_text(out),
                        "statements": [{"text": st["text"], "expanded_from": st.get("expanded_from")} for st in stmts]})

    # ---------- grid: one CSV result per statement, split by markers ----------
    parts = ["\\timing on"]
    for k, st in enumerate(stmts):
        parts.append(f"\\echo @@AIDB_STMT_{k}@@")
        parts.append(line(st))
    proc, err = run_script(ci, "\n".join(parts) + "\n", "grid", read_only, timeout_s)
    if err:
        return jsonify({"ok": False, "error": err})

    chunks = re.split(r"^@@AIDB_STMT_(\d+)@@\n?", proc.stdout, flags=re.M)
    seen = {}
    for k in range(1, len(chunks), 2):
        seen[int(chunks[k])] = chunks[k + 1] if k + 1 < len(chunks) else ""

    stderr_lines = (proc.stderr or "").splitlines()
    notices = [_clean_err(l) for l in stderr_lines if re.search(r"(WARNING|NOTICE|INFO):", l)]
    error_text = "\n".join(_clean_err(l) for l in stderr_lines
                           if not re.search(r"(WARNING|NOTICE|INFO):", l) and l.strip())
    failed_at = max(seen) if (proc.returncode != 0 and seen) else None

    results = []
    for k, st in enumerate(stmts):
        res = {"index": k, "kind": st["kind"], "text": st["text"], "expanded_from": st.get("expanded_from")}
        if k not in seen:
            res["status"] = "skipped"
        elif k == failed_at:
            res["status"] = "error"
            res["error"] = redact_text(error_text) or f"psql exited with code {proc.returncode}"
        else:
            chunk = seen[k]
            lines = chunk.rstrip("\n").split("\n") if chunk.strip() else []
            ms = None
            while lines and re.match(r"^Time: [\d.,]+ ms", lines[-1]):
                ms = float(re.match(r"^Time: ([\d.,]+) ms", lines.pop()).group(1).replace(",", ""))
            res["ms"] = ms
            res["status"] = "ok"
            if not lines:
                res["columns"], res["rows"] = [], []
                res["no_result"] = True
            else:
                rdr = list(csv.reader(io.StringIO("\n".join(lines))))
                header, data = rdr[0], rdr[1:]
                if any(len(r) != len(header) for r in data):
                    res["raw"] = redact_text("\n".join(lines))   # e.g. \d table with several sections
                else:
                    secret_cols = {c for c in header if is_secret_key(c)}
                    rows = []
                    for r in data[:MAX_ROWS_PER_RESULT]:
                        rows.append([REDACTED if (header[i] in secret_cols and v) else redact_text(redact(v))
                                     for i, v in enumerate(r)])
                    res["columns"], res["rows"] = header, rows
                    res["total_rows"] = len(data)
                    res["truncated"] = len(data) > MAX_ROWS_PER_RESULT
        results.append(res)

    if proc.returncode != 0 and failed_at is None:
        return jsonify({"ok": False, "error": redact_text(error_text) or f"psql exited with code {proc.returncode}",
                        "notices": notices})
    return jsonify({"ok": True, "format": "grid", "results": results, "notices": notices})


if __name__ == "__main__":
    print("AIDB 7.8 Introspector — local console")
    print(f"Open http://127.0.0.1:{PORT} in your browser.")
    print("Read-only: every query runs with default_transaction_read_only=on.\n")
    app.run(host="127.0.0.1", port=PORT, debug=False)
