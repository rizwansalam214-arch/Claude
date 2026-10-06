# Bateel Sales Semantic Layer — Phase 1 (sales only)

The governed layer the Sales & COGS dashboard and AI analyst will read from. **Scope: Net Sales, Qty, Other Income and Sales Budget. COGS is parked** until the per-segment COGS rule is agreed.

It replaces the logic in `channel_sku_extract.sql` and `summary_gl_extract.sql`. The BC databases stay read-only; everything is built in a separate reporting database (e.g. `BATEEL_RPT`).

## Layout

| Path | Purpose |
|---|---|
| `sql/00_schemas.sql` | `cfg` (configuration), `src` (source synonyms), `rpt` (semantic layer) |
| `sql/01_synonyms.sql` | The **only** place BC table names appear |
| `sql/02_config_tables.sql` | Settings, FX, companies, segments, segment rules, Other Income accounts, budget versions |
| `sql/03_config_seed.sql` | Seed from build prompt v2 Appendix A/B. PROVISIONAL rows = open items |
| `sql/04_functions.sql` | Department → division lookup; segment resolver with precedence |
| `sql/05_source_views.sql` | `rpt.vSalesSku` (Value Entry), `rpt.vSalesGL` (G/L), `rpt.vBudgetSales` (G/L Budget) |
| `sql/06_facts_and_load.sql` | Fact tables, `rpt.usp_LoadSales`, `rpt.vBudgetSalesDaily` |
| `sql/07_data_quality_views.sql` | Feeds the Data Quality page |
| `diagnostics/` | Read-only checks to run on live data **before** go-live |
| `tests/` | Mock BC databases and 28 assertions |

## Deploy

1. DBA creates `BATEEL_RPT`. Service account: read on `BTL_LS_LIVE` / `FAKHRA_LIVE`, write on `BATEEL_RPT` only.
2. Run `sql/00` → `sql/07` in order, in `BATEEL_RPT`. All scripts are re-runnable.
3. Schedule nightly: `EXEC rpt.usp_LoadSales;` (full reload of the 24-month window plus all active budget versions, in one transaction).

## Definitions

| Item | Rule |
|---|---|
| Net Sales — SKU basis | `+[Sales Amount (Actual)]`, Value Entry, Item Ledger Entry Type = Sale |
| Qty | `−[Item Ledger Entry Quantity]` (positive for sales) |
| Net Sales — P&L basis | `−[Amount]`, G/L accounts `3*` excluding `cfg.OtherIncomeAccount` |
| Other Income | `−[Amount]`, accounts 30160–30163, 30170. Own line (`LineType = OTHER_INCOME`) |
| Sales Budget | `−[Amount]`, G/L Budget `3*`, same split as P&L. Active names in `cfg.BudgetVersion` |
| Currency | AED = local × `cfg.FxRate` (SAR 0.979333, one stored value) |
| History | `cfg.Setting HISTORY_MONTHS` = 24 full months + current month |
| Closing entries | G/L entries at 23:59:59 (year-end close) excluded |

**Segment precedence** (one segment per transaction, never two): customer category (UAE GD1) → explicit department rule → Jedoxdept division. Anything unmatched goes to `UNASSIGNED` and is shown, never dropped.

## How each known defect is resolved

| # | Defect (build prompt §4) | Resolution | Test |
|---|---|---|---|
| 1 | Budget sign inconsistent with actuals | One sign convention for all three sources; actuals were the inverted side in the Detail extract | 01, 07, 15, 19 |
| 2 | UAE customer category / division overlap → double count | Single resolver with precedence, applied to actuals **and** budget; overridden rows flagged | 02–04, 18 |
| 3 | Other Income inside `3*` and merged again | `cfg.OtherIncomeAccount` splits it to its own line in actuals and budget | 16, 21 |
| 4 | Division labels normalised on actuals, not budget | Labels come from `cfg.SegmentRule`, identical for actuals and budget | 19, 20 |
| 5 | Cust-cat budget rows used a different department key | Department key is always GD2 (UAE/KSA) / GD1 (Fakhra) | 20 |
| 6 | Unverified: Fakhra budget name, SNS Division_ID, code 017 | Held as PROVISIONAL config; `dqBudgetCoverage` and `dqProvisionalMapping` show impact | 23, 27 |

Additional defects found and fixed:

- **Case sensitivity:** Division_ID is upper-cased before matching, so `Franchise` = `FRANCHISE` (test 05).
- **Jedoxdept join:** exact code match first, numeric match as fallback, so non-numeric codes no longer drop silently.
- **Fakhra department names:** taken only from the Global Dimension 1 dimension, not `TOP 1` across all dimensions (test 13).
- **Silent drops:** unmapped Fakhra and UAE codes kept as `UNASSIGNED` (tests 12, 14).
- **Budget cut-off at today:** full-year budget loaded (test 22).
- **Year-end close:** closing entries excluded so 24-month history keeps December (test 17).

## Data Quality views

| View | Shows |
|---|---|
| `rpt.dqLastLoad` | Last load time, status and row counts |
| `rpt.dqUnassigned` | Sales/budget no rule claims, by code |
| `rpt.dqUnresolvedDepartment` | UAE/KSA department codes missing from Jedoxdept |
| `rpt.dqPrecedenceOverride` | Volume where precedence decided the segment (what used to be double counted) |
| `rpt.dqProvisionalMapping` | Amounts riding on unconfirmed rules |
| `rpt.dqBudgetCoverage` | Budget versions that loaded nothing (e.g. wrong name) |
| `rpt.dqSkuToPLBridge` | SKU basis vs P&L basis by month, company and segment |

## Before go-live: run on live data

| Script | Confirms | Owner |
|---|---|---|
| `diagnostics/01_sign_check.sql` | BC signs match the convention above | IT |
| `diagnostics/02_collation_and_jedoxdept_check.sql` | Collation, Division_ID spelling, non-numeric / duplicate dept codes | IT |
| `diagnostics/03_sns_franchise_check.sql` | Exact SNS Division_ID | IT / Finance |
| `diagnostics/04_fakhra_checks.sql` | Fakhra budget name, code 017, unmapped departments with sales | IT / Finance |
| `diagnostics/05_closing_entries_check.sql` | Closing entries exist on revenue accounts | IT |
| `diagnostics/06_summary_budget_rowcount.sql` | Whether the Summary budget is lost in SQL or in the renderer | IT |

## Open decisions (sales scope)

1. **MTD vs budget phasing:** `rpt.vBudgetSalesDaily` spreads evenly by calendar day. Trading-day phasing or full-month-only are alternatives. *Finance.*
2. **UAE customer category 1181:** provisionally Jomara UAE Exports. *Finance.*
3. **Jedoxdept is shared by UAE and KSA:** if department numbers overlap between companies, a company column is needed. Confirm with diagnostic 02. *IT.*
4. **Inter-company eliminations:** not in this phase. *Finance.*

## Tests

```bash
SQLCMD="sqlcmd -C -S <host> -U <user> -P <password>" tests/run_tests.sh
```

Use a disposable SQL Server only: the script drops and recreates `BTL_LS_LIVE`, `FAKHRA_LIVE` and `BATEEL_RPT`.
