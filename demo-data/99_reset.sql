-- 99_reset.sql: removes everything the demo scripts created. Safe to run more than once.
-- It does not touch AIDB's built-in models or anything you created yourself.

DO $do$ BEGIN PERFORM aidb.delete_agent('shop_helpdesk');        EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_agent('shop_readonly_agent');  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_agent('shop_analyst');         EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_purpose('shop_read_only');     EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_tool('customer_open_tickets'); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_semantic_alias('monthly_revenue');   EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_semantic_alias('repeat_customers');  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_semantic_kb('shop_kb');        EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_pipeline('shop_articles_pipe'); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_model('demo_hosted_gpt');      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;
DO $do$ BEGIN PERFORM aidb.delete_credential('demo_hosted_ai', cascade => true); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'skip: %', SQLERRM; END $do$;

DROP SCHEMA IF EXISTS shop CASCADE;
DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shop_readonly') THEN
    DROP OWNED BY shop_readonly;
    DROP ROLE shop_readonly;
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'role cleanup skipped: %', SQLERRM;
END $do$;
\echo 'Demo objects removed.'
