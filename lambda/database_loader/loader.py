"""Pure, AWS-free Phase 5 loading logic.

Everything in this module is unit-testable without AWS or a live database. The
orchestrator :func:`process_batch` operates on an injected ``db`` object (see
``db.Database``) whose methods perform the actual SQL. Tests pass a fake ``db``.

The database is fed from the Phase 3 curated Parquet dataset, whose columns are
produced by ``jobs/transform_helpers.py``:

    customer_id, name, email, sales, sales_category, ingestion_timestamp,
    processed_timestamp, phase1_batch_id, phase3_batch_id, source_filename,
    source_raw_key, source_clean_key, pipeline_version, year, month, day

``phase3_batch_id`` is the Phase 5 batch key (renamed ``batch_id`` in staging).
"""

from __future__ import annotations

import hashlib
import json
import logging
import contextlib
import os
import tempfile
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, Sequence


# Curated column that identifies a batch, and the staging column it maps to.
CURATED_BATCH_COLUMN = "phase3_batch_id"
STAGING_BATCH_COLUMN = "batch_id"

# Columns copied from a curated row into staging.customers.
STAGING_COLUMNS: tuple[str, ...] = (
    "customer_id",
    "name",
    "email",
    "sales",
    "sales_category",
    "ingestion_timestamp",
    "processed_timestamp",
    "phase1_batch_id",
    STAGING_BATCH_COLUMN,
    "source_filename",
    "source_raw_key",
    "source_clean_key",
    "pipeline_version",
)

STATUS_SUCCESS = "SUCCESS"
STATUS_FAILED = "FAILED"
STATUS_SKIPPED = "SKIPPED"


def utc_now_iso() -> str:
    """Return the current UTC timestamp in ISO-8601 form (matches Phase 1/3)."""
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def structured_log(logger: logging.Logger, level: int = logging.INFO, **fields: Any) -> str:
    """Emit a single structured JSON log line and return it.

    Every line carries a timestamp and the ``streamforge`` / ``database_loader``
    identity so log-based metrics and dashboards can filter reliably.
    """
    payload = {
        "timestamp": utc_now_iso(),
        "pipeline": "streamforge",
        "stage": "database_loader",
        **fields,
    }
    line = json.dumps(payload, sort_keys=True, default=str)
    logger.log(level, line)
    return line


def read_parquet_rows(data: bytes) -> list[dict[str, Any]]:
    """Decode curated Parquet ``data`` into a list of row dicts.

    DuckDB is imported lazily so pure helpers remain importable without the
    runtime-only Parquet engine.
    """
    import duckdb  # local import: runtime-only dependency

    descriptor, path = tempfile.mkstemp(suffix=".parquet")
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(data)
        connection = duckdb.connect(":memory:")
        try:
            result = connection.execute("SELECT * FROM read_parquet(?)", [path])
            columns = [column[0] for column in result.description]
            return [dict(zip(columns, row)) for row in result.fetchall()]
        finally:
            connection.close()
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(path)


def extract_batch_id(rows: Sequence[Mapping[str, Any]]) -> str:
    """Return the single batch id shared by ``rows``.

    Raises ``ValueError`` if the rows are empty or span more than one batch,
    which would indicate a malformed curated object.
    """
    ids = {
        str(row.get(CURATED_BATCH_COLUMN))
        for row in rows
        if row.get(CURATED_BATCH_COLUMN)
    }
    if not ids:
        raise ValueError(f"Curated rows are missing a {CURATED_BATCH_COLUMN} value")
    if len(ids) > 1:
        raise ValueError(f"Curated object spans multiple batches: {sorted(ids)}")
    return ids.pop()


def _coerce_sales(value: Any) -> int:
    """Return ``value`` as a non-negative integer or raise ``ValueError``."""
    if value is None or value == "":
        raise ValueError("sales is missing")
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise ValueError("sales is not a valid number") from None
    if not number.is_integer():
        raise ValueError("sales must be a whole number")
    result = int(number)
    if result < 0:
        raise ValueError("sales must be non-negative")
    return result


def normalize_and_validate(
    rows: Iterable[Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    """Split curated ``rows`` into staging-ready rows and per-record errors.

    Validation rules (mandatory fields, numeric sales, duplicate business keys)
    mirror the Phase 5 spec. Invalid or duplicate rows never abort the batch;
    they are returned as errors for ``audit.load_errors`` and the batch loads
    the remaining good rows.
    """
    valid: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    seen: set[str] = set()

    for row in rows:
        customer_id = row.get("customer_id")
        source_file = row.get("source_filename")
        if customer_id is None or str(customer_id).strip() == "":
            errors.append(
                {
                    "customer_id": "",
                    "error_message": "missing customer_id",
                    "source_file": str(source_file or ""),
                }
            )
            continue

        customer_id = str(customer_id).strip()
        if customer_id in seen:
            errors.append(
                {
                    "customer_id": customer_id,
                    "error_message": "duplicate customer_id within batch",
                    "source_file": str(source_file or ""),
                }
            )
            continue

        try:
            sales = _coerce_sales(row.get("sales"))
        except ValueError as exc:
            errors.append(
                {
                    "customer_id": customer_id,
                    "error_message": str(exc),
                    "source_file": str(source_file or ""),
                }
            )
            continue

        seen.add(customer_id)
        staged = {column: row.get(column) for column in STAGING_COLUMNS}
        staged["customer_id"] = customer_id
        staged["sales"] = sales
        staged[STAGING_BATCH_COLUMN] = row.get(CURATED_BATCH_COLUMN)
        valid.append(staged)

    return valid, errors


def compute_checksum(rows: Sequence[Mapping[str, Any]]) -> str:
    """Return a deterministic checksum over the batch's business content."""
    digest = hashlib.sha256()
    for row in sorted(rows, key=lambda item: str(item.get("customer_id"))):
        digest.update(f"{row.get('customer_id')}:{row.get('sales')};".encode("utf-8"))
    return digest.hexdigest()


def process_batch(
    db: Any,
    rows: Sequence[Mapping[str, Any]],
    *,
    source_file: str,
    logger: logging.Logger,
) -> dict[str, Any]:
    """Load one curated batch into the serving database, idempotently.

    ``db`` is any object implementing the ``db.Database`` interface. The whole
    batch runs inside a single transaction; a critical failure rolls back and
    marks the batch FAILED (re-raising for the caller to alert on). Per-record
    data errors are captured to ``audit.load_errors`` without failing the batch.

    Returns a result dict describing the outcome (also used for structured
    logging and SNS notifications).
    """
    batch_id = extract_batch_id(rows)

    # Incremental loading: a batch already marked SUCCESS is skipped.
    if db.get_batch_status(batch_id) == STATUS_SUCCESS:
        structured_log(
            logger,
            batch_id=batch_id,
            source_file=source_file,
            status=STATUS_SKIPPED,
            message="batch already processed; skipping",
        )
        return {"batch_id": batch_id, "status": STATUS_SKIPPED, "records_loaded": 0}

    start = utc_now_iso()
    valid_rows, row_errors = normalize_and_validate(rows)
    checksum = compute_checksum(valid_rows)

    try:
        with db.transaction():
            db.begin_batch(batch_id, source_file=source_file, start_time=start)
            db.reset_staging(batch_id)
            db.load_staging(valid_rows)

            db.validate_pre_merge(batch_id, expected_rows=len(valid_rows))
            merge_counts = db.merge(batch_id)
            db.validate_post_merge(batch_id, expected_rows=len(valid_rows))

            if row_errors:
                db.record_errors(batch_id, row_errors)

            result = {
                "batch_id": batch_id,
                "status": STATUS_SUCCESS,
                "records_loaded": merge_counts.get("inserted", 0),
                "records_updated": merge_counts.get("updated", 0),
                "records_failed": len(row_errors),
                "checksum": checksum,
            }
            db.finalize_batch(
                batch_id,
                status=STATUS_SUCCESS,
                records_loaded=result["records_loaded"],
                records_updated=result["records_updated"],
                records_failed=result["records_failed"],
                checksum=checksum,
                end_time=utc_now_iso(),
            )
    except Exception as exc:  # noqa: BLE001 - surfaced after audit + alert
        # The transaction has rolled back; record the failure in its own txn.
        db.mark_failed(batch_id, source_file=source_file, error_message=str(exc))
        structured_log(
            logger,
            level=logging.ERROR,
            batch_id=batch_id,
            source_file=source_file,
            status=STATUS_FAILED,
            error=str(exc),
        )
        raise

    structured_log(
        logger,
        batch_id=batch_id,
        source_file=source_file,
        records_inserted=result["records_loaded"],
        records_updated=result["records_updated"],
        records_failed=result["records_failed"],
        status=STATUS_SUCCESS,
    )
    return result
