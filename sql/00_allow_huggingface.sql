-- 00_allow_huggingface.sql: OPT-IN. Needs a superuser.
-- Adds Hugging Face to aidb.egress_allowlist so the built-in local models can download their files.
-- Your existing entries are kept. Nothing happens if there is no allowlist (no restriction) or if
-- huggingface.co is already on it.
--
-- Hosts added: huggingface.co and its subdomains, and hf.co and its subdomains
-- (Hugging Face redirects large files to CDN hosts, and every redirect is re-checked against the list).
-- ".example.com" matches subdomains only, so both the bare host and the subdomain form are listed.
--
-- WHERE the change is made:
--   1. Wherever the setting is already overridden for a database or role (ALTER DATABASE/ROLE ... SET):
--      those entries are updated, because they beat server-wide settings.
--   2. The current database, if it has no entry of its own. A database-level setting applies to new
--      connections and to AIDB's background workers for this database only, needs no reload, and
--      still works if the server-wide value is fixed by start-up options.
-- To undo:  ALTER DATABASE <db> RESET aidb.egress_allowlist;  (and ALTER ROLE ... RESET for any role entry)

SELECT coalesce(nullif(current_setting('aidb.egress_allowlist', true), ''),
                nullif(current_setting('edb.egress_allowlist', true), ''), '') AS cur \gset
SELECT (:'cur' = '' OR position('huggingface.co' in :'cur') > 0) AS nothing_to_do \gset
SELECT current_database() AS db \gset

\if :nothing_to_do
  \echo 'Nothing to change: there is no allowlist, or huggingface.co is already on it.'
\else
  \echo 'Current allowlist: ' :cur
  \set src unknown
  SELECT source AS src FROM pg_settings WHERE name = 'aidb.egress_allowlist' \gset
  \echo 'It currently comes from: ' :src

  \echo '== 1. Updating existing per-database / per-role entries (if any)'
  SELECT CASE
           WHEN s.setdatabase <> 0 AND s.setrole <> 0
             THEN format('ALTER ROLE %I IN DATABASE %I SET aidb.egress_allowlist = %L', r.rolname, d.datname, y.v)
           WHEN s.setdatabase <> 0
             THEN format('ALTER DATABASE %I SET aidb.egress_allowlist = %L', d.datname, y.v)
           ELSE format('ALTER ROLE %I SET aidb.egress_allowlist = %L', r.rolname, y.v)
         END AS command
  FROM pg_db_role_setting s
  CROSS JOIN LATERAL (SELECT substring(c from '^aidb\.egress_allowlist=(.*)$') AS old
                      FROM unnest(s.setconfig) AS c
                      WHERE c LIKE 'aidb.egress_allowlist=%') x
  CROSS JOIN LATERAL (SELECT x.old || ', huggingface.co, .huggingface.co, hf.co, .hf.co' AS v) y
  LEFT JOIN pg_database d ON d.oid = s.setdatabase
  LEFT JOIN pg_roles    r ON r.oid = s.setrole
  WHERE x.old IS NOT NULL AND position('huggingface.co' in x.old) = 0 \gexec

  \echo '== 2. Database-level setting for the current database (if it has none)'
  SELECT format('ALTER DATABASE %I SET aidb.egress_allowlist = %L', :'db',
                :'cur' || ', huggingface.co, .huggingface.co, hf.co, .hf.co') AS command
  WHERE NOT EXISTS (SELECT 1
                    FROM pg_db_role_setting s
                    WHERE s.setrole = 0
                      AND s.setdatabase = (SELECT oid FROM pg_database WHERE datname = :'db')
                      AND EXISTS (SELECT 1 FROM unnest(s.setconfig) c WHERE c LIKE 'aidb.egress_allowlist=%')) \gexec

  \echo 'Reconnecting so this session sees the new value...'
  \connect
  SHOW aidb.egress_allowlist;
  SELECT coalesce(nullif(current_setting('aidb.egress_allowlist', true), ''),
                  nullif(current_setting('edb.egress_allowlist', true), ''), '') AS now \gset
  SELECT (position('huggingface.co' in :'now') > 0) AS fixed \gset
  \if :fixed
    \echo 'OK: huggingface.co is now allowed for new connections to this database.'
  \else
    \echo 'The value is still not changed for this session. Something stronger is overriding it. Details:'
    \ir 00_diagnose_egress.sql
    \echo 'Send this output to whoever manages the server, or paste it to me.'
  \endif
\endif
