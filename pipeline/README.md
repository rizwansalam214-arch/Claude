# Sales dashboard pipeline

Runs your Channel & SKU extract against BC, then builds the Sales & SKU dashboard as self-contained HTML files, one per audience.

```
SQL Server (read-only) ──► extract CSV ──► transform & validate ──► sales-dashboard-<audience>.html
  sql/channel_sku_extract.sql     output/extract_*.csv   build_dashboard.py         output/
```

## Set up (once)

1. Install Python 3.10+ and **Microsoft ODBC Driver 18 for SQL Server** on the machine that runs the job.
2. `pip install -r requirements.txt`
3. `copy config.example.json config.json`, then edit it if needed (mappings, audiences, FX).
4. Set the SQL host as an environment variable, never in a file: `setx SALES_SQL_SERVER "your-sql-host"`.
   Windows authentication is the default (`trusted_connection: true`). For a SQL login, set it to `false` and provide `SALES_SQL_USER` / `SALES_SQL_PASSWORD`.
5. Run `diagnostics/01_sign_check.sql` (repo root) once and confirm the `sign` multipliers in `config.json`.

## Run

| Command | What it does |
|---|---|
| `python build_dashboard.py` | Extract, then build every audience |
| `python build_dashboard.py --audience retail` | Build one audience |
| `python build_dashboard.py --from-csv output/extract_20261006_0215.csv` | Rebuild from a saved extract, no database |
| `run_nightly.ps1` | Same as the first, with a log; schedule it in Task Scheduler |

Exit code `0` = built, `2` = stopped by a validation error (message on screen and in the log).

## No Python on the server? Export, then build elsewhere

`export_extract.ps1` runs the same patched query with PowerShell and writes a zipped CSV:

```powershell
Install-Module SqlServer -Scope CurrentUser      # once
.\export_extract.ps1 -Server "your-sql-host"
```

Build from that file on any machine with Python: `python build_dashboard.py --from-csv output\extract_<stamp>.csv`.
Locale-formatted dates (e.g. `01/09/2026`) are handled.

## Changes to your query

`sql/channel_sku_extract.sql` is your query with six marked fixes. The untouched original is in `sql/channel_sku_extract.original.sql`, so you can diff the two.

| Fix | Change | Why |
|---|---|---|
| 1 | Extract starts **1 Jan last year** | Needed for vs LY comparisons |
| 2 | Budget runs to 31 Dec this year | The original cut the budget at today |
| 3 | `UPPER(TRIM(Division_ID))` in filters | BC is case-sensitive; `Franchise` ≠ `FRANCHISE` |
| 4 | UAE division blocks exclude rows whose customer category is listed | Those sales were counted twice |
| 5 | Other Income accounts excluded from Sales Budget | Budget included Other Income; actuals did not |
| 6 | Year-end closing entries excluded from Other Income | Matters now that history spans a year end |

Handled in Python rather than SQL:

- **Sign.** The query returns sales and quantity negative. `config.json → sign` flips them, and the build **stops** if either total is still negative.
- **FX.** SAR → AED at 0.979333.
- **Segment mapping.** Precedence is UAE customer category, then department code, then division label. Rows nothing claims are listed on the Data quality page for Group Finance.

## What each audience gets

Each file contains **only** that audience's segments and companies. Scope is enforced when the file is built, so the Retail file holds no B2B or Al Fakhra figures at all. Audiences are defined in `config.json → audiences`.

| File | Contents |
|---|---|
| `sales-dashboard-group.html` | All segments and companies, segment contribution, mapping exceptions |
| `sales-dashboard-retail.html` | Retail, Bateel UAE + KSA |
| `sales-dashboard-jomara-uae.html` | Jomara, Bateel UAE sub-lines only |

**Handling.** These files hold real sales data. Share them only through permission-controlled locations (e.g. a restricted SharePoint library per audience), never by open email or a public link. `output/extract_*.csv` holds the full detail for every segment: keep it on the server; the nightly script deletes extracts older than 30 days.

## Limits to know

- **Actual vs budget basis.** Actuals are item-ledger (Value Entry) sales and budget is G/L, so actuals run slightly below budget by construction (non-item revenue). The Summary G/L extract would give a like-for-like comparison.
- **Unmapped departments.** The query itself drops UAE departments whose Jedoxdept division is not listed, so they never reach the Data quality page.
- **Partial budget.** Where part of a selection has sales but no budget (e.g. Al Fakhra while `2026BUD` is unverified), the dashboard flags that the variance is flattered.
- **COGS and margin** are extracted but not shown. They wait on the agreed COGS rule.
- **AI analyst** is off (`analyst_enabled: false`). It needs Finance/Legal approval to send figures to the Claude API, and it only works when a file is published as a private claude.ai artifact.

## Test

`tests/test_pipeline.py` runs the patched SQL against the mock BC databases and checks 25 outcomes, including the double-count fix, the sign guard and per-audience scoping. Use a disposable SQL Server only:

```bash
sqlcmd ... -i ../tests/mock_sources.sql          # repo root: builds mock BTL_LS_LIVE / FAKHRA_LIVE
sqlcmd ... -i tests/mock_extract_addon.sql
SALES_SQL_SERVER=localhost SALES_SQL_USER=sa SALES_SQL_PASSWORD=... python tests/test_pipeline.py
```
