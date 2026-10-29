# Fund Capital Activity – Assessment Submission

**Stack:** Python 3.10 + pandas (Part 1), **SQL Server 2022 in Docker** (T-SQL, Part 2; DuckDB used as a cross-check), Power BI Desktop (Part 3).
Input CSVs (`funds`, `investors`, `commitments`, `capital_activity_raw`) are expected in a `Docs/` folder next to the Part folders (not shipped; see `.gitignore`).

## Folder layout
| Folder | Contents |
|---|---|
| `Part 1/` | `part1_clean_capital_activity.py`, `capital_activity_clean.csv` (1,940 rows), `dq_exceptions.csv` (17 rows) |
| `Part 2/` | `part2_queries.sql` (DuckDB), `sqlserver/` (T-SQL queries + loader + `run.sh`), `docker-compose.yml`, `run_part2.py`, `sql_results/q1-q4.csv` |
| `Part 3/` | `TPG.pbix`, `Screenshots/model_view.png`, `Screenshots/report_page.png` |
| `Additional files/` | `dq_duplicates_removed.csv` (43 removed duplicates, audit trail), `PowerBI_Build_Guide.md` (DAX, relationships, page layout) |

Run order (from the project root):
1. `python3 "Part 1/part1_clean_capital_activity.py"`: prints the DQ summary, writes the clean and exceptions files.
2. `./"Part 2"/sqlserver/run.sh` (SQL Server in Docker) **or** `python3 "Part 2/run_part2.py"` (DuckDB): loads the data and runs Q1-Q4.
3. Power BI: see `Part 3/` and `Additional files/PowerBI_Build_Guide.md`.

## Note to the Fund Finance Controller (non-technical summary)
* **Overall:** investors committed **$4,813M** across six funds; **$3,342M (69%)** has been called, **$1,425M** distributed (DPI 0.43x), **$1,471M** still unfunded.
* **Two investors in Meridian Buyout Partners VII have been called for more than they committed** (total excess **$3.78M**): Redwood Life Insurance Co. (+$2.59M, 103.5%) and Granite Retirement System (+$1.19M, 103.5%). Both stem from large round-number calls dated 14 Nov 2025 (TXN101920 $3.91M, TXN101921 $8.51M). **Action: confirm with fund administration whether these calls are valid, were mis-allocated, or need to be reversed/returned.**
* **17 records were excluded and need follow-up** (none were silently dropped – all in `dq_exceptions.csv`):
  * 7 capital calls have **no amount** (e.g. TXN900001–900007) – amounts must be supplied by operations.
  * 6 capital calls ($3.3M) are for **investor/fund pairs with no commitment on file** (e.g. I006 in F02, I038 in F05) – either a missing commitment record or wrong investor/fund coding.
  * 4 manual-upload calls ($5.3M) are **dated in 2026** (Jan–Mar) but were loaded on 2 Jan 2026 – future-dated, excluded from the 31-Dec-2025 view.
* **Fund picture:** Buyout VII is 93% called and has returned 0.94x; Buyout VIII (2023) is only 32% called with no distributions yet; Credit II and Real Estate IV are both 72% called / 0.25x. Funds needing the most future capital: Impact Climate I ($351M unfunded) and Buyout VIII ($467M).
* Reported figures exclude the excluded items above, so called capital is understated until the missing amounts are resolved.

## Assumptions & decisions
1. **Date formats.** The spec says INVESTRAN = `YYYY-MM-DD`, but in the file *both* sources use `M/D/YYYY`. The parser accepts ISO or US month-first and never guesses day-first (it would be ambiguous, e.g. 3/6/2024). Unparseable dates would become exceptions (none occurred).
2. **Duplicates (rule 4).** Applied *before* exceptions so a superseded row never appears as an exception. "Exact" = every raw column identical (18 rows). "Superseded" = same `transaction_id`, different values → keep the latest `load_timestamp` (25 rows; e.g. TXN100795 11.51M→12.11M). Ties on timestamp fall back to file order (none occurred).
3. **Corrected-record caveat:** some superseded pairs differ in amount *and* label formatting (e.g. `Dist.` vs `DIST`); the latest load always wins regardless of source.
4. **Amounts.** `$`, commas, spaces, parentheses and minus signs stripped; stored positive. Distributions arrive as parenthesised negatives from manual uploads and as positives from INVESTRAN – both become positive DIST.
5. **Exceptions** list *all* applicable reasons per row (separated by `;`); exceptions file keeps original raw values for traceability. No row hit more than one reason.
6. **Unfunded** can be negative for over-called investors; I did not cap it at zero so the problem stays visible. DPI divides by zero-safe (`NULLIF`/`DIVIDE`) → NULL/blank when nothing has been called.
7. Currency is USD for all rows (checked); `currency` is therefore not carried to Silver (per the required column list).
8. Reporting date 2025-12-31 is inclusive.

## Validation
* Row reconciliation: 2,000 read − 43 duplicates − 17 exceptions = 1,940 clean (printed by the script, check = 0).
* Fund % called lands on clean values (86.00%, 72.00%, 72.00%, 55.00%, 32.00%) which indicates the dedupe/cleaning matches how the source was built.
* Commitments aggregated separately from activity in every query → no join fan-out (total commitments = $4,813.0M = sum of `commitments.csv`).
* Power BI totals should equal `Part 2/sql_results/q1.csv`.

## Power BI notes
* **Model:** star schema. Fund, Investor and Date are dimensions; Commitments and Capital Activity are facts. All relationships are one-to-many, **single direction** (dimension to fact). The two fact tables are deliberately **not** related to each other (different grains), so measures cannot double-count commitments. Date is marked as the date table and related to `transaction_date`; `Year-Quarter` is sorted by `YearQuarterSort`.
* **Measures:** Total Commitments, Capital Called, Distributions, Unfunded Commitment, % Called, DPI (as specified).
* **Display:** the web card auto-abbreviates numbers, so the KPI cards use text "label" measures (e.g. `$4,813.0M`); the six required measures drive the chart and matrix. DPI is shown as a multiple (e.g. 0.95x = $0.95 distributed per $1 paid in).
* **Check:** unfiltered cards = $4,813.0M / $3,341.6M / $1,425.4M / $1,471.4M, matching `Part 2/sql_results/q1.csv`.

## What I'd do next / not done
* **Power BI was built in Power BI Service (web) on macOS**, as Desktop is Windows-only. `TPG.pbix` was exported from the service; the report visuals are shown in `Part 3/Screenshots/report_page.png` and the star schema in `Part 3/Screenshots/model_view.png`. The full DAX, relationships and page layout are in `Additional files/PowerBI_Build_Guide.md`.
* Add a check for the same economic transaction loaded under *different* `transaction_id`s (I tested fund+investor+date+type+amount: none found).
* Productionise as Bronze/Silver/Gold tables in SQL Server with the exceptions table as a first-class monitored output.

## Run SQL Server in Docker (any PC/Mac)
Needs Docker Desktop. From the project root: `./"Part 2"/sqlserver/run.sh` (Windows: run the same `docker compose up -d`, `docker cp` and `sqlcmd` steps from that script in Git Bash/WSL).
Connect from SSMS / Azure Data Studio / Power BI: **server `localhost,1433`, user `sa`, password `TpgAssess#2025` (change in `.env`), database `FundCapital`**.
Files (in `Part 2/`): `docker-compose.yml`, `sqlserver/01_load.sql` (schema + BULK INSERT), `sqlserver/02_queries_tsql.sql` (Q1-Q4). Apple Silicon runs the amd64 image under emulation (enable Rosetta in Docker Desktop for speed). The T-SQL output matches the DuckDB results exactly.

## Quick walkthrough (how to explain / re-run)
1. `python3 -m pip install pandas duckdb` then `python3 "Part 1/part1_clean_capital_activity.py"` - prints the DQ summary and writes the clean, exceptions and duplicates files.
2. `./"Part 2"/sqlserver/run.sh` (or `python3 "Part 2/run_part2.py"`) - loads the clean output and the dimensions, runs Q1-Q4.
3. Over-calls (Q3) tie back to two Nov-2025 calls; the 17 exceptions are listed with reasons in `Part 1/dq_exceptions.csv`.
