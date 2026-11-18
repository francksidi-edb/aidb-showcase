-- 00_diagnose_egress.sql: read-only. Shows WHERE the egress settings come from.
-- A setting can be defined at several levels. From weakest to strongest:
--   postgresql.conf  <  postgresql.auto.conf (ALTER SYSTEM)  <  server start options  <  ALTER DATABASE SET  <  ALTER ROLE SET  <  ALTER ROLE ... IN DATABASE SET  <  SET in the session
-- If you changed a weaker level and nothing happened, a stronger level is overriding it.
\set ON_ERROR_STOP off

\echo '== What THIS session sees, and which level it came from'
SELECT name, setting, source, sourcefile, sourceline, pending_restart
FROM pg_settings
WHERE name IN ('aidb.egress_allowlist', 'edb.egress_allowlist', 'aidb.allow_insecure_egress')
ORDER BY name;

\echo '== Per-database and per-role overrides (ALTER DATABASE / ALTER ROLE ... SET)'
SELECT coalesce(d.datname, '(every database)') AS database,
       coalesce(r.rolname, '(every role)')     AS role,
       c AS setting
FROM pg_db_role_setting s
LEFT JOIN pg_database d ON d.oid = s.setdatabase
LEFT JOIN pg_roles    r ON r.oid = s.setrole
CROSS JOIN LATERAL unnest(s.setconfig) AS c
WHERE c ~ '^(aidb|edb)\.(egress_allowlist|allow_insecure_egress)='
ORDER BY 1, 2;

\echo '== Config files: was each line applied, or rejected? (superuser only)'
SELECT sourcefile, sourceline, name, setting, applied, error
FROM pg_file_settings
WHERE name IN ('aidb.egress_allowlist', 'edb.egress_allowlist', 'aidb.allow_insecure_egress')
ORDER BY seqno;

\echo '== postgresql.auto.conf as the server sees it (superuser only)'
SELECT pg_read_file(current_setting('data_directory') || '/postgresql.auto.conf') AS postgresql_auto_conf;

\echo '== You are connected as'
SELECT current_user AS role, current_database() AS database, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS is_superuser;

\set ON_ERROR_STOP on
