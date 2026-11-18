# AIDB showcase: install, load the demo, start the console

Target: any machine with Python 3.8+, the `psql` client and a Postgres database that has (or can create) the `aidb`
extension. Run from the repository root, as your normal user (no root needed), in order:

    cp env.sh.example env.sh && $EDITOR env.sh   # host, port, database, user
    ./install/00_check_prereqs.sh                # read-only: python3, psql, connection, aidb
    ./install/10_setup_dashboard.sh              # .venv and the console's requirements
    ./install/20_load_demo.sh                    # sample data, models, semantic layer, documents, agents
    ./reset-demo.sh                              # start the console
    ./install/99_smoke_test.sh                   # page, logo, API guard, demo readiness

Console: http://127.0.0.1:8643 (loopback only)   Settings: `dashboard/config.json` (port, psql timeout, row cap).

`20_load_demo.sh` takes the options listed at the top of the script: `--check`, `--from 03`, `--with-governance`,
`--allow-huggingface`, `--diagnose-egress`, `--force`, `--reset`. It is safe to run twice. The scripts write to your
database (a `shop` schema and AIDB objects), so use a test database.

## What each SQL file does

| File | Purpose |
| :-- | :-- |
| `sql/00_preflight.sql` | Read-only. Warns if the server blocks model downloads. Runs first. |
| `sql/00_allow_huggingface.sql` | Opt-in, superuser. Adds Hugging Face to `aidb.egress_allowlist`. Only needed if the preflight warns. |
| `sql/00_diagnose_egress.sql` | Read-only. Shows which level (file, `ALTER SYSTEM`, database, role) each egress setting comes from. |
| `sql/01_sample_data.sql` | The Northwind Outdoors tables. Plain Postgres. |
| `sql/02_models_and_credentials.sql` | Local models, plus a named credential (new in 7.8). |
| `sql/03_semantic_layer.sql` | Teaches AIDB the shop schema, and saves two trusted queries. |
| `sql/04_documents.sql` | Turns help articles into a searchable knowledge base. |
| `sql/05_agents_and_tools.sql` | A custom tool and two assistants. |
| `sql/06_optional_governance.sql` | Optional: an assistant held to a read-only role. Needs a superuser or an `aidb_governance` member. |
| `sql/check_ready.sql` | Read-only: reports what is ready or missing. |
| `sql/tour_queries.sql` | Read-only queries covering every capability, for the SQL console. Ends with a section on what 7.9 added. |
| `sql/99_reset.sql` | Removes everything the demo created. |

All scripts are safe to run twice. `./install/20_load_demo.sh --from 03` resumes at step 03 without reloading the sample
data. Step 01 drops and recreates the `shop` schema, so after a partial run use `--from` rather than starting over.

Tested on 6 Nov 2026 against Postgres 16.15 without the `aidb` extension: all five scripts, `reset-demo.sh` and
`stop-demo.sh` (start, restart, status, custom port, the `--wipe` confirmation, stop), the console serving its page and
logo and refusing foreign hosts, and `sql/01_sample_data.sql`. Not yet run: the AIDB-specific scripts (`02` to `06`) and
the console's AIDB views on a live AIDB 7.8 or 7.9 server.
