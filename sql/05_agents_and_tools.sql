-- 05_agents_and_tools.sql   (Showcase step 6)
-- One custom tool, one assistant that can use tools, and a second assistant that delegates to it.
--
-- Default model: AIDB's built-in 'qwen3.5-0.8b-Q8_0' (local, no key, supports tool calling).
-- It is small, so expect simple answers. For better results, register a stronger model and run:
--   SELECT * FROM aidb.update_agent('shop_analyst', model => 'your_model_name');
-- The first agent_converse call downloads the model files from Hugging Face (several hundred MB).

\echo '== A custom tool: look up open support tickets for a customer'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.tools WHERE name = 'customer_open_tickets') THEN
    PERFORM aidb.create_sql_tool(
      name          => 'customer_open_tickets',
      description   => 'List the open support tickets for one customer, newest first, looked up by customer id.',
      sql_statement => 'SELECT t.id, t.opened_at, t.subject, t.status FROM shop.support_tickets t WHERE t.customer_id = ${customer_id} AND t.status = ''open'' ORDER BY t.opened_at DESC',
      params        => aidb.tool_params(
                         aidb.tool_param('customer_id', 'INT', 'The customer id.')),
      read_only     => true
    );
  END IF;
END
$do$;

\echo '== An assistant that can discover tables, search the schema and run read-only queries'
DO $do$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.agents WHERE name = 'shop_analyst') THEN
    FOR r IN SELECT * FROM aidb.create_agent(
      name           => 'shop_analyst',
      instructions   => 'You answer questions about the shop schema: customers, products, orders, order_items and support_tickets. First discover the right tables and columns with the catalog and schema-search tools, then run a read-only SQL query and answer in one or two plain sentences. Never guess a table or column name.',
      model          => 'qwen3.5-0.8b-Q8_0',
      tools          => ARRAY(SELECT name FROM aidb.tools
                              WHERE name IN ('run_sql_query', 'catalog_list_objects', 'catalog_get_object_details',
                                             'semantic_kb_search', 'customer_open_tickets')),
      max_iterations => 8
    ) LOOP
      IF r.error IS NOT NULL THEN RAISE WARNING 'create_agent shop_analyst: %', r.error; END IF;
    END LOOP;
  END IF;
END
$do$;

\echo '== A front-desk assistant that hands data questions to the analyst'
DO $do$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.agents WHERE name = 'shop_helpdesk') THEN
    FOR r IN SELECT * FROM aidb.create_agent(
      name         => 'shop_helpdesk',
      instructions => 'You help staff with general questions and hand questions about orders, customers or tickets to the analyst.',
      model        => 'qwen3.5-0.8b-Q8_0',
      delegates    => ARRAY['shop_analyst']
    ) LOOP
      IF r.error IS NOT NULL THEN RAISE WARNING 'create_agent shop_helpdesk: %', r.error; END IF;
    END LOOP;
  END IF;
END
$do$;

\echo '== Agents and the tools each one may use'
SELECT name, model, tools, delegates FROM aidb.agents ORDER BY name;

\echo '== Tools the analyst was NOT given because they are not in this build (should be empty)'
SELECT t AS missing_tool
FROM unnest(ARRAY['run_sql_query', 'catalog_list_objects', 'catalog_get_object_details',
                  'semantic_kb_search', 'customer_open_tickets']) AS t
WHERE t NOT IN (SELECT name FROM aidb.tools);

-- Ask a question from psql (downloads the model on first use; can take a few minutes):
--   SELECT * FROM aidb.agent_converse('shop_analyst', 'How many customers are in each region?', read_only => true);
-- Or use the Showcase, step 6.
