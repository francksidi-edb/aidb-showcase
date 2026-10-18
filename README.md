# AIDB 7.8 Showcase

A guided, plain-English demo of **EDB Postgres AI AIDB 7.8**, with a sample dataset and a read-only introspector for engineers. Unofficial demo material; see the product documentation at https://www.enterprisedb.com/docs/aidb/ for the supported behaviour.

Two things in one local web page:

- **Showcase**: a guided, seven-step tour in plain English, for business audiences.
- **Technical tabs**: a read-only map of every function, table, type and setting, plus a SQL console.

It comes with a **demo dataset** (a small online outdoor-gear shop called *Northwind Outdoors*) so every step has something real to show.

---

## 1. Quick start

```bash
git clone https://github.com/francksidi-edb/aidb-showcase.git
cd aidb-showcase
```

You need Python 3, the `psql` client, and a Postgres database with `aidb` installed (`CREATE EXTENSION aidb CASCADE;`).

```bash
# 1. Create env.sh with your connection settings (host, port, database, user)
cp env.sh.example env.sh
$EDITOR env.sh

# 2. Load the demo data and the AIDB objects (takes a few minutes the first time: see note below)
bash demo-data/run_demo_setup.sh

# 3. Start the app
bash start.sh
```

`env.sh` is loaded automatically by both scripts, so you do not need to export anything yourself. It is git-ignored, so your details are never committed. If your server needs a password, uncomment the `PGPASSWORD` line or use `~/.pgpass`.

Keep the repository layout as it is: `env.sh` and `start.sh` in the top folder, and the `demo-data` folder beside them.

Open **http://127.0.0.1:8643**, press **Connect & scan**, then **Start the guided showcase**.

Not sure what is set up? In the Showcase press **Demo readiness**. It lists what exists, what is missing, and which script creates each missing piece.

> **First-run downloads.** AIDB's built-in local models download their files from Hugging Face the first time they are used. The Postgres server needs internet access once. The embedding model (`bert`) is small. The assistant model (`qwen3.5-0.8b-Q8_0`) is several hundred MB and downloads on the first agent question.

### Files

| File | Purpose |
| :-- | :-- |
| `env.sh.example` | Template for `env.sh`, your connection settings (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`). Copy it; `env.sh` is git-ignored and loaded by both scripts. |
| `docs/AIDB-7.8-benefits-and-use-cases.pptx` | A 10-slide deck on AIDB 7.8 benefits and use cases that follows the same story as the demo. |
| `start.sh`, `aidb_introspect_server.py`, `aidb_introspect.html` | The app. The server listens on `127.0.0.1` only and runs every query through your `psql`. |
| `demo-data/run_demo_setup.sh` | Loads everything below. Options: `--check`, `--with-governance`, `--reset`. |
| `demo-data/00_preflight.sql` | Read-only. Warns if the server blocks model downloads. Runs first. |
| `demo-data/00_allow_huggingface.sql` | Opt-in, superuser. Adds Hugging Face to `aidb.egress_allowlist`. Only needed if the preflight warns. |
| `demo-data/00_diagnose_egress.sql` | Read-only. Shows which level (file, `ALTER SYSTEM`, database, role) each egress setting comes from. |
| `demo-data/01_sample_data.sql` | The Northwind Outdoors tables. Plain Postgres. |
| `demo-data/02_models_and_credentials.sql` | Local models, plus a named credential (new in 7.8). |
| `demo-data/03_semantic_layer.sql` | Teaches AIDB the shop schema, and saves two trusted queries. |
| `demo-data/04_documents.sql` | Turns help articles into a searchable knowledge base. |
| `demo-data/05_agents_and_tools.sql` | A custom tool and two assistants. |
| `demo-data/06_optional_governance.sql` | Optional: an assistant held to a read-only role. Needs a superuser. |
| `demo-data/check_ready.sql` | Read-only: reports what is ready or missing. |
| `demo-data/tour_queries.sql` | Read-only queries covering every capability, for the SQL console. |
| `demo-data/99_reset.sql` | Removes everything the demo created. |

All scripts are safe to run twice. `bash run_demo_setup.sh --from 03` resumes at step 03 without reloading the sample data (step 01 drops and recreates the `shop` schema, so after a partial run use `--from` rather than starting over).

---

## 2. The demo data

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

## 3. Run the demo, step by step

Use the numbered tabs at the top of the Showcase, or the left and right arrow keys. Tick **Presenter notes** for a talking point under each step. Under each step's live panel there is also a box of ready-to-run SQL queries; section 3b explains how to use it.

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
- **Click:** **What changed since an earlier version?** to open Compare versions. See section 5.
- **Say:** "An empty failure list is the good result. If something breaks, it shows here."

---

## 3b. The SQL console, step by step

Every Showcase step has a box called **Try it yourself in the SQL console** under the live panel. You can use it two ways:

- **Run here** runs the query and shows the result right under it. Nothing else to do.
- **Open in SQL console** loads the same query into the full editor on the *SQL console* tab, with a yellow note telling you where it came from. Press **Run** (or **Ctrl+Enter**; **⌘+Enter** on a Mac) to execute it.

### How to use the SQL console (the 5 things to know)

1. **Get a query into the editor.** Use *Open in SQL console* from a Showcase step, press one of the preset buttons under the editor, or paste your own.
2. **Press Run.** If you have selected some text, only the selection runs. Otherwise everything runs. Give each query its own semicolon.
3. **Read the result under the editor.** Each query gets its own table. Click a cell to read a long value in the side panel.
4. **It is read-only.** Nothing changes unless you tick **Allow writes**. Only one query below needs it (asking an assistant a question, because the conversation is recorded).
5. **Errors are normal.** The red text says what went wrong. The usual cause is a demo piece that has not been created yet: run `bash run_demo_setup.sh --check`.

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

## 4. Use case cheat sheet

| Use case | Where | Type or click | Correct answer |
| :-- | :-- | :-- | :-- |
| Find answers in documents | Step 5, Find documents | `How do I send back an item?` | Returns and refunds |
| Question the database in plain English | Step 5, Find data | `customer email address` | `shop.customers.email` |
| Reuse trusted queries | Step 5, query 3 ("Run a saved, trusted query") | Run here | Maya Cohen, Noah Schmidt, Lucas Tanaka |
| Assistants that do the work | Step 6 | Ask `shop_analyst` | A short answer from live data |
| Choose where the AI runs | Step 2 | Compare `bert` and `demo_hosted_gpt` | Inside Postgres versus outside service |
| Control and trust | Step 3 | Read the credential card | Key stored, never shown |
| Keep it running | Step 7 | Health check | No failed steps |

To demonstrate **assistants held to one role**, run `./demo-data/run_demo_setup.sh --with-governance`, then ask `shop_readonly_agent` a question in step 6. Its tool calls run as the read-only role `shop_readonly`.

The deck `2026-10-18 AIDB 7.8 Capabilities.pptx` follows the same story. Slide 10 maps each use case to a step.

---

## 5. The technical tabs

| Tab | Use it to |
| :-- | :-- |
| **Overview** | See installed and available versions, preload status, workers, and one coloured mark per function. |
| **Functions** | Search every function. Open one for its parameters, a ready-to-edit call, and its source. Press `/` to jump to search. |
| **Tables & views** | Browse the catalog tables and open their first rows. |
| **Types** | See enums, including valid values for options such as `auto_processing`. |
| **Settings** | See every `aidb.*` setting, with risky ones flagged. |
| **Live objects** | See models, credentials, providers, semantic knowledge bases, tools, aliases, volumes and pipeline errors. |
| **SQL console** | Run SQL and psql describe commands. **Ctrl or Cmd + Enter** runs the selection. Section 3b explains it step by step, and `tour_queries.sql` holds every query in one file. |
| **Compare versions** | Download a snapshot on an older server, load it here, and see what changed. |

**Showing what 7.8 added:** on a 7.7 server press **Download snapshot** in Compare versions. On the 7.8 server choose **Compare with a snapshot file**. The new credentials functions and the `aidb.credentials` view appear as new.

---

## 6. Safe by default

- Every query runs in a **read-only transaction** with a timeout.
- Anything stored under names like `api_key`, `secret`, `password` or `bearer` is replaced with `••• redacted •••` on the server before it reaches the browser.
- Only this page can call the API.

Actions that do more than read, and how they are guarded:

| Action | Where | What happens |
| :-- | :-- | :-- |
| **Try it** on a model | Step 2 | Calls the model once. Hosted providers bill for tokens. |
| **Ask** (search) | Step 5 | Calls the embedding model. |
| **Ask** an agent | Step 6 | Records the conversation, so it writes. A confirmation box appears and the agent starts in read-only mode. |
| **Allow writes** | SQL console | Turns off the guard for that session, after confirmation. |

The setup scripts do write to your database. They create a `shop` schema, AIDB objects named above, and with `--with-governance` a role named `shop_readonly`. Run them on a test database. `./demo-data/run_demo_setup.sh --reset` removes everything they created.

---

## 7. Troubleshooting

| Symptom | Fix |
| :-- | :-- |
| "`psql` isn't on PATH" | Start the server from a shell where `psql` runs. |
| "the aidb extension isn't installed" | `CREATE EXTENSION aidb CASCADE;` or choose the right database. |
| Setup stops with `egress denied: egress to host "huggingface.co" is not permitted by aidb.egress_allowlist` | The server restricts outbound traffic, and the built-in local models must download their files once. See section 9. |
| Setup script stops with `permission denied` | Run it as a role that can create schemas, triggers and AIDB objects. A superuser is simplest. |
| Setup hangs for minutes | A local model is downloading. Watch the Postgres `NOTICE` lines, or check the server has internet access. |
| `operator does not exist: numeric = text` when running a saved query | Fixed in the current `03_semantic_layer.sql`: AIDB passes `${month}` and `${year}` to the query as text, so the queries cast them (`${month}::int`). Run `bash run_demo_setup.sh --from 03` to recreate the saved queries. |
| Step 4 or Step 5 "Find data" errors | Run `./demo-data/run_demo_setup.sh --check`, then the script it names. If `shop_kb` shows 0 tables, wait a moment and run `SELECT * FROM aidb.semantic_kb_stats(kb_name => 'shop_kb');` again. |
| Step 5 "Find documents" says nothing matched | Check the knowledge base name (`shop.shop_articles_kb`) and that `04_documents.sql` ran without errors. |
| Step 6 shows no agents | Run `05_agents_and_tools.sql`. |
| Step 6 answer is wrong or empty | The default model is tiny. Switch the agent to a stronger model with `aidb.update_agent`. |
| "That didn't run" on a card | Open **The SQL behind this** in the console to see the full error. |
| No `aidb.*` settings shown | Add `aidb` to `shared_preload_libraries` and restart Postgres. |
| Port 8643 in use | Change `PORT` near the top of `aidb_introspect_server.py`. |

---

## 8. What has been tested

- **Tested on a real Postgres 16:** `01_sample_data.sql`, including that exactly three customers match the "ordered twice last month" question and that no order has a zero total.
- **Tested against a stand-in `aidb` schema** that mirrors the documented function names and parameters: every other script, including running each twice and resetting. This catches typos and quoting errors. It does not test real AIDB behaviour.
- **Tested in a browser with mocked responses:** all seven Showcase steps and the readiness panel.
- **Not tested against a live AIDB 7.8 server.** Run `./demo-data/run_demo_setup.sh` and `--check` once before presenting. If a statement fails on your build, the error names it, and the syntax comes from the official docs:
  - https://www.enterprisedb.com/docs/aidb/latest/integrating-models/
  - https://www.enterprisedb.com/docs/aidb/latest/integrating-models/credentials/
  - https://www.enterprisedb.com/docs/aidb/latest/semantic-knowledge-bases/example/
  - https://www.enterprisedb.com/docs/aidb/latest/knowledge-bases/multi-pipeline/
  - https://www.enterprisedb.com/docs/aidb/latest/agents/
  - https://www.enterprisedb.com/docs/aidb/latest/tools/custom-sql-tools/
  - https://www.enterprisedb.com/docs/aidb/latest/release-notes/7/aidb_7.8.0_rel_notes
- The knowledge base and agent lists find their tables by name (`knowledge_bases`, `agents`), which the docs confirm.
- Search closeness bars compare the results of one search with each other. They are not an absolute score.

---

## 9. If setup says "egress denied" for huggingface.co

AIDB can restrict where it connects with `aidb.egress_allowlist` (a comma-separated list of hosts and CIDR ranges; `edb.egress_allowlist` is a shared fallback). When the list is set, anything not on it is refused before a connection is made, **including the one-time download of a local model's files from Hugging Face**. The error means that control is working. `run_demo_setup.sh` now checks this first and **stops before creating anything** if the allowlist would block the download (use `--force` to load only the plain sample data anyway). Your options:

**A. Allow Hugging Face (needs a superuser).**

```bash
bash run_demo_setup.sh --allow-huggingface
bash run_demo_setup.sh
```

The script finds where the setting is defined and changes it there. A setting can live at several levels (`postgresql.conf`, `ALTER SYSTEM`, server start options, `ALTER DATABASE ... SET`, `ALTER ROLE ... SET`), and the stronger levels override the weaker ones. If an `ALTER SYSTEM` change seems to be ignored, a database- or role-level setting is overriding it. The script updates those entries and, if the current database has none, adds a database-level setting for just that database. It needs no reload and still works if the server-wide value is fixed by start-up options. If the value still does not change, the script prints a diagnosis, which you can also get any time with `bash run_demo_setup.sh --diagnose-egress` (read-only). The script keeps every entry already on your list and adds `huggingface.co`, `.huggingface.co`, `hf.co` and `.hf.co`. A leading dot means "subdomains only", so both forms are listed. Hugging Face redirects large files to CDN hosts, and each redirect is checked against the same list. To undo it, run `ALTER DATABASE <your database> RESET aidb.egress_allowlist;` (and `ALTER ROLE <role> RESET aidb.egress_allowlist;` for any role entry it updated), or restore the old value shown in the output.

**B. Ask whoever owns the server** to add those four entries. You can paste the commands from `00_allow_huggingface.sql`.

**C. Work offline.** Download the model files elsewhere and copy them into the Postgres host's cache, then point the model at them with the `cache_dir` setting. See https://www.enterprisedb.com/docs/aidb/latest/integrating-models/integrated-models/

The Showcase step 3 ("Keys") now shows the allowlist, so it doubles as a demonstration of this control.

Reference: https://www.enterprisedb.com/docs/aidb/latest/install/configure/ (Network egress).
