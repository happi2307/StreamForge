"""AWS Lambda entry point for the Phase 5 database loader.

Triggered by EventBridge when a curated Parquet object is created. Reads the
object, loads it into Aurora PostgreSQL through the staging -> validate -> merge
-> audit workflow, and publishes an SNS alert if the batch fails.

Runs inside the Phase 5 VPC with reserved concurrency (serialised) so the
per-part-file events of a single batch do not race; batch-level idempotency
skips any that arrive after the batch is already SUCCESS.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError

try:  # Support both Lambda (flat zip) and local package imports.
    import db as db_module
    from loader import process_batch, read_parquet_rows, structured_log
except ImportError:  # pragma: no cover - exercised only outside the package
    import importlib

    db_module = importlib.import_module("lambda.database_loader.db")
    _loader = importlib.import_module("lambda.database_loader.loader")
    process_batch = _loader.process_batch
    read_parquet_rows = _loader.read_parquet_rows
    structured_log = _loader.structured_log


LOGGER = logging.getLogger(__name__)
if not LOGGER.handlers:
    logging.basicConfig(level=logging.INFO)
LOGGER.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())


def _extract_source(event: dict[str, Any]) -> tuple[str, str]:
    """Return the (bucket, key) of the curated object described by *event*."""
    detail = event.get("detail")
    if not isinstance(detail, dict):
        raise ValueError("Event is missing an S3 'detail' object")
    bucket = (detail.get("bucket") or {}).get("name")
    key = (detail.get("object") or {}).get("key")
    if not bucket or not key:
        raise ValueError("Event detail is missing bucket name or object key")
    return str(bucket), str(key)


def _source_filename(key: str) -> str:
    return key.rsplit("/", 1)[-1]


def _publish_failure(sns_client: Any, topic_arn: str, message: str) -> None:
    """Best-effort SNS alert; never masks the original loader error."""
    if not topic_arn:
        return
    try:
        sns_client.publish(
            TopicArn=topic_arn,
            Subject="StreamForge database loader failure",
            Message=message,
        )
    except (ClientError, BotoCoreError):
        LOGGER.exception("Failed to publish loader failure alert to SNS")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Load one curated Parquet object into the serving database."""
    s3_client = boto3.client("s3")
    secrets_client = boto3.client("secretsmanager")
    sns_client = boto3.client("sns")
    topic_arn = os.environ.get("SNS_TOPIC", "")

    try:
        bucket, key = _extract_source(event)
        source_file = _source_filename(key)
        LOGGER.info("Loading curated object s3://%s/%s", bucket, key)

        body = s3_client.get_object(Bucket=bucket, Key=key)["Body"].read()
        rows = read_parquet_rows(body)
        if not rows:
            structured_log(
                LOGGER, source_file=source_file, status="EMPTY",
                message="curated object contained no rows",
            )
            return {"status": "EMPTY", "records_loaded": 0}

        connection = db_module.get_connection(secrets_client)
        database = db_module.Database(connection)

        try:
            return process_batch(database, rows, source_file=source_file, logger=LOGGER)
        except Exception as exc:
            _publish_failure(
                sns_client,
                topic_arn,
                f"Batch load failed for s3://{bucket}/{key}: {exc}",
            )
            # A connection-level failure invalidates the cached connection.
            if isinstance(exc, (ClientError, BotoCoreError, OSError)):
                db_module.reset_connection()
            raise

    except (ClientError, BotoCoreError):
        LOGGER.exception("AWS SDK error while loading curated object")
        raise
    except Exception:
        LOGGER.exception("Failed to load curated object")
        raise
