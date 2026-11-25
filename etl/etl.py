"""
Australian Retail & Consumer Spending Analytics — ETL

Pulls:
  1. ABS Retail Trade (dataflow "RT") — turnover by state x industry, last 24 months
  2. RBA Cash Rate Target (table F1)
  3. RBA CPI (table G1)

Writes raw pulls to S3 (raw/) and cleaned tables to S3 (processed/) and Postgres.

Required environment variables:
  S3_BUCKET   - S3 bucket name for raw/processed data
  DB_HOST     - Postgres host (RDS endpoint)
  DB_NAME     - Postgres database name
  DB_USER     - Postgres username
  DB_PASSWORD - Postgres password (fetch from Secrets Manager/SSM in production;
                for local testing this can be a plain env var)
"""

import csv
import io
import os
import sys
import logging
from datetime import datetime, timezone

import boto3
import pandas as pd
import requests
from sqlalchemy import create_engine

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("retail_etl")

ABS_RETAIL_TRADE_URL = (
    "https://data.api.abs.gov.au/rest/data/RT/all"
    "?format=csvfilewithlabels&lastNObservations=24"
)
RBA_CASH_RATE_URL = "https://www.rba.gov.au/statistics/tables/csv/f1-data.csv"
RBA_CPI_URL = "https://www.rba.gov.au/statistics/tables/csv/g1-data.csv"

REQUEST_TIMEOUT = 30  # ABS API gateway hard-limits responses to 30s anyway


def get_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def fetch_abs_retail_trade() -> pd.DataFrame:
    """Pull ABS Retail Trade turnover by state x industry for the last 24 months."""
    log.info("Fetching ABS Retail Trade data...")
    headers = {"Accept-Encoding": "gzip, deflate"}
    resp = requests.get(ABS_RETAIL_TRADE_URL, headers=headers, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    df = pd.read_csv(io.StringIO(resp.text))
    log.info("Retrieved %d rows from ABS Retail Trade", len(df))
    return df


def fetch_rba_table(url: str, label: str) -> pd.DataFrame:
    """
    RBA CSV tables have several metadata rows (title, description, units,
    source, publication date, series IDs) before the actual data starts.
    The metadata rows themselves are NOT reliably the same width as the
    data — in particular the "Title" row (the very first line) can be
    shorter than the number of actual series/columns, because RBA doesn't
    always pad every metadata row out to the full column count.
    Anchoring the column count on the Title row (as an earlier version of
    this function did) silently truncated every data row down to that
    narrower width — which is what caused rba_cash_rate and rba_cpi to
    come out as a single "Date" column with no values at all.

    Fix: anchor both the column COUNT and the column NAMES on the
    "Series ID" row instead of the Title row. Series ID is the last
    metadata row before data starts, and it reliably has exactly one
    entry per real data column (that's its whole purpose), so it's a
    much safer source of truth for how many columns this table actually
    has.
    """
    log.info("Fetching RBA table: %s", label)
    resp = requests.get(url, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()

    rows = list(csv.reader(resp.text.splitlines()))
    if not rows:
        raise ValueError(f"RBA table {label} returned no content")

    series_id_idx = None
    for i, row in enumerate(rows):
        if row and row[0].strip().lower() == "series id":
            series_id_idx = i
            break

    if series_id_idx is None:
        raise ValueError(f"Could not find the 'Series ID' marker row in RBA table {label}")

    # Use the Series ID row itself for both the column count and the
    # column names — it's the authoritative width for this table.
    header = list(rows[series_id_idx])
    header[0] = "Date"
    ncols = len(header)

    data_rows = []
    for row in rows[series_id_idx + 1:]:
        if not row or not row[0].strip():
            continue
        if len(row) < ncols:
            row = row + [""] * (ncols - len(row))
        elif len(row) > ncols:
            row = row[:ncols]
        data_rows.append(row)

    if not data_rows:
        raise ValueError(f"Could not locate any data rows in RBA table {label}")

    df = pd.DataFrame(data_rows, columns=header)
    df["Date"] = pd.to_datetime(df["Date"], errors="coerce")
    df = df.dropna(subset=["Date"])

    for col in df.columns[1:]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    # Sanity check: a table with only a Date column means something is
    # still wrong upstream (format change, no series found) — better to
    # fail loudly here than silently ship a useless CSV again.
    if df.shape[1] < 2:
        raise ValueError(
            f"RBA table {label} parsed with no data columns (only Date) — "
            "the source format may have changed."
        )

    log.info(
        "Retrieved %d rows x %d columns from RBA table %s",
        len(df), df.shape[1], label,
    )
    return df


def upload_to_s3(bucket: str, key: str, df: pd.DataFrame) -> None:
    s3 = boto3.client("s3")
    buffer = io.StringIO()
    df.to_csv(buffer, index=False)
    s3.put_object(Bucket=bucket, Key=key, Body=buffer.getvalue())
    log.info("Uploaded %s to s3://%s/%s", key, bucket, key)


def load_to_postgres(engine, table_name: str, df: pd.DataFrame) -> None:
    df.to_sql(table_name, engine, if_exists="replace", index=False)
    log.info("Loaded %d rows into Postgres table '%s'", len(df), table_name)


def main() -> int:
    bucket = get_env("S3_BUCKET")
    db_host = get_env("DB_HOST")
    db_name = get_env("DB_NAME")
    db_user = get_env("DB_USER")
    db_password = get_env("DB_PASSWORD")

    run_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    try:
        retail_df = fetch_abs_retail_trade()
        cash_rate_df = fetch_rba_table(RBA_CASH_RATE_URL, "Cash Rate (F1)")
        cpi_df = fetch_rba_table(RBA_CPI_URL, "CPI (G1)")
    except requests.RequestException as exc:
        log.error("A data source request failed: %s", exc)
        return 1
    except ValueError as exc:
        log.error("A data source could not be parsed: %s", exc)
        return 1

    # Raw dumps to S3 for auditability / reprocessing
    upload_to_s3(bucket, f"raw/retail_trade_{run_date}.csv", retail_df)
    upload_to_s3(bucket, f"raw/rba_cash_rate_{run_date}.csv", cash_rate_df)
    upload_to_s3(bucket, f"raw/rba_cpi_{run_date}.csv", cpi_df)

    # Processed copies (same shape for now — this is where cleaning/renaming
    # logic can grow as you look at the real data more closely)
    upload_to_s3(bucket, "processed/retail_trade_latest.csv", retail_df)
    upload_to_s3(bucket, "processed/rba_cash_rate_latest.csv", cash_rate_df)
    upload_to_s3(bucket, "processed/rba_cpi_latest.csv", cpi_df)

    db_url = f"postgresql+psycopg2://{db_user}:{db_password}@{db_host}:5432/{db_name}"
    engine = create_engine(db_url)

    try:
        load_to_postgres(engine, "retail_trade", retail_df)
        load_to_postgres(engine, "rba_cash_rate", cash_rate_df)
        load_to_postgres(engine, "rba_cpi", cpi_df)
    except Exception as exc:  # noqa: BLE001 - want to log any DB error before exiting
        log.error("Failed to load data into Postgres: %s", exc)
        return 1

    log.info("ETL run complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
