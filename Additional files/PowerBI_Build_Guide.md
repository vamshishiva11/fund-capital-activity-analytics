# Part 3 – Power BI build guide (Power BI Desktop, Windows)

## 1. Load (Get Data > Text/CSV)
Load: `funds.csv`, `investors.csv`, `commitments.csv`, `capital_activity_clean.csv` (the Part 1 output).
Rename tables: **Fund**, **Investor**, **Commitments**, **Capital Activity**.
Types: `commitment_amount`, `amount` = Fixed decimal; `transaction_date`, `commitment_date` = Date; `vintage_year` = Whole number (set "Don't summarize").
Hide key columns (fund_id/investor_id) in the fact tables so users filter from dimensions only.

## 2. Date table (DAX) – Modeling > New table, then Table tools > Mark as date table (column `Date`)
```DAX
Date =
VAR MinD = DATE(YEAR(MIN('Capital Activity'[transaction_date])), 1, 1)
VAR MaxD = DATE(YEAR(MAX('Capital Activity'[transaction_date])), 12, 31)
RETURN
ADDCOLUMNS(
    CALENDAR(MinD, MaxD),
    "Year", YEAR([Date]),
    "Quarter", "Q" & QUARTER([Date]),
    "Year-Quarter", YEAR([Date]) & "-Q" & QUARTER([Date]),
    "YearQuarterSort", YEAR([Date]) * 10 + QUARTER([Date])
)
```
Sort `Year-Quarter` by `YearQuarterSort`.

## 3. Relationships (star schema) – all 1:many, single direction (dimension -> fact)
| From (1) | To (many) | Direction | Why |
|---|---|---|---|
| Fund[fund_id] | Commitments[fund_id] | Single | dimension filters facts |
| Fund[fund_id] | Capital Activity[fund_id] | Single | same |
| Investor[investor_id] | Commitments[investor_id] | Single | same |
| Investor[investor_id] | Capital Activity[investor_id] | Single | same |
| Date[Date] | Capital Activity[transaction_date] | Single | time axis for activity |

Deliberate choices to explain in interview:
* **Single direction, no bi-directional.** Two facts share the same dimensions; bi-directional would create ambiguous paths and let one fact filter the other unpredictably.
* **Commitments and Capital Activity are NOT related to each other** – they are different grains (investor+fund vs transaction). They meet only through the shared Fund / Investor dimensions, so the measures cannot double-count commitments.
* **Date relates to Capital Activity only.** Commitments have a `commitment_date`, but the report's time axis is transaction date; Total Commitments therefore is *not* filtered by the year axis (it stays at the fund/investor level, which is what makes % Called and Unfunded correct). Optional: add an inactive Date -> Commitments[commitment_date] relationship and use `USERELATIONSHIP` if commitments-by-year is needed.

## 4. Measures (create a `_Measures` table)
```DAX
Total Commitments = SUM(Commitments[commitment_amount])

Capital Called =
CALCULATE(SUM('Capital Activity'[amount]), 'Capital Activity'[transaction_type] = "CALL")

Distributions =
CALCULATE(SUM('Capital Activity'[amount]), 'Capital Activity'[transaction_type] = "DIST")

Unfunded Commitment = [Total Commitments] - [Capital Called]

% Called = DIVIDE([Capital Called], [Total Commitments])

DPI = DIVIDE([Distributions], [Capital Called])
```
Formats: money measures `$#,0.0,,"M"` ; % Called `0.0%` ; DPI `0.00"x"`.

## 5. Report page (one page, 16:9)
* Title: "Fund Capital Activity – as of 31 Dec 2025"
* Top row: 4 **Card** visuals – Total Commitments, Capital Called, Distributions, Unfunded Commitment.
* Left: **Slicers** – Fund[strategy] (dropdown), Fund[vintage_year] (dropdown/tile).
* Middle: **Clustered column** – Axis `Date[Year]` (or Year-Quarter), Values `Capital Called`, `Distributions`.
* Bottom: **Matrix** – Rows `Fund[fund_name]`, Columns `Investor[investor_type]`, Values: Total Commitments, Capital Called, % Called, DPI. (Wide: show investor types in columns and reduce to 4 values; or use "Stepped layout off". Alternative: put investor_type as a second row level to keep it readable.)
* Optional: a small table "Over-called investors" (see Q3) as a data-quality callout.

## 6. Sanity checks to run in the report (must match SQL results in sql_results/q1.csv)
With no slicer: Commitments $4,813.0M ; Called $3,341.6M ; Distributions $1,425.4M ; Unfunded $1,471.4M. 
Buyout VII: 93.5% called, DPI 0.94x.  Buyout VIII: 32.0% called, DPI 0.00x.

## 7. Screenshots
Take: (1) Model view, (2) the report page -> save into `screenshots/`.
