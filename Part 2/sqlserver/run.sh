#!/usr/bin/env bash
# One command: start SQL Server in Docker, load the CSVs, run the T-SQL queries.
set -euo pipefail
cd "$(dirname "$0")/.."
PW="${MSSQL_SA_PASSWORD:-TpgAssess#2025}"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P $PW"
docker compose up -d
echo "Waiting for SQL Server to be healthy..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' tpg_sqlserver)" = "healthy" ]; do sleep 3; done
# BULK INSERT can't read Docker bind mounts reliably, so copy CSVs onto the container's own disk
docker exec -u root tpg_sqlserver mkdir -p /var/opt/mssql/data_in
for f in funds investors commitments; do docker cp "../Docs/$f.csv" tpg_sqlserver:/var/opt/mssql/data_in/; done
docker cp "../Part 1/capital_activity_clean.csv" tpg_sqlserver:/var/opt/mssql/data_in/
docker exec -u root tpg_sqlserver chmod -R a+rX /var/opt/mssql/data_in
docker exec tpg_sqlserver $SQLCMD -b -i /scripts/01_load.sql
docker exec tpg_sqlserver $SQLCMD -b -s"," -W -i /scripts/02_queries_tsql.sql
echo "Connect with: server localhost,1433 | user sa | password $PW | database FundCapital"
