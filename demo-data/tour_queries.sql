-- tour_queries.sql: every ready-to-run query from the Showcase, in presentation order.
-- Paste a block into the Introspector SQL console and press Run (Ctrl+Enter / Cmd+Enter),
-- or run the whole file with:  psql -f tour_queries.sql
-- Blocks marked (calls a model) use a local model; the first call downloads its files.
-- Blocks marked (needs Allow writes) record a conversation, so they are commented out here.

-- ================================================================
-- Step 1 · AI inside: Your database already speaks AI
-- ================================================================

-- 1.1 How many commands does AIDB add?
-- You should see: One number. It is larger than the tile above because it also counts internal helper functions.
SELECT count(*) AS commands
FROM pg_proc
WHERE pronamespace = 'aidb'::regnamespace;

-- 1.2 List the commands that search by meaning
-- You should see: A list of names such as retrieve_text, retrieve_key and semantic_kb_search.
SELECT proname
FROM pg_proc
WHERE pronamespace = 'aidb'::regnamespace
  AND (proname LIKE '%semantic%' OR proname LIKE 'retrieve%')
ORDER BY 1;

-- ================================================================
-- Step 2 · Models: Choose the AI brain, local or hosted
-- ================================================================

-- 2.1 Which models are registered, and where do they run?
-- You should see: The built-in models (bert, clip, t5, llama and others), plus demo_hosted_gpt if you ran the demo setup. Providers ending in _local or starting with llamacpp run inside Postgres.
SELECT name, provider, credential
FROM aidb.list_models()
ORDER BY provider, name;

-- 2.2 Turn a sentence into numbers with the local bert model (calls a model)
-- You should see: 384. The sentence became a list of 384 numbers that capture its meaning. The first call downloads the model, so it can take a while.
SELECT array_length(
         aidb.encode_text('bert', 'warm jacket for a cold night'), 1
       ) AS numbers_per_sentence;

-- ================================================================
-- Step 3 · Keys: Passwords and keys stay locked away
-- ================================================================

-- 3.1 List the credentials (the key itself is never shown)
-- You should see: A row for demo_hosted_ai: endpoint api.openai.com, shared t, has_secret t. The built-in "none" credential is also listed.
SELECT name, owner, endpoint, shared, has_secret, can_use
FROM aidb.credentials
ORDER BY name;

-- 3.2 Scan for keys pasted into model settings by mistake
-- You should see: No rows. An empty result is the good answer.
SELECT * FROM aidb.audit_leaked_credentials();

-- 3.3 Where may AIDB connect?
-- You should see: The outbound allowlist and the insecure-egress switch. The allowlist is the list of hosts AIDB may call.
SELECT name, setting
FROM pg_settings
WHERE name LIKE '%egress%'
ORDER BY name;

-- ================================================================
-- Step 4 · Your data: Teach AI how your tables connect
-- ================================================================

-- 4.1 What has AIDB learned about the shop schema?
-- You should see: tables = 6 (customers, products, orders, order_items, support_tickets, kb_articles), a count of columns and relationships, and pending = 0. If tables is 0, wait a moment and run it again.
SELECT * FROM aidb.semantic_kb_stats(kb_name => 'shop_kb');

-- 4.2 How do the tables connect?
-- You should see: Links such as orders to customers and order_items to orders, with the join condition in the last column.
SELECT left_object, right_object, kind, join_expr
FROM aidb.list_relationships(kb_name => 'shop_kb');

-- 4.3 Find the route between two tables
-- You should see: A route that goes through shop.orders, with the join clause to use.
SELECT path_rank, hops, route, join_clause
FROM aidb.find_join_path(
       kb_name     => 'shop_kb',
       from_object => 'shop.order_items',
       to_object   => 'shop.customers');

-- ================================================================
-- Step 5 · Ask: Ask a question in everyday words
-- ================================================================

-- 5.1 Find the data by describing it (calls a model)
-- You should see: The email column of the customers table at or near the top, although the question never says "customers.email".
SELECT source_type, entity_type, relation_name, column_name, rank
FROM aidb.semantic_kb_search(
       query_text => 'customer email address',
       kb_name    => 'shop_kb',
       top_k      => 5);

-- 5.2 Find a help article by meaning (calls a model)
-- You should see: The "Returns and refunds" article (key 1) first, although it never uses the words "send back an item". A smaller distance means a closer match.
SELECT key, left(value, 100) AS passage, round(distance::numeric, 3) AS distance
FROM aidb.retrieve_text(
       (SELECT name FROM aidb.knowledge_bases WHERE name LIKE '%shop_articles_kb' LIMIT 1),
       'How do I send back an item?',
       topk => 3);

-- 5.3 Run a saved, trusted query for last month
-- You should see: Three customers: Maya Cohen, Noah Schmidt and Lucas Tanaka, each with 2 orders.
SELECT result
FROM aidb.execute_semantic_alias(
       alias_name => 'repeat_customers',
       args => jsonb_build_object(
         'month', EXTRACT(MONTH FROM current_date - INTERVAL '1 month')::int,
         'year',  EXTRACT(YEAR  FROM current_date - INTERVAL '1 month')::int));

-- ================================================================
-- Step 6 · Agents: Let an agent work through a task
-- ================================================================

-- 6.1 What may an assistant use?
-- You should see: Every tool in one list. Look for customer_open_tickets: a custom SQL tool, read_only t.
SELECT name, tool_type, read_only
FROM aidb.tools
ORDER BY tool_type, name;

-- 6.2 Which assistants exist?
-- You should see: shop_analyst (with its list of tools) and shop_helpdesk (which delegates to shop_analyst).
SELECT name, model, tools, delegates
FROM aidb.agents
ORDER BY name;

-- 6.3 Run one tool directly, with no AI involved
-- You should see: One open ticket for customer 2: "Boots arrived in the wrong size". This is exactly what an assistant would get back when it uses the tool.
SELECT aidb.run_tool(
         'customer_open_tickets',
         '{"customer_id": 2}'::jsonb);

-- 6.4 Ask the assistant a question (calls a model; needs Allow writes)
-- You should see: A short answer in the "message" column. This records the conversation, so it needs the Allow writes tick in the SQL console. The first call downloads the model, which can take several minutes. The small local model may give a rough answer.
-- SELECT *
-- FROM aidb.agent_converse(
--        agent_name => 'shop_analyst',
--        prompt     => 'How many customers are in each region?',
--        read_only  => true);

-- ================================================================
-- Step 7 · Health: Spot problems before users do
-- ================================================================

-- 7.1 Has any pipeline step failed?
-- You should see: No rows. An empty result means nothing has failed.
SELECT * FROM aidb.get_all_error_summaries();

-- 7.2 How is the document pipeline doing?
-- You should see: A status row for the pipeline. The source count should be 14, one per help article.
SELECT * FROM aidb.get_pipeline_metrics('shop_articles_pipe');

-- 7.3 Run AIDB's built-in health check
-- You should see: A report in JSON. Click the cell to read it in the side panel.
SELECT aidb.analyze_db_health();

-- ================================================================
-- Extras
-- ================================================================

-- Split a long text into passages (no model needed)
SELECT part_id, chunk
FROM aidb.chunk_text(
  'Boots should leave a thumb of space in front of your longest toe. Try them on in the afternoon, when feet are slightly larger. Wear the socks you plan to hike in. If you are between sizes, choose the larger one.',
  aidb.chunk_text_config(desired_length => 90));

-- Revenue for last month, from the second saved query
SELECT result FROM aidb.execute_semantic_alias(
  alias_name => 'monthly_revenue',
  args => jsonb_build_object('month', EXTRACT(MONTH FROM current_date - INTERVAL '1 month')::int,
                             'year',  EXTRACT(YEAR  FROM current_date - INTERVAL '1 month')::int));
