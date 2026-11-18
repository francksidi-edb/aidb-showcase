# If setup says "egress denied" for huggingface.co

AIDB can restrict where it connects with `aidb.egress_allowlist` (a comma-separated list of hosts and CIDR ranges; `edb.egress_allowlist` is a shared fallback). When the list is set, anything not on it is refused before a connection is made, **including the one-time download of a local model's files from Hugging Face**. The error means that control is working. `install/20_load_demo.sh` checks this first and **stops before creating anything** if the allowlist would block the download (use `--force` to load only the plain sample data anyway). Your options:

**A. Allow Hugging Face (needs a superuser).**

```bash
./install/20_load_demo.sh --allow-huggingface
./install/20_load_demo.sh
```

The script finds where the setting is defined and changes it there. A setting can live at several levels (`postgresql.conf`, `ALTER SYSTEM`, server start options, `ALTER DATABASE ... SET`, `ALTER ROLE ... SET`), and the stronger levels override the weaker ones. If an `ALTER SYSTEM` change seems to be ignored, a database- or role-level setting is overriding it. The script updates those entries and, if the current database has none, adds a database-level setting for just that database. It needs no reload and still works if the server-wide value is fixed by start-up options. If the value still does not change, the script prints a diagnosis, which you can also get any time with `./install/20_load_demo.sh --diagnose-egress` (read-only). The script keeps every entry already on your list and adds `huggingface.co`, `.huggingface.co`, `hf.co` and `.hf.co`. A leading dot means "subdomains only", so both forms are listed. Hugging Face redirects large files to CDN hosts, and each redirect is checked against the same list. To undo it, run `ALTER DATABASE <your database> RESET aidb.egress_allowlist;` (and `ALTER ROLE <role> RESET aidb.egress_allowlist;` for any role entry it updated), or restore the old value shown in the output.

**B. Ask whoever owns the server** to add those four entries. You can paste the commands from `sql/00_allow_huggingface.sql`.

**C. Work offline.** Download the model files elsewhere and copy them into the Postgres host's cache, then point the model at them with the `cache_dir` setting. See https://www.enterprisedb.com/docs/aidb/latest/integrating-models/integrated-models/

The Showcase step 3 ("Keys") now shows the allowlist, so it doubles as a demonstration of this control.

Reference: https://www.enterprisedb.com/docs/aidb/latest/install/configure/ (Network egress).
