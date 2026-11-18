# Build an AIDB agent: how, and what an agent can use

An agent in AIDB is a row in `aidb.agents`. Creating one only stores its settings: a name, instructions, a model and the
tools it may call. Nothing runs until you call `aidb.agent_converse()`, and everything is plain SQL, so the usual Postgres
controls (roles, read-only transactions, audit) apply to it.

This guide builds an agent step by step on the demo's `shop` schema, then lists every setting and tool you can give it.
The demo already contains two finished agents, `shop_analyst` and `shop_helpdesk` (`sql/05_agents_and_tools.sql`, Showcase
step 6). Read those first if you want a working example, then build your own here.

> **Status:** written from the AIDB documentation (see Sources). The statements have not been run on a live AIDB server,
> so run the steps on a test database first. If a statement fails, the error column names it. Agents are covered by AIDB
> 7.8 and 7.9. On WarehousePG, the 7.9 release notes list agent memory and OpenTelemetry storage as unsupported.

## Before you start

You need `aidb`, the demo loaded (`./install/20_load_demo.sh`) and a registered text-generation model. The demo registers
the local model `qwen3.5-0.8b-Q8_0`, which needs no key but is small, so expect short, simple answers. For better
answers register a hosted model and use its name in `model =>` below.

The model must be a text-generation model that follows instructions. Embedding, reranking, OCR and multimodal-embedding
models cannot back an agent, and `t5_local` is rejected. For tool calling, the docs recommend `openai_responses` where
your server supports it. Other supported providers: `anthropic_messages` (and its Azure and Bedrock variants),
`llamacpp_generate` (the local models), and, with tool calls simulated through prompt text, `openai_completions`,
`completions`, `nim_completions`, `openrouter_chat`, `gemini` and `llama_instruct_local`.

Run the SQL below in the console's **SQL console** (tick **Allow writes** for steps that create things), or in `psql`.

## 1. See what exists

```sql
-- every tool an agent could be given
SELECT name, tool_type, read_only FROM aidb.tools ORDER BY tool_type, name;

-- the models you can use, and the agents already there
SELECT * FROM aidb.list_models();
SELECT name, model, tools, delegates FROM aidb.agents ORDER BY name;
```

*You should see:* the native tools (listed below), the demo's custom tool `customer_open_tickets`, your models, and
`shop_analyst` and `shop_helpdesk`.

## 2. Pick or build the tools

A tool is something an agent can call. Use the built-in ones, or wrap your own read-only query as a tool. This is how the
demo defines `customer_open_tickets`:

```sql
SELECT aidb.create_sql_tool(
  name          => 'customer_open_tickets',
  description   => 'List the open support tickets for one customer, newest first, looked up by customer id.',
  sql_statement => 'SELECT t.id, t.opened_at, t.subject, t.status
                    FROM shop.support_tickets t
                    WHERE t.customer_id = ${customer_id} AND t.status = ''open''
                    ORDER BY t.opened_at DESC',
  params        => aidb.tool_params(aidb.tool_param('customer_id', 'INT', 'The customer id.')),
  read_only     => true);
```

The `description` is what the model reads to decide when to use the tool, so write it for the model. Test a tool with no AI
involved:

```sql
SELECT aidb.run_tool('customer_open_tickets', '{"customer_id": 2}'::jsonb);
```

*You should see:* one open ticket for customer 2, "Boots arrived in the wrong size". This is exactly what an agent
receives when it uses the tool. To see any tool's parameters: `SELECT params FROM aidb.tools WHERE name = '<name>';`

## 3. Create the agent

```sql
SELECT * FROM aidb.create_agent(
  name           => 'order_helper',
  instructions   => 'You answer questions about customers and their orders in the shop schema. Look up the right tables first, then run a read-only query. Answer in one or two plain sentences. Never guess a table or column name.',
  model          => 'qwen3.5-0.8b-Q8_0',
  tools          => ARRAY['catalog_list_objects', 'catalog_get_object_details', 'run_sql_query', 'customer_open_tickets'],
  max_iterations => 8);
```

Success returns no rows. A failure returns one row with an `error` column, because the function never raises an
exception. That is why the demo scripts loop over the result and warn. Tool and delegate names are checked when you
create or update the agent, so a typo is rejected straight away. The model does not need to exist yet: only
`agent_converse` needs it to resolve.

Good instructions say what the agent is for, which data it may use, how to look things up, and how long the answer
should be. They matter more than any other setting, especially with a small model.

## 4. Ask it a question

```sql
SELECT * FROM aidb.agent_converse(
  agent_name => 'order_helper',
  prompt     => 'Which customers have an open support ticket?',
  read_only  => true);
```

*You should see:* a `message` with the answer. The first call to a local model downloads its files, which can take
several minutes. `agent_converse` returns `message`, `conversation_id` and `error`. Agent-logic failures come back in
`error` instead of raising, so the transaction still commits.

**`read_only => true` is the safe way to demo.** No conversation is stored (so `conversation_id` comes back NULL and the
run cannot be resumed), every tool call runs under `transaction_read_only = on`, and tools that are not provably read-only
are hidden from the agent. MCP tools are always excluded. Leave it NULL to record the conversation (it defaults to on only
on a read replica).

## 5. Continue a conversation, and read it back

```sql
-- first call without read_only, so the conversation is recorded
SELECT * FROM aidb.agent_converse('order_helper', 'How many customers are in each region?');

-- pass the conversation_id from that result to continue with the earlier history
SELECT * FROM aidb.agent_converse('order_helper', 'And which region has the most orders?',
                                  conversation_id => '<the id from the first call>');

SELECT * FROM aidb.get_conversation('<the id>');          -- prompts and final answers, in order
SELECT * FROM aidb.conversations;                         -- one row per conversation
```

`aidb.start_agent_session('order_helper')` mints an id before the first prompt. `debug => true` prints each action as a
NOTICE, but those payloads are not redacted, so do not use it with sensitive data.

## 6. Tune it without recreating it

```sql
SELECT aidb.update_agent('order_helper', model => 'your_hosted_model', max_iterations => 15);
```

`update_agent` takes the same fields as `create_agent`, all optional, and changes only the ones you pass.

## 7. Add a second agent that delegates

```sql
SELECT * FROM aidb.create_agent(
  name         => 'front_desk',
  instructions => 'You help staff with general questions. Hand questions about orders, customers or tickets to order_helper.',
  model        => 'qwen3.5-0.8b-Q8_0',
  delegates    => ARRAY['order_helper']);
```

Each delegate appears to the model as a tool named after the delegate agent, with a required `prompt` and an optional
`conversation_id`. The delegate's `instructions` become the tool's description, so write them to say what that agent is
for. Read-only and debug mode carry over to the delegate, and the role always comes from the calling agent, so a read-only
agent cannot reach a write through a delegate. Budgets do not carry over: each delegate call has its own. Chains are capped
at 10 levels, which catches cycles.

## 8. Remove it

```sql
SELECT aidb.delete_agent('front_desk');
SELECT aidb.delete_agent('order_helper', force => true);   -- force also removes its stored conversation history
```

Without `force`, deleting an agent that has history fails. The transcript stays readable with `aidb.get_conversation()`.

## What you can configure

| Setting | What it does |
| :-- | :-- |
| `instructions` | The agent's brief. Required. |
| `model` | A registered text-generation model. Required. |
| `tools` | Names from `aidb.tools` the agent may call. NULL means none. |
| `delegates` | Names of other agents it may hand off to. NULL means none. |
| `purpose` | A name from `aidb.purpose_registry`. Tool SQL then runs as that purpose's Postgres role (see below). NULL means the calling role. |
| `output_type` | A schema for structured answers (see below). NULL means plain text. |
| `input_token_budget`, `output_token_budget` | Token caps per `agent_converse` call. NULL means no limit. |
| `max_iterations` | Reasoning rounds per call. A hard ceiling of 25 always applies. |
| `timeout` | Seconds per call. 300 applies at run time when NULL. |
| `budget_strategy` | What happens at a budget: `'ignore'`, `'error'`, `'summarize'` or `'attempt_complete'` (default). |
| `preset` | Reserved for future use. Stored, no effect today. |

The 7.9 release notes also add a `plugins` argument to `create_agent` and the functions `aidb.create_agent_plugin()`,
`aidb.update_agent_plugin()` and `aidb.delete_agent_plugin()`, with each semantic knowledge base publishing its own
plugin. The agent pages I could read do not describe plugins, so check the 7.9 reference before building with them.
`SELECT * FROM aidb.agent_plugins_registry;` shows what is registered.

## Hold an agent to a role (governance)

A *purpose* maps a name to a Postgres role. An agent created with that purpose runs its tool SQL as that role, and each
tool SQL execution is recorded as `allowed` or `denied`. Only `aidb_governance` members create purposes, and from AIDB 7.9
the purpose functions run with the caller's own privileges.

```sql
SELECT aidb.create_purpose(name => 'shop_reporting', role => 'shop_readonly',
                           description => 'Read-only access to the shop schema');
SELECT * FROM aidb.create_agent(
  name => 'readonly_reporter', instructions => 'Answer questions about shop data. Never modify data.',
  model => 'qwen3.5-0.8b-Q8_0', tools => ARRAY['run_sql_query'], purpose => 'shop_reporting');
```

The demo's `./install/20_load_demo.sh --with-governance` builds exactly this as `shop_readonly_agent`. Each invocation
re-checks that the caller is a member of the purpose's role, and the call is refused if the purpose was deleted.

## Get structured answers

Build a schema with `aidb.output_type()` and `aidb.output_field()` to get fields back instead of free text:

```sql
SELECT * FROM aidb.create_agent(
  name         => 'ticket_triage',
  instructions => 'Read a support ticket and classify it.',
  model        => 'qwen3.5-0.8b-Q8_0',
  output_type  => aidb.output_type(
    aidb.output_field('priority', 'TEXT', 'One of: low, medium, high'),
    aidb.output_field('topic',    'TEXT', 'A short topic such as sizing, delivery or refund')));

SELECT * FROM aidb.agent_converse('ticket_triage', 'Boots arrived in the wrong size and I need them for a trip on Friday.', read_only => true);
```

An `output_type` passed to `agent_converse` overrides the agent's schema for that one call. A very small model may fill the
fields poorly; a hosted model is more reliable.

## What an agent can use: the native tools

These ship with AIDB. `Read-only` tools are the only ones an agent sees when you call it with `read_only => true`.

| Group | Tools (read-only unless marked **write**) |
| :-- | :-- |
| Ad hoc SQL | `run_sql_query`, `explain_query` |
| Catalog discovery | `catalog_list_schemas`, `catalog_list_objects`, `catalog_get_object_details`, `catalog_list_relations`, `catalog_list_sequences`, `catalog_list_extensions` |
| Database health | `analyze_db_health` (index, connection, vacuum, sequence, replication, buffer and constraint checks) |
| Semantic knowledge bases (search) | `semantic_kb_search`, `get_column_definitions`, `get_metadata`, `get_entity_definitions`, `search_by_comment`, `semantic_kb_stats`, `list_relationships`, `find_join_path`, `suggest_joins`, `semantic_kb_subgraph`, `relationship_candidates`, `list_query_history`, `list_proposed_comments`, `list_semantic_kbs`, `get_semantic_kb` |
| Semantic knowledge bases (change) | **write:** `create_semantic_kb`, `delete_semantic_kb`, `refresh_semantic_kb`, `update_semantic_kb_auto_processing`, `add_relationship`, `delete_relationship`, `accept_relationship_candidates`, `import_query_history`, `add_comment_to_object`, `remove_comment`. `relationship_drift` is flagged read-only but writes on every call, so treat it as a write |
| Models and credentials | `list_models`, `get_model`, `list_credentials`, `list_hcp_models`, `get_hcp_models`. **write:** `create_model`, `delete_model`, `create_credential`, `update_credential`, `delete_credential`, `sync_hcp_models`, `create_hcp_model`. A credential's secret passes through the agent's model |
| Volumes | `list_volumes`, `list_volume_content`, `read_volume_file`. **write:** `create_volume`, `delete_volume`, `write_volume_data`, `delete_volume_file` |
| Embedding and documents | `encode_text`, `encode_text_query`, `encode_image`, `generate_text`, `rerank_text`, `chunk_text`, `parse_html`, `parse_pdf`, `pdf_to_image`, `perform_ocr`, `summarize_text`, `get_model_description`, `list_model_providers`, `get_adapter_embedding_dimensions` |
| Agent management | `list_agents`, `sleep`. **write:** `create_agent`, `update_agent`, `delete_agent` |
| Agent memory (preview) | `memory_search`. **write:** `memory_add`. From 7.9 these take `namespace` and `actor_id` |
| Pipelines | `search_pipelines`, `get_pipeline`, `get_pipeline_metrics`, `get_error_logs`, `get_error_log_summary`, `get_all_error_summaries`. **write:** `delete_pipeline`, `run_pipeline`, `clear_error_logs`, `requeue_pipeline_errors` |

On top of these, an agent can use **your own SQL tools** (`aidb.create_sql_tool`, as in step 2) and **MCP tools** from
connected servers. MCP tools are never available in a read-only run.

**Give an agent the fewest tools that do the job.** Prefer the read-only ones, and only add a write tool, such as
`create_model` or `run_pipeline`, when the agent must change something. A small model with a short, relevant tool list
does better than one with all of them.

## Limits worth knowing

- **Cost and runtime** are bounded per call by the token budgets, `max_iterations` (hard ceiling 25) and `timeout`.
- **Delegation depth** is 10 levels. Hitting it stops the task with an error and does not retry.
- **`debug => true`** prints unredacted payloads as NOTICE messages.
- **Small local model:** answers are short and sometimes rough, and structured output is unreliable.
- **`create_agent` and `update_agent` do not check role membership.** The check happens on each invocation.

## Sources

- [Managing agents](https://www.enterprisedb.com/docs/aidb/latest/agents/creating-agents/)
- [Invoking agents](https://www.enterprisedb.com/docs/aidb/latest/agents/conversing-with-agents/)
- [Delegation](https://www.enterprisedb.com/docs/aidb/latest/agents/delegation/)
- [Native tools](https://www.enterprisedb.com/docs/aidb/latest/tools/native-tools/)
- [Custom SQL tools](https://www.enterprisedb.com/docs/aidb/latest/tools/custom-sql-tools/)
- [AIDB 7.9.0 release notes](https://www.enterprisedb.com/docs/aidb/latest/release-notes/7/aidb_7.9.0_rel_notes)
