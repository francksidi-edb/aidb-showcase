-- check_ready.sql: read-only. Shows which demo pieces exist on this server.
-- Run from psql, or paste into the Introspector SQL console.
SELECT step,
       CASE WHEN ok THEN 'ready' ELSE 'MISSING' END AS status,
       CASE WHEN ok THEN '' ELSE 'run ' || fix END   AS what_to_do
FROM (
  SELECT 1 AS n, 'Models: built-in local model "bert"' AS step,
         EXISTS (SELECT 1 FROM aidb.list_models() WHERE name = 'bert') AS ok,
         'nothing: it is built in. Check the AIDB install' AS fix
  UNION ALL SELECT 2, 'Named credential "demo_hosted_ai"',
         EXISTS (SELECT 1 FROM aidb.credentials WHERE name = 'demo_hosted_ai'), '02_models_and_credentials.sql'
  UNION ALL SELECT 3, 'Semantic knowledge base "shop_kb"',
         EXISTS (SELECT 1 FROM aidb.list_semantic_kbs() WHERE name = 'shop_kb'), '03_semantic_layer.sql'
  UNION ALL SELECT 4, 'Two saved queries (semantic aliases)',
         (SELECT count(*) FROM aidb.get_semantic_aliases() WHERE name IN ('monthly_revenue', 'repeat_customers')) = 2,
         '03_semantic_layer.sql'
  UNION ALL SELECT 5, 'Document knowledge base "shop_articles_kb"',
         EXISTS (SELECT 1 FROM aidb.knowledge_bases WHERE name LIKE '%shop_articles_kb'), '04_documents.sql'
  UNION ALL SELECT 6, 'Custom tool "customer_open_tickets"',
         EXISTS (SELECT 1 FROM aidb.tools WHERE name = 'customer_open_tickets'), '05_agents_and_tools.sql'
  UNION ALL SELECT 7, 'Agent "shop_analyst"',
         EXISTS (SELECT 1 FROM aidb.agents WHERE name = 'shop_analyst'), '05_agents_and_tools.sql'
  UNION ALL SELECT 8, 'No failed pipeline steps',
         NOT EXISTS (SELECT 1 FROM aidb.get_all_error_summaries()), 'SELECT * FROM aidb.get_all_error_summaries();'
) c
ORDER BY n;
