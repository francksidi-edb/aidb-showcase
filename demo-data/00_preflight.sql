-- 00_preflight.sql: read-only. Warns about settings that would stop the demo.
-- The local models (bert and the llama.cpp models) download their files from Hugging Face once.
-- If the server restricts outbound traffic with aidb.egress_allowlist, that download is refused.

\echo '== Network egress settings on this server'
SELECT name, setting FROM pg_settings
WHERE name IN ('aidb.egress_allowlist', 'edb.egress_allowlist', 'aidb.allow_insecure_egress')
ORDER BY name;

-- AIDB checks aidb.egress_allowlist first and falls back to edb.egress_allowlist. Unset means no restriction.
SELECT coalesce(nullif(current_setting('aidb.egress_allowlist', true), ''),
                nullif(current_setting('edb.egress_allowlist', true), ''), '') AS allow \gset
SELECT (:'allow' <> '' AND position('huggingface.co' in :'allow') = 0) AS hf_blocked \gset

\if :hf_blocked
  \echo
  \echo 'WARNING: an egress allowlist is set and it does not include huggingface.co.'
  \echo '         The first use of a local model will fail with "egress denied".'
  \echo '         Fix: bash run_demo_setup.sh --allow-huggingface   (needs a superuser; see README)'
\else
  \echo
  \echo 'OK: model downloads from huggingface.co are not blocked by an egress allowlist.'
\endif
