"""Part 1 - Bronze -> Silver: clean capital_activity_raw.csv.

Run:  python3 part1_clean_capital_activity.py
Reads : ../Docs/capital_activity_raw.csv, ../Docs/commitments.csv
Writes: capital_activity_clean.csv, dq_exceptions.csv (next to this script),
        ../Additional files/dq_duplicates_removed.csv
"""
import re
from pathlib import Path

import pandas as pd

BASE = Path(__file__).parent
INPUT = BASE.parent / "Docs"  # raw + dimension CSVs (not shipped)
EXTRA = BASE.parent / "Additional files"
REPORTING_DATE = pd.Timestamp("2025-12-31")

CLEAN_COLS = ["transaction_id", "fund_id", "investor_id", "transaction_date",
              "transaction_type", "amount", "source_system", "load_timestamp"]


# ---------------------------------------------------------------- helpers
def map_type(label):
    """Rule 1: map any label variant to CALL / DIST (None if unrecognised)."""
    s = re.sub(r"[^a-z]", "", str(label).lower())  # drop spaces, dots, case
    if s in {"call", "capitalcall", "capcall"}:
        return "CALL"
    if s in {"dist", "distribution"}:
        return "DIST"
    return None


def parse_date(value):
    """Rule 2: ISO (YYYY-MM-DD) or US (MM/DD/YYYY). Never guesses day-first."""
    s = str(value).strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        return pd.to_datetime(s, format="%Y-%m-%d", errors="coerce")
    return pd.to_datetime(s, format="%m/%d/%Y", errors="coerce")


def parse_amount(value):
    """Rule 3: strip $ , spaces, parentheses, minus -> positive float (NaN if blank)."""
    if pd.isna(value) or str(value).strip() == "":
        return float("nan")
    s = re.sub(r"[\$,\s()\-]", "", str(value))
    return float(s) if s else float("nan")


def add_reason(reasons, mask, text):
    for idx in reasons.index[mask]:
        reasons.at[idx] = (reasons.at[idx] + "; " if reasons.at[idx] else "") + text


# ------------------------------------------------------------------- main
def main():
    raw = pd.read_csv(INPUT / "capital_activity_raw.csv", dtype=str, keep_default_na=False)
    commitments = pd.read_csv(INPUT / "commitments.csv", dtype=str)
    rows_read = len(raw)

    # Whitespace trim on every text column
    df = raw.apply(lambda c: c.str.strip())
    df["_row"] = raw.index + 2  # line number in the source file (header = line 1)

    # --- Rule 4a: exact duplicates (all raw columns identical)
    exact_dup = df.duplicated(subset=[c for c in df.columns if c != "_row"], keep="first")
    dups_exact = df[exact_dup].assign(duplicate_type="EXACT_DUPLICATE")
    df = df[~exact_dup].copy()

    # --- Standardise (rules 1-3)
    df["transaction_type_raw"] = df["transaction_type"]
    df["transaction_type"] = df["transaction_type"].map(map_type)
    df["transaction_date"] = df["transaction_date"].map(parse_date)
    df["load_timestamp"] = pd.to_datetime(df["load_timestamp"], format="%m/%d/%Y %H:%M", errors="coerce")
    df["amount_raw"] = df["amount"]
    df["amount"] = df["amount"].map(parse_amount)

    # --- Rule 4b: same transaction_id, different values -> keep latest load_timestamp
    df = df.sort_values(["transaction_id", "load_timestamp", "_row"])
    superseded = df.duplicated(subset="transaction_id", keep="last")
    dups_conflict = df[superseded].assign(duplicate_type="SUPERSEDED_BY_LATER_LOAD")
    df = df[~superseded].copy()

    dup_log = pd.concat([dups_exact, dups_conflict])
    dup_out = raw.loc[dup_log["_row"] - 2].copy()  # original raw values, untouched
    dup_out["duplicate_type"] = dup_log["duplicate_type"].values
    dup_out.to_csv(EXTRA / "dq_duplicates_removed.csv", index=False)

    # --- Rule 5: exceptions (a row may fail several tests; all reasons are listed)
    reasons = pd.Series("", index=df.index)
    add_reason(reasons, df["amount"].isna(), "MISSING_AMOUNT")
    valid_pairs = set(zip(commitments["fund_id"], commitments["investor_id"]))
    no_commit = [(f, i) not in valid_pairs for f, i in zip(df["fund_id"], df["investor_id"])]
    add_reason(reasons, pd.Series(no_commit, index=df.index), "NO_MATCHING_COMMITMENT")
    add_reason(reasons, df["transaction_date"] > REPORTING_DATE, "DATE_AFTER_REPORTING_DATE")
    add_reason(reasons, df["transaction_type"].isna(), "UNMAPPED_TRANSACTION_TYPE")
    add_reason(reasons, df["transaction_date"].isna(), "UNPARSEABLE_DATE")

    bad = reasons != ""
    exceptions = df[bad].assign(exception_reason=reasons[bad])
    clean = df[~bad].copy()

    # --- Outputs
    out = clean[CLEAN_COLS].sort_values("transaction_id").copy()
    out["transaction_date"] = out["transaction_date"].dt.strftime("%Y-%m-%d")
    out["load_timestamp"] = out["load_timestamp"].dt.strftime("%Y-%m-%d %H:%M:%S")
    out["amount"] = out["amount"].round(2)
    out.to_csv(BASE / "capital_activity_clean.csv", index=False)

    exc_out = raw.loc[exceptions["_row"] - 2].copy()  # original raw values, untouched
    exc_out["exception_reason"] = exceptions["exception_reason"].values
    exc_out.to_csv(BASE / "dq_exceptions.csv", index=False)

    # --- Rule 6: DQ summary
    sources = raw["source_system"].str.strip().value_counts().to_dict()
    print("=" * 60)
    print("DATA QUALITY SUMMARY")
    print("=" * 60)
    print(f"Rows read                         : {rows_read:>6,}   {sources}")
    print("Duplicates removed")
    print(f"  exact duplicate rows            : {len(dups_exact):>6,}")
    print(f"  superseded (same id, older load): {len(dups_conflict):>6,}")
    print(f"  total                           : {len(dup_log):>6,}")
    print(f"Unique transactions after dedupe  : {len(df):>6,}")
    print(f"Exception rows                    : {len(exceptions):>6,}")
    for reason, n in (exceptions["exception_reason"].str.split("; ").explode()
                      .value_counts().items()):
        print(f"  {reason:<31} : {n:>6,}")
    print(f"Clean rows written                : {len(out):>6,}")
    print("-" * 60)
    check = rows_read - len(dup_log) - len(exceptions) - len(out)
    print(f"Reconciliation (read - dups - exceptions - clean) = {check}  "
          f"{'OK' if check == 0 else 'MISMATCH'}")
    print("Clean totals by type:")
    print(out.groupby("transaction_type")["amount"].agg(["count", "sum"]).round(2).to_string())
    print("=" * 60)


if __name__ == "__main__":
    main()
