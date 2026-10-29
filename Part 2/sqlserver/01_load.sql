-- Creates database FundCapital and loads the 4 CSVs (Part 1 output + dimensions). Re-runnable.
IF DB_ID('FundCapital') IS NOT NULL
BEGIN
    ALTER DATABASE FundCapital SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE FundCapital;
END
GO
CREATE DATABASE FundCapital;
GO
USE FundCapital;
GO
CREATE TABLE dbo.funds (
    fund_id CHAR(3) PRIMARY KEY, fund_name VARCHAR(100), strategy VARCHAR(50),
    vintage_year INT, currency CHAR(3), target_size_mm INT);
CREATE TABLE dbo.investors (
    investor_id CHAR(4) PRIMARY KEY, investor_name VARCHAR(100),
    investor_type VARCHAR(50), country VARCHAR(50));
CREATE TABLE dbo.commitments (
    commitment_id CHAR(5) PRIMARY KEY, fund_id CHAR(3) REFERENCES dbo.funds(fund_id),
    investor_id CHAR(4) REFERENCES dbo.investors(investor_id),
    commitment_amount DECIMAL(18,2), commitment_date DATE,
    CONSTRAINT uq_commit UNIQUE (fund_id, investor_id));
CREATE TABLE dbo.capital_activity_clean (
    transaction_id VARCHAR(12) PRIMARY KEY, fund_id CHAR(3), investor_id CHAR(4),
    transaction_date DATE, transaction_type CHAR(4) CHECK (transaction_type IN ('CALL','DIST')),
    amount DECIMAL(18,2) CHECK (amount > 0), source_system VARCHAR(20), load_timestamp DATETIME2(0));
GO
-- commitment_date in commitments.csv is M/D/YYYY, so load as text first
CREATE TABLE #c (commitment_id CHAR(5), fund_id CHAR(3), investor_id CHAR(4), commitment_amount DECIMAL(18,2), commitment_date VARCHAR(20));
BULK INSERT dbo.funds     FROM '/var/opt/mssql/data_in/funds.csv'     WITH (FORMAT='CSV', FIRSTROW=2, ROWTERMINATOR='0x0a');
BULK INSERT dbo.investors FROM '/var/opt/mssql/data_in/investors.csv' WITH (FORMAT='CSV', FIRSTROW=2, ROWTERMINATOR='0x0a');
BULK INSERT #c            FROM '/var/opt/mssql/data_in/commitments.csv' WITH (FORMAT='CSV', FIRSTROW=2, ROWTERMINATOR='0x0a');
INSERT dbo.commitments SELECT commitment_id, fund_id, investor_id, commitment_amount, CONVERT(DATE, LTRIM(RTRIM(REPLACE(commitment_date, CHAR(13), ''))), 101) FROM #c;
BULK INSERT dbo.capital_activity_clean FROM '/var/opt/mssql/data_in/capital_activity_clean.csv' WITH (FORMAT='CSV', FIRSTROW=2, ROWTERMINATOR='0x0a');
GO
SELECT 'funds' t, COUNT(*) n FROM dbo.funds UNION ALL SELECT 'investors', COUNT(*) FROM dbo.investors
UNION ALL SELECT 'commitments', COUNT(*) FROM dbo.commitments UNION ALL SELECT 'capital_activity_clean', COUNT(*) FROM dbo.capital_activity_clean;
GO
