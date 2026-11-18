-- 04_documents.sql   (Showcase step 5, "Find documents")
-- Turns the help-centre articles into a searchable knowledge base.
-- A pipeline reads shop.kb_articles, embeds each article with the local 'bert' model,
-- and stores the vectors in a knowledge base called shop_articles_kb.

\echo '== Create the pipeline'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.knowledge_bases WHERE name LIKE '%shop_articles_kb') THEN
    PERFORM aidb.create_pipeline(
      name               => 'shop_articles_pipe',
      source             => 'shop.kb_articles',
      source_key_column  => 'id',
      source_data_column => 'body',
      destination        => 'shop_articles_kb',
      step_1             => 'KnowledgeBase',
      step_1_options     => aidb.knowledge_base_config(model => 'bert', data_format => 'Text')
    );
  END IF;
END
$do$;

\echo '== Process the articles once, then keep the knowledge base current automatically'
SELECT aidb.run_pipeline('shop_articles_pipe');
SELECT aidb.update_pipeline('shop_articles_pipe', auto_processing => 'Live');

\echo '== Knowledge bases on this server (copy the name into the Showcase "Find documents" box)'
SELECT name, model_name, distance_operator FROM aidb.knowledge_bases ORDER BY name;

-- Remember the full knowledge base name (it may carry a schema prefix)
SELECT name AS kbname FROM aidb.knowledge_bases WHERE name LIKE '%shop_articles_kb' LIMIT 1 \gset

\echo '== Search by meaning: no words in common with the answer'
SELECT key, left(value, 90) AS passage, round(distance::numeric, 3) AS distance
FROM aidb.retrieve_text(:'kbname', 'How do I send back an item?', topk => 3);

SELECT key, left(value, 90) AS passage, round(distance::numeric, 3) AS distance
FROM aidb.retrieve_text(:'kbname', 'I cannot sign in to my account', topk => 3);

SELECT key, left(value, 90) AS passage, round(distance::numeric, 3) AS distance
FROM aidb.retrieve_text(:'kbname', 'Is this tent covered if the zip breaks?', topk => 3);

\echo '== Pipeline health'
SELECT * FROM aidb.get_all_error_summaries();
