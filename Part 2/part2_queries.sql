-- Engine: DuckDB (ANSI SQL; runs on T-SQL with minor changes: FORMAT/DATE_TRUNC -> DATEPART/EOMONTH, NULLIF kept as-is)
-- Tables loaded by run_part2.py: funds, investors, commitments, capital_activity_clean
-- GRAIN WARNING: commitments = 1 row per investor+fund; activity = many rows per investor+fund.
-- Every query aggregates each side to its own grain BEFORE joining, so commitments are never double-counted.

-- Q1. Fund summary: commitments, called, distributions, unfunded, % called, DPI. Sorted by vintage year.
WITH commit_by_fund AS (
    SELECT fund_id, SUM(commitment_amount) AS total_commitments
    FROM commitments GROUP BY fund_id
), activity_by_fund AS (
    SELECT fund_id,
           SUM(CASE WHEN transaction_type = 'CALL' THEN amount ELSE 0 END) AS capital_called,
           SUM(CASE WHEN transaction_type = 'DIST' THEN amount ELSE 0 END) AS distributions
    FROM capital_activity_clean GROUP BY fund_id
)
SELECT f.fund_name, f.strategy, f.vintage_year,
       c.total_commitments,
       COALESCE(a.capital_called, 0)                                   AS capital_called,
       COALESCE(a.distributions, 0)                                    AS distributions,
       c.total_commitments - COALESCE(a.capital_called, 0)             AS unfunded_commitment,
       ROUND(100.0 * COALESCE(a.capital_called, 0) / c.total_commitments, 2) AS pct_called,
       ROUND(COALESCE(a.distributions, 0) / NULLIF(a.capital_called, 0), 3) AS dpi
FROM funds f
JOIN commit_by_fund c ON c.fund_id = f.fund_id
LEFT JOIN activity_by_fund a ON a.fund_id = f.fund_id
ORDER BY f.vintage_year, f.fund_id;

-- Q2. Top 3 investors per fund by commitment (window function), with % of the fund's total commitments.
WITH ranked AS (
    SELECT c.fund_id, c.investor_id, c.commitment_amount,
           ROW_NUMBER() OVER (PARTITION BY c.fund_id ORDER BY c.commitment_amount DESC, c.investor_id) AS rnk,
           SUM(c.commitment_amount) OVER (PARTITION BY c.fund_id) AS fund_total
    FROM commitments c
)
SELECT f.fund_name, r.rnk AS rank, i.investor_name, i.investor_type,
       r.commitment_amount,
       ROUND(100.0 * r.commitment_amount / r.fund_total, 2) AS pct_of_fund_commitments
FROM ranked r
JOIN funds f     ON f.fund_id = r.fund_id
JOIN investors i ON i.investor_id = r.investor_id
WHERE r.rnk <= 3
ORDER BY f.vintage_year, f.fund_id, r.rnk;

-- Q3. Over-call check: investor + fund where total called > commitment.
WITH called AS (
    SELECT fund_id, investor_id, SUM(amount) AS total_called
    FROM capital_activity_clean
    WHERE transaction_type = 'CALL'
    GROUP BY fund_id, investor_id
)
SELECT f.fund_name, i.investor_name, c.commitment_amount,
       k.total_called,
       k.total_called - c.commitment_amount AS excess_amount,
       ROUND(100.0 * k.total_called / c.commitment_amount, 1) AS pct_of_commitment_called
FROM commitments c
JOIN called k    ON k.fund_id = c.fund_id AND k.investor_id = c.investor_id
JOIN funds f     ON f.fund_id = c.fund_id
JOIN investors i ON i.investor_id = c.investor_id
WHERE k.total_called > c.commitment_amount
ORDER BY excess_amount DESC;

-- Q4 (bonus). Capital called per calendar quarter per fund, with running cumulative total.
WITH q AS (
    SELECT fund_id,
           YEAR(transaction_date)    AS yr,
           QUARTER(transaction_date) AS qtr,
           SUM(amount)               AS capital_called
    FROM capital_activity_clean
    WHERE transaction_type = 'CALL'
    GROUP BY fund_id, YEAR(transaction_date), QUARTER(transaction_date)
)
SELECT f.fund_name,
       CAST(q.yr AS VARCHAR) || '-Q' || CAST(q.qtr AS VARCHAR) AS year_quarter,
       q.capital_called,
       SUM(q.capital_called) OVER (PARTITION BY q.fund_id ORDER BY q.yr, q.qtr
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_called
FROM q
JOIN funds f ON f.fund_id = q.fund_id
ORDER BY f.vintage_year, f.fund_id, q.yr, q.qtr;
