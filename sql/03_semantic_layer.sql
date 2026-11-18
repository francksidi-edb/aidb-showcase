-- 03_semantic_layer.sql   (Showcase steps 4 and 5, "Find data")
-- Indexes the shop schema so questions in plain English map to the right tables,
-- and saves two trusted, reusable queries (semantic aliases).
-- Placeholders such as ${month} reach the query as text, so the queries cast them: ${month}::int.
-- Safe to run again: the saved queries are recreated.
-- First run downloads the local 'bert' model if step 2 has not already.

\echo '== Create the semantic knowledge base over the shop schema'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.list_semantic_kbs() WHERE name = 'shop_kb') THEN
    PERFORM aidb.create_semantic_kb(
      name            => 'shop_kb',
      model           => 'bert',
      schemas         => ARRAY['shop'],
      auto_processing => 'Live'
    );
  END IF;
END
$do$;

\echo '== What was indexed (if "tables" is 0 or "pending" is above 0, wait a moment and run this again)'
SELECT * FROM aidb.semantic_kb_stats(kb_name => 'shop_kb');

\echo '== Trusted query 1: revenue for a month'
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM aidb.get_semantic_aliases() WHERE name = 'monthly_revenue') THEN
    PERFORM aidb.delete_semantic_alias('monthly_revenue');   -- recreate, so an updated query replaces the old one
  END IF;
  BEGIN
    PERFORM aidb.create_semantic_alias(
      name        => 'monthly_revenue',
      description => 'Total revenue for a given month and year, excluding cancelled orders',
      query_text  => $q$
        SELECT SUM(amount) AS total
        FROM shop.orders
        WHERE EXTRACT(MONTH FROM order_date) = ${month}::int
          AND EXTRACT(YEAR  FROM order_date) = ${year}::int
          AND status <> 'cancelled'
      $q$,
      params => '[
        {"name": "month", "param_type": "integer", "description": "Month number (1-12)"},
        {"name": "year",  "param_type": "integer", "description": "Four-digit year"}
      ]'
    );
  END;
END
$do$;

\echo '== Trusted query 2: customers who ordered more than once in a month'
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM aidb.get_semantic_aliases() WHERE name = 'repeat_customers') THEN
    PERFORM aidb.delete_semantic_alias('repeat_customers');   -- recreate, so an updated query replaces the old one
  END IF;
  BEGIN
    PERFORM aidb.create_semantic_alias(
      name        => 'repeat_customers',
      description => 'Customers who placed two or more orders in a given month and year',
      query_text  => $q$
        SELECT c.name, c.email, COUNT(*) AS orders
        FROM shop.orders o
        JOIN shop.customers c ON c.id = o.customer_id
        WHERE EXTRACT(MONTH FROM o.order_date) = ${month}::int
          AND EXTRACT(YEAR  FROM o.order_date) = ${year}::int
          AND o.status <> 'cancelled'
        GROUP BY c.name, c.email
        HAVING COUNT(*) >= 2
        ORDER BY orders DESC, c.name
      $q$,
      params => '[
        {"name": "month", "param_type": "integer", "description": "Month number (1-12)"},
        {"name": "year",  "param_type": "integer", "description": "Four-digit year"}
      ]'
    );
  END;
END
$do$;

\echo '== Try it: find the right table by meaning'
SELECT source_type, entity_type, schema_name, relation_name, column_name, rank
FROM aidb.semantic_kb_search(query_text => 'customer email address', kb_name => 'shop_kb', top_k => 4);

\echo '== Try it: find a saved query by meaning'
SELECT name, similarity
FROM aidb.search_semantic_aliases(query_text => 'which customers bought more than once', kb_name => 'shop_kb', top_k => 2);

\echo '== Try it: run the saved query for LAST month (expect Maya Cohen, Noah Schmidt, Lucas Tanaka)'
SELECT result
FROM aidb.execute_semantic_alias(
  alias_name => 'repeat_customers',
  args => jsonb_build_object(
            'month', EXTRACT(MONTH FROM current_date - INTERVAL '1 month')::int,
            'year',  EXTRACT(YEAR  FROM current_date - INTERVAL '1 month')::int)
);
