# AIDB showcase: demo guide

The step-by-step script for presenting the demo, the ready-to-run SQL for each step, and a cheat sheet of use cases.
Set up first (see the [README](../README.md#quick-start)). All names below come from the demo data in `sql/`.

## The demo data

Everything is in a schema called `shop`. Dates are relative to today, so "last month" always has data.

| Table | What it holds | Rows |
| :-- | :-- | :-- |
| `shop.customers` | People who buy: name, email, country | 12 |
| `shop.products` | Items for sale, with category and price | 10 |
| `shop.orders` | One row per order: date, status, total | 59 |
| `shop.order_items` | The products inside each order | 165 |
| `shop.support_tickets` | Customer problems, open or closed | 10 |
| `shop.kb_articles` | Help-centre articles (returns, delivery, warranty, sizing, password reset and more) | 14 |

Facts built into the data, so you know what a correct answer looks like:

- **Three customers ordered twice last month:** Maya Cohen, Noah Schmidt and Lucas Tanaka.
- The help article **"Returns and refunds"** answers "How do I send back an item?" even though it never uses those words.
- Support ticket subjects include a stuck tent zipper, a missing refund and a login problem.

What the scripts create in AIDB:

| Object | Name | Used in |
| :-- | :-- | :-- |
| Credential (placeholder key, not real) | `demo_hosted_ai` | Step 3 |
| Hosted model using that credential | `demo_hosted_gpt` | Step 2 |
| Semantic knowledge base over `shop` | `shop_kb` | Steps 4, 5 |
| Saved queries | `monthly_revenue`, `repeat_customers` | Step 4 |
| Document knowledge base (pipeline `shop_articles_pipe`) | `shop_articles_kb` | Step 5 |
| Custom tool | `customer_open_tickets` | Step 6 |
| Assistants | `shop_analyst`, `shop_helpdesk` (and `shop_readonly_agent` with `--with-governance`) | Step 6 |

Models used: the built-in `bert` for search and `qwen3.5-0.8b-Q8_0` for the assistants. Neither needs an API key. The assistant model is small, so expect short, simple answers. For stronger answers, register a hosted model and run `SELECT * FROM aidb.update_agent('shop_analyst', model => 'your_model');`.

---

## Run the demo, step by step

Use the numbered tabs at the top of the Showcase, or the left and right arrow keys. Tick **Presenter notes** for a talking point under each step. Under each step's live panel there is also a box of ready-to-run SQL queries; [The SQL console, step by step](#the-sql-console-step-by-step) explains how to use it.

### Step 1 · AI inside: "Your database already speaks AI"
- **Click:** any capability tile, for example *Talk to AI models*.
- **You see:** live counts of commands and areas, then the list of commands in that area.
- **Say:** "Everything AIDB does is a command inside the database. These numbers are counted live from this server."

### Step 2 · Models: "Choose the AI brain"
- **Click:** **Try it** on `bert`.
- **You see:** the sentence "hello world" became a list of numbers (384 for `bert`). Local models are tagged *runs inside Postgres*. `demo_hosted_gpt` is tagged *outside service*.
- **Skip Try it on `demo_hosted_gpt`.** Its key is a placeholder, so the call fails by design.
- **Say:** "This model stays inside Postgres. This one would call a provider. The application uses both the same way."

### Step 3 · Keys: "Passwords and keys stay locked away"
- **Click:** nothing. Read the cards.
- **You see:** the credential `demo_hosted_ai` with *key stored: yes*, *shared: yes*, *allowed to call: api.openai.com*, and never the key itself. A leaked-key scan with zero findings.
- **Say:** "The key is stored once, shared with chosen colleagues and limited to one website. This page cannot show it, even if I wanted it to."

### Step 4 · Your data: "Teach AI how your tables connect"
- **Click:** **Show the connections**.
- **You see:** the links between tables, such as orders to customers.
- **Click:** type `shop.order_items` in *from* and `shop.customers` in *to*, then **Find route**.
- **You see:** a route that goes through `shop.orders`.
- **Say:** "Because the system knows how these tables join, a question about customers and order items combines them correctly."

### Step 5 · Ask: "Ask a question in everyday words"
Two modes:

| Mode | Type | You should see |
| :-- | :-- | :-- |
| **Find data** | `customer email address` | `shop.customers.email` ranked first |
| **Find data** | `how much money did customers spend` | order-related columns such as `shop.orders.amount` near the top (exact order can vary) |
| **Find documents** | `How do I send back an item?` (knowledge base `shop.shop_articles_kb`) | **Returns and refunds** ranked first |
| **Find documents** | `I cannot sign in to my account` | the password-reset article first |
| **Find documents** | `Is this tent covered if the zip breaks?` | the warranty article first |

- The knowledge base name fills in automatically when one is found.
- **Say:** "Notice there is no shared wording. The system matches meaning."

### Step 6 · Agents: "Let an agent work through a task"
- **Click:** nothing for the tool cards. They list every tool an assistant may use, marked *read-only* or *can change data*. Look for `customer_open_tickets`.
- **Click:** choose `shop_analyst`, type `How many customers are in each region?`, press **Ask**, and confirm.
- **You see:** a short answer in a speech bubble. The first question downloads the model, so allow a few minutes.
- **Say:** "The assistant can only use the tools on this list. Everything it does is recorded."
- The small local model may give a rough answer. That is a model limit, not an AIDB limit.

### Step 7 · Health: "Spot problems before users do"
- **Click:** **Run a health check**.
- **You see:** no failed pipeline steps (a green all-clear) and a health report.
- **Click:** **What changed since an earlier version?** to open Compare versions (see "What the console shows" in the README).
- **Say:** "An empty failure list is the good result. If something breaks, it shows here."

---

## The SQL console, step by step

Every Showcase step has a box called **Try it yourself in the SQL console** under the live panel. You can use it two ways:

- **Run here** runs the query and shows the result right under it. Nothing else to do.
- **Open in SQL console** loads the same query into the full editor on the *SQL console* tab, with a yellow note telling you where it came from. Press **Run** (or **Ctrl+Enter**; **⌘+Enter** on a Mac) to execute it.

### How to use the SQL console (the 5 things to know)

1. **Get a query into the editor.** Use *Open in SQL console* from a Showcase step, press one of the preset buttons under the editor, or paste your own.
2. **Press Run.** If you have selected some text, only the selection runs. Otherwise everything runs. Give each query its own semicolon.
3. **Read the result under the editor.** Each query gets its own table. Click a cell to read a long value in the side panel.
4. **It is read-only.** Nothing changes unless you tick **Allow writes**. Only one query below needs it (asking an assistant a question, because the conversation is recorded).
5. **Errors are normal.** The red text says what went wrong. The usual cause is a demo piece that has not been created yet: run `./install/20_load_demo.sh --check`.

The queries below use the demo data. You can copy them straight into the editor. **You should see** describes the result with the sample data; exact numbers can vary, and anything that calls a model is slow the first time because the model downloads.

### Step 1 queries · Your database already speaks AI

**1. How many commands does AIDB add?**

```sql
SELECT count(*) AS commands
FROM pg_proc
WHERE pronamespace = 'aidb'::regnamespace;
```
*You should see:* One number. It is larger than the tile above because it also counts internal helper functions.

**2. List the commands that search by meaning**

```sql
SELECT proname
FROM pg_proc
WHERE pronamespace = 'aidb'::regnamespace
  AND (proname LIKE '%semantic%' OR proname LIKE 'retrieve%')
ORDER BY 1;
```
*You should see:* A list of names such as retrieve_text, retrieve_key and semantic_kb_search.

### Step 2 queries · Choose the AI brain, local or hosted

**1. Which models are registered, and where do they run?**

```sql
SELECT name, provider, credential
FROM aidb.list_models()
ORDER BY provider, name;
```
*You should see:* The built-in models (bert, clip, t5, llama and others), plus demo_hosted_gpt if you ran the demo setup. Providers ending in _local or starting with llamacpp run inside Postgres.

**2. Turn a sentence into numbers with the local bert model** (calls a model)

```sql
SELECT array_length(
         aidb.encode_text('bert', 'warm jacket for a cold night'), 1
       ) AS numbers_per_sentence;
```
*You should see:* 384. The sentence became a list of 384 numbers that capture its meaning. The first call downloads the model, so it can take a while.

### Step 3 queries · Passwords and keys stay locked away

**1. List the credentials (the key itself is never shown)**

```sql
SELECT name, owner, endpoint, shared, has_secret, can_use
FROM aidb.credentials
ORDER BY name;
```
*You should see:* A row for demo_hosted_ai: endpoint api.openai.com, shared t, has_secret t. The built-in "none" credential is also listed.

**2. Scan for keys pasted into model settings by mistake**

```sql
SELECT * FROM aidb.audit_leaked_credentials();
```
*You should see:* No rows. An empty result is the good answer.

**3. Where may AIDB connect?**

```sql
SELECT name, setting
FROM pg_settings
WHERE name LIKE '%egress%'
ORDER BY name;
```
*You should see:* The outbound allowlist and the insecure-egress switch. The allowlist is the list of hosts AIDB may call.

### Step 4 queries · Teach AI how your tables connect

**1. What has AIDB learned about the shop schema?**

```sql
SELECT * FROM aidb.semantic_kb_stats(kb_name => 'shop_kb');
```
*You should see:* tables = 6 (customers, products, orders, order_items, support_tickets, kb_articles), a count of columns and relationships, and pending = 0. If tables is 0, wait a moment and run it again.

**2. How do the tables connect?**

```sql
SELECT left_object, right_object, kind, join_expr
FROM aidb.list_relationships(kb_name => 'shop_kb');
```
*You should see:* Links such as orders to customers and order_items to orders, with the join condition in the last column.

**3. Find the route between two tables**

```sql
SELECT path_rank, hops, route, join_clause
FROM aidb.find_join_path(
       kb_name     => 'shop_kb',
       from_object => 'shop.order_items',
       to_object   => 'shop.customers');
```
*You should see:* A route that goes through shop.orders, with the join clause to use.

### Step 5 queries · Ask a question in everyday words

**1. Find the data by describing it** (calls a model)

```sql
SELECT source_type, entity_type, relation_name, column_name, rank
FROM aidb.semantic_kb_search(
       query_text => 'customer email address',
       kb_name    => 'shop_kb',
       top_k      => 5);
```
*You should see:* The email column of the customers table at or near the top, although the question never says "customers.email".

**2. Find a help article by meaning** (calls a model)

```sql
SELECT key, left(value, 100) AS passage, round(distance::numeric, 3) AS distance
FROM aidb.retrieve_text(
       (SELECT name FROM aidb.knowledge_bases WHERE name LIKE '%shop_articles_kb' LIMIT 1),
       'How do I send back an item?',
       topk => 3);
```
*You should see:* The "Returns and refunds" article (key 1) first, although it never uses the words "send back an item". A smaller distance means a closer match.

**3. Run a saved, trusted query for last month**

```sql
SELECT result
FROM aidb.execute_semantic_alias(
       alias_name => 'repeat_customers',
       args => jsonb_build_object(
         'month', EXTRACT(MONTH FROM current_date - INTERVAL '1 month')::int,
         'year',  EXTRACT(YEAR  FROM current_date - INTERVAL '1 month')::int));
```
*You should see:* Three customers: Maya Cohen, Noah Schmidt and Lucas Tanaka, each with 2 orders.

### Step 6 queries · Let an agent work through a task

To build your own agent live, and to show every setting and tool an agent can use, follow [build-an-agent.md](build-an-agent.md).

**1. What may an assistant use?**

```sql
SELECT name, tool_type, read_only
FROM aidb.tools
ORDER BY tool_type, name;
```
*You should see:* Every tool in one list. Look for customer_open_tickets: a custom SQL tool, read_only t.

**2. Which assistants exist?**

```sql
SELECT name, model, tools, delegates
FROM aidb.agents
ORDER BY name;
```
*You should see:* shop_analyst (with its list of tools) and shop_helpdesk (which delegates to shop_analyst).

**3. Run one tool directly, with no AI involved**

```sql
SELECT aidb.run_tool(
         'customer_open_tickets',
         '{"customer_id": 2}'::jsonb);
```
*You should see:* One open ticket for customer 2: "Boots arrived in the wrong size". This is exactly what an assistant would get back when it uses the tool.

**4. Ask the assistant a question** (calls a model; tick **Allow writes** first)

```sql
SELECT *
FROM aidb.agent_converse(
       agent_name => 'shop_analyst',
       prompt     => 'How many customers are in each region?',
       read_only  => true);
```
*You should see:* A short answer in the "message" column. This records the conversation, so it needs the Allow writes tick in the SQL console. The first call downloads the model, which can take several minutes. The small local model may give a rough answer.

### Step 7 queries · Spot problems before users do

**1. Has any pipeline step failed?**

```sql
SELECT * FROM aidb.get_all_error_summaries();
```
*You should see:* No rows. An empty result means nothing has failed.

**2. How is the document pipeline doing?**

```sql
SELECT * FROM aidb.get_pipeline_metrics('shop_articles_pipe');
```
*You should see:* A status row for the pipeline. The source count should be 14, one per help article.

**3. Run AIDB's built-in health check**

```sql
SELECT aidb.analyze_db_health();
```
*You should see:* A report in JSON. Click the cell to read it in the side panel.


---

## Use case cheat sheet

| Use case | Where | Type or click | Correct answer |
| :-- | :-- | :-- | :-- |
| Find answers in documents | Step 5, Find documents | `How do I send back an item?` | Returns and refunds |
| Question the database in plain English | Step 5, Find data | `customer email address` | `shop.customers.email` |
| Reuse trusted queries | Step 5, query 3 ("Run a saved, trusted query") | Run here | Maya Cohen, Noah Schmidt, Lucas Tanaka |
| Assistants that do the work | Step 6 | Ask `shop_analyst` | A short answer from live data |
| Choose where the AI runs | Step 2 | Compare `bert` and `demo_hosted_gpt` | Inside Postgres versus outside service |
| Control and trust | Step 3 | Read the credential card | Key stored, never shown |
| Keep it running | Step 7 | Health check | No failed steps |

To demonstrate **assistants held to one role**, run `./install/20_load_demo.sh --with-governance`, then ask `shop_readonly_agent` a question in step 6. Its tool calls run as the read-only role `shop_readonly`.

The deck `docs/AIDB-7.8-benefits-and-use-cases.pptx` (written for 7.8) follows the same story. Slide 10 maps each use case to a step.

---

## What 7.9 added (optional, read-only)

Three queries for the SQL console, for a 7.9 server. They also sit under **What 7.9 added** in `sql/tour_queries.sql` and as
presets under the console editor. On 7.8 they fail because the objects do not exist, which is expected.

**1. Each knowledge base now has a managed plugin**

```sql
SELECT name, plugin_name FROM aidb.list_semantic_kbs();
```
*You should see:* a row for `shop_kb` and the name of its plugin. The release notes say each semantic knowledge base publishes a plugin named `semkb_<kb_name>`, with three read-only SQL tools (search, join paths, join suggestions).

**2. Plugins registered for agents**

```sql
SELECT * FROM aidb.agent_plugins_registry;
```
*You should see:* one row per registered agent plugin. It may be empty if nobody has created one. Plugins are managed with `aidb.create_agent_plugin()`, `aidb.update_agent_plugin()` and `aidb.delete_agent_plugin()`, and `aidb.create_agent()` takes a new `plugins` argument.

**3. Who wrote the telemetry** (needs `aidb_governance`)

```sql
SELECT source, count(*) AS spans
FROM aidb_otel.traces
GROUP BY source;
```
*You should see:* a count per source: `internal` for AIDB's own spans, `external` for spans sent in over OTLP. Rows written before the upgrade to 7.9 are all labelled `internal`. "Permission denied" means your role is not an `aidb_governance` member, because ordinary `aidb_users` cannot read `aidb_otel` by default.
