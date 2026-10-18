-- 06_optional_governance.sql   (optional; needs a superuser or an aidb_governance member)
-- Shows "assistants held to one role": an assistant whose every tool call runs as a
-- read-only database role, enforced by Postgres privileges rather than by the model.

\echo '== A read-only role that can see only the shop schema'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shop_readonly') THEN
    CREATE ROLE shop_readonly NOLOGIN;
  END IF;
END
$do$;
GRANT USAGE ON SCHEMA shop TO shop_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA shop TO shop_readonly;

-- Native tools need explicit grants (a custom SQL tool needs only the table privileges above).
GRANT USAGE ON SCHEMA aidb TO shop_readonly;
GRANT EXECUTE ON FUNCTION aidb.run_sql_query(TEXT) TO shop_readonly;

-- The caller of agent_converse must be a member of the purpose's role, and a governor registers purposes.
GRANT shop_readonly TO CURRENT_USER;
GRANT aidb_governance TO CURRENT_USER;

\echo '== Register the purpose'
DO $do$
BEGIN
  PERFORM aidb.create_purpose('shop_read_only', 'shop_readonly', 'Read-only access to the shop schema');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'create_purpose skipped: %', SQLERRM;
END
$do$;

\echo '== An assistant bound to that purpose'
DO $do$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.agents WHERE name = 'shop_readonly_agent') THEN
    FOR r IN SELECT * FROM aidb.create_agent(
      name         => 'shop_readonly_agent',
      instructions => 'Answer questions about the shop schema with read-only SQL queries. Keep answers short.',
      model        => 'qwen3.5-0.8b-Q8_0',
      tools        => ARRAY(SELECT name FROM aidb.tools WHERE name IN ('run_sql_query', 'customer_open_tickets')),
      purpose      => 'shop_read_only'
    ) LOOP
      IF r.error IS NOT NULL THEN RAISE WARNING 'create_agent shop_readonly_agent: %', r.error; END IF;
    END LOOP;
  END IF;
END
$do$;

SELECT name, model, tools FROM aidb.agents WHERE name = 'shop_readonly_agent';
