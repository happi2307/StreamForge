"""Database access for the Phase 5 loader.

Encapsulates Secrets Manager credential retrieval, a reusable pg8000 connection,
and the SQL that implements the staging -> validate -> merge -> audit workflow.

pg8000 is a pure-Python PostgreSQL driver (no native build), which packages into
a Lambda zip cleanly. It is imported lazily inside :func:`connect` so this module
can be imported for unit testing (e.g. :func:`get_secret`) without the driver
installed.
"""

from __future__ import annotations

import contextlib
import json
import os
from typing import Any, Iterator, Mapping, Sequence


# Reused across warm invocations to amortise connection setup.
_CONNECTION: Any = None


def get_secret(secret_name: str, client: Any) -> dict[str, Any]:
    """Return the parsed JSON credentials stored in Secrets Manager.

    Works with the RDS-managed master user secret shape
    (``{"username": ..., "password": ...}``).
    """
    response = client.get_secret_value(SecretId=secret_name)
    secret_string = response.get("SecretString")
    if not secret_string:
        raise ValueError(f"Secret {secret_name} has no SecretString")
    return json.loads(secret_string)


def connect(
    credentials: Mapping[str, Any],
    *,
    host: str,
    database: str,
    port: int = 5432,
) -> Any:
    """Open a new pg8000 connection using SSL (required by Aurora)."""
    import pg8000.native  # local import: runtime-only dependency

    return pg8000.native.Connection(
        user=credentials["username"],
        password=credentials["password"],
        host=host,
        port=port,
        database=database,
        ssl_context=True,
    )


def get_connection(secrets_client: Any) -> Any:
    """Return a cached pg8000 connection, creating one on first use.

    Configuration comes from the loader's environment variables. A dropped
    connection is transparently replaced on the next call.
    """
    global _CONNECTION
    if _CONNECTION is not None:
        return _CONNECTION

    secret_name = os.environ["DB_SECRET_NAME"]
    host = os.environ["DB_HOST"]
    database = os.environ.get("DB_NAME", "streamforge")
    port = int(os.environ.get("DB_PORT", "5432"))

    credentials = get_secret(secret_name, secrets_client)
    _CONNECTION = connect(credentials, host=host, database=database, port=port)
    return _CONNECTION


def reset_connection() -> None:
    """Drop the cached connection (call after a connection-level error)."""
    global _CONNECTION
    with contextlib.suppress(Exception):
        if _CONNECTION is not None:
            _CONNECTION.close()
    _CONNECTION = None


class Database:
    """pg8000-backed implementation of the loader's data operations.

    Uses ``pg8000.native.Connection`` whose ``run`` executes a statement with
    ``:name`` parameters and returns rows as lists.
    """

    def __init__(self, connection: Any) -> None:
        self._conn = connection

    # -- transaction management ---------------------------------------------
    @contextlib.contextmanager
    def transaction(self) -> Iterator[None]:
        """Run a block inside one transaction; commit on success, else rollback."""
        self._conn.run("BEGIN")
        try:
            yield
        except Exception:
            with contextlib.suppress(Exception):
                self._conn.run("ROLLBACK")
            raise
        else:
            self._conn.run("COMMIT")

    # -- idempotency --------------------------------------------------------
    def get_batch_status(self, batch_id: str) -> str | None:
        rows = self._conn.run(
            "SELECT status FROM audit.batch_metadata WHERE batch_id = :b",
            b=batch_id,
        )
        return rows[0][0] if rows else None

    def begin_batch(self, batch_id: str, *, source_file: str, start_time: str) -> None:
        self._conn.run(
            """
            INSERT INTO audit.batch_metadata (batch_id, source_file, start_time, status)
            VALUES (:b, :f, :t::timestamptz, 'IN_PROGRESS')
            ON CONFLICT (batch_id) DO UPDATE
            SET source_file = EXCLUDED.source_file,
                start_time  = EXCLUDED.start_time,
                status      = 'IN_PROGRESS'
            """,
            b=batch_id,
            f=source_file,
            t=start_time,
        )

    # -- staging ------------------------------------------------------------
    def reset_staging(self, batch_id: str) -> None:
        self._conn.run(
            "DELETE FROM staging.customers WHERE batch_id = :b", b=batch_id
        )

    def load_staging(self, rows: Sequence[Mapping[str, Any]]) -> int:
        for row in rows:
            self._conn.run(
                """
                INSERT INTO staging.customers (
                    customer_id, name, email, sales, sales_category,
                    ingestion_timestamp, processed_timestamp, phase1_batch_id,
                    batch_id, source_filename, source_raw_key, source_clean_key,
                    pipeline_version
                ) VALUES (
                    :customer_id, :name, :email, :sales, :sales_category,
                    :ingestion_timestamp, :processed_timestamp, :phase1_batch_id,
                    :batch_id, :source_filename, :source_raw_key, :source_clean_key,
                    :pipeline_version
                )
                """,
                **{key: row.get(key) for key in _STAGING_KEYS},
            )
        return len(rows)

    # -- validation ---------------------------------------------------------
    def validate_pre_merge(self, batch_id: str, *, expected_rows: int) -> None:
        staged = self._conn.run(
            "SELECT count(*) FROM staging.customers WHERE batch_id = :b", b=batch_id
        )[0][0]
        if staged != expected_rows:
            raise ValueError(
                f"pre-merge staged rows {staged} != expected {expected_rows}"
            )

        bad = self._conn.run(
            """
            SELECT
                count(*) FILTER (WHERE customer_id IS NULL OR customer_id = ''),
                count(*) FILTER (WHERE sales IS NULL OR sales < 0)
            FROM staging.customers WHERE batch_id = :b
            """,
            b=batch_id,
        )[0]
        if bad[0] or bad[1]:
            raise ValueError(
                f"pre-merge validation failed: missing_key={bad[0]} bad_sales={bad[1]}"
            )

        dupes = self._conn.run(
            """
            SELECT count(*) FROM (
                SELECT customer_id FROM staging.customers
                WHERE batch_id = :b GROUP BY customer_id HAVING count(*) > 1
            ) d
            """,
            b=batch_id,
        )[0][0]
        if dupes:
            raise ValueError(f"pre-merge validation failed: {dupes} duplicate keys")

    def validate_post_merge(self, batch_id: str, *, expected_rows: int) -> None:
        staged_total = self._conn.run(
            "SELECT coalesce(sum(sales), 0) FROM staging.customers WHERE batch_id = :b",
            b=batch_id,
        )[0][0]
        loaded = self._conn.run(
            "SELECT count(*), coalesce(sum(sales_amount), 0) "
            "FROM analytics.sales WHERE batch_id = :b",
            b=batch_id,
        )[0]
        if loaded[0] != expected_rows:
            raise ValueError(
                f"post-merge loaded rows {loaded[0]} != expected {expected_rows}"
            )
        if loaded[1] != staged_total:
            raise ValueError(
                f"post-merge total sales {loaded[1]} != staged {staged_total}"
            )

    # -- merge --------------------------------------------------------------
    def merge(self, batch_id: str) -> dict[str, int]:
        """Upsert staging into production; return inserted/updated counts."""
        updated = self._conn.run(
            """
            SELECT count(*)
            FROM analytics.customers c
            JOIN staging.customers s ON c.customer_id = s.customer_id
            WHERE s.batch_id = :b
            """,
            b=batch_id,
        )[0][0]

        self._conn.run(_UPSERT_CUSTOMERS_SQL, b=batch_id)
        self._conn.run(_UPSERT_SALES_SQL, b=batch_id)

        total = self._conn.run(
            "SELECT count(DISTINCT customer_id) FROM staging.customers "
            "WHERE batch_id = :b",
            b=batch_id,
        )[0][0]
        return {"inserted": total - updated, "updated": updated}

    # -- audit --------------------------------------------------------------
    def record_errors(self, batch_id: str, errors: Sequence[Mapping[str, str]]) -> None:
        for error in errors:
            self._conn.run(
                """
                INSERT INTO audit.load_errors
                    (batch_id, customer_id, error_message, source_file)
                VALUES (:b, :c, :m, :f)
                """,
                b=batch_id,
                c=error.get("customer_id") or None,
                m=error["error_message"],
                f=error.get("source_file"),
            )

    def finalize_batch(
        self,
        batch_id: str,
        *,
        status: str,
        records_loaded: int,
        records_updated: int,
        records_failed: int,
        checksum: str,
        end_time: str,
    ) -> None:
        self._conn.run(
            """
            UPDATE audit.batch_metadata
            SET status              = :status,
                records_loaded      = :loaded,
                records_updated     = :updated,
                records_failed      = :failed,
                checksum            = :checksum,
                end_time            = :end::timestamptz,
                processed_timestamp = :end::timestamptz,
                duration_ms         = round(
                    extract(epoch FROM (:end::timestamptz - start_time)) * 1000
                )
            WHERE batch_id = :b
            """,
            status=status,
            loaded=records_loaded,
            updated=records_updated,
            failed=records_failed,
            checksum=checksum,
            end=end_time,
            b=batch_id,
        )

    def mark_failed(self, batch_id: str, *, source_file: str, error_message: str) -> None:
        """Record a batch failure in its own committed transaction."""
        with self.transaction():
            self._conn.run(
                """
                INSERT INTO audit.batch_metadata (batch_id, source_file, status, end_time)
                VALUES (:b, :f, 'FAILED', now())
                ON CONFLICT (batch_id) DO UPDATE
                SET status = 'FAILED', end_time = now()
                """,
                b=batch_id,
                f=source_file,
            )
            self._conn.run(
                """
                INSERT INTO audit.load_errors
                    (batch_id, customer_id, error_message, source_file)
                VALUES (:b, NULL, :m, :f)
                """,
                b=batch_id,
                m=error_message,
                f=source_file,
            )


_STAGING_KEYS = (
    "customer_id",
    "name",
    "email",
    "sales",
    "sales_category",
    "ingestion_timestamp",
    "processed_timestamp",
    "phase1_batch_id",
    "batch_id",
    "source_filename",
    "source_raw_key",
    "source_clean_key",
    "pipeline_version",
)

_UPSERT_CUSTOMERS_SQL = """
INSERT INTO analytics.customers AS c (
    customer_id, name, email, sales, sales_category,
    batch_id, processed_timestamp, source_filename, pipeline_version, updated_at
)
SELECT s.customer_id, s.name, s.email, s.sales, s.sales_category,
       s.batch_id, nullif(s.processed_timestamp, '')::timestamptz,
       s.source_filename, s.pipeline_version, now()
FROM staging.customers s
WHERE s.batch_id = :b
ON CONFLICT (customer_id) DO UPDATE
SET name = EXCLUDED.name, email = EXCLUDED.email, sales = EXCLUDED.sales,
    sales_category = EXCLUDED.sales_category, batch_id = EXCLUDED.batch_id,
    processed_timestamp = EXCLUDED.processed_timestamp,
    source_filename = EXCLUDED.source_filename,
    pipeline_version = EXCLUDED.pipeline_version, updated_at = now()
"""

_UPSERT_SALES_SQL = """
INSERT INTO analytics.sales AS f (
    customer_id, sales_amount, sales_category,
    batch_id, source_filename, ingestion_date, processed_timestamp
)
SELECT s.customer_id, s.sales, s.sales_category, s.batch_id, s.source_filename,
       nullif(s.ingestion_timestamp, '')::timestamptz::date,
       nullif(s.processed_timestamp, '')::timestamptz
FROM staging.customers s
WHERE s.batch_id = :b
ON CONFLICT (customer_id, batch_id) DO UPDATE
SET sales_amount = EXCLUDED.sales_amount, sales_category = EXCLUDED.sales_category,
    source_filename = EXCLUDED.source_filename, ingestion_date = EXCLUDED.ingestion_date,
    processed_timestamp = EXCLUDED.processed_timestamp, loaded_at = now()
"""
