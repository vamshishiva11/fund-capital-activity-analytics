"""Part 2 runner: loads CSVs into DuckDB, runs each query in part2_queries.sql, exports sql_results/qN.csv."""
import re
from pathlib import Path
import duckdb

BASE = Path(__file__).parent
INPUT = BASE.parent / "Docs"
CLEAN = BASE.parent / "Part 1" / "capital_activity_clean.csv"
con = duckdb.connect()
for t, path in [("funds", INPUT / "funds.csv"), ("investors", INPUT / "investors.csv"),
                ("commitments", INPUT / "commitments.csv"),
                ("capital_activity_clean", CLEAN)]:
    con.execute(f"CREATE TABLE {t} AS SELECT * FROM read_csv_auto('{path}')")

sql = (BASE / "part2_queries.sql").read_text()
for block in re.split(r"(?=^-- Q\d)", sql, flags=re.M):
    m = re.match(r"-- (Q\d)", block)
    if not m:
        continue
    df = con.execute(block).df()
    df.to_csv(BASE / "sql_results" / f"{m.group(1).lower()}.csv", index=False)
    print(f"\n{block.splitlines()[0]}\n{df.to_string(index=False)}")
