-- 02_models_and_credentials.sql   (Showcase steps 2 and 3)
-- Uses AIDB's built-in local models (no key, no setup) and creates one named credential,
-- the headline feature of AIDB 7.8.
--
-- NOTE: the first call to a local model downloads its files from Hugging Face into the
-- Postgres host's cache, so the Postgres server needs internet access once.
-- The credential below holds a PLACEHOLDER, not a real key. It exists so the demo can show
-- "key stored, shared, limited to api.openai.com" without exposing anything.

\echo '== Built-in local models'
SELECT name, provider FROM aidb.list_models() ORDER BY provider, name;

\echo '== A local embedding model turns a sentence into numbers (no API key involved)'
SELECT array_length(aidb.encode_text('bert', 'Northwind Outdoors sells hiking gear'), 1) AS numbers_per_sentence;

\echo '== Named credential (7.8): stored once, shared, limited to one host'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.credentials WHERE name = 'demo_hosted_ai') THEN
    PERFORM aidb.create_credential(
      name        => 'demo_hosted_ai',
      credentials => '{"api_key": "DEMO-PLACEHOLDER-NOT-A-REAL-KEY"}'::jsonb,
      endpoint    => 'api.openai.com',
      share       => true
    );
  END IF;
END
$do$;

\echo '== A hosted model that uses that credential (registered without validation: it will not call the provider)'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM aidb.list_models() WHERE name = 'demo_hosted_gpt') THEN
    PERFORM aidb.create_model(
      name       => 'demo_hosted_gpt',
      provider   => 'openai_completions',
      config     => aidb.completions_config(model => 'gpt-4o-mini'),
      credential => 'demo_hosted_ai',
      validate   => false
    );
  END IF;
END
$do$;

SELECT name, owner, endpoint, shared, has_secret, can_use FROM aidb.credentials ORDER BY name;
SELECT name, provider, credential FROM aidb.get_model('demo_hosted_gpt');
