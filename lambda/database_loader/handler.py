"""AWS Lambda entry point for the Phase 5 database loader.

Triggered by EventBridge when a curated batch is ready. Reads its Parquet
objects, loads them into Aurora PostgreSQL through the staging -> validate ->
merge -> audit workflow, and publishes an SNS alert if the batch fails.

Runs inside the Phase 5 VPC with reserved concurrency (serialised) so the
per-part-file events of a single batch do not race; batch-level idempotency
skips any that arrive after the batch is already SUCCESS.
"""

from __future__ import annotations

import logging
import os
import json
from pathlib import Path
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError

try:  # Support both Lambda (flat zip) and local package imports.
    import db as db_module
    from loader import compute_checksum, extract_batch_id, process_batch, read_parquet_rows, structured_log
except ImportError:  # pragma: no cover - exercised only outside the package
    import importlib

    db_module = importlib.import_module("lambda.database_loader.db")
    _loader = importlib.import_module("lambda.database_loader.loader")
    compute_checksum = _loader.compute_checksum
    extract_batch_id = _loader.extract_batch_id
    process_batch = _loader.process_batch
    read_parquet_rows = _loader.read_parquet_rows
    structured_log = _loader.structured_log


LOGGER = logging.getLogger(__name__)
if not LOGGER.handlers:
    logging.basicConfig(level=logging.INFO)
LOGGER.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

SCHEMA_FILES = ("schema.sql", "indexes.sql", "constraints.sql")


def _extract_batch_ready(event: dict[str, Any]) -> tuple[str, str, str]:
    """Return metadata bucket, manifest key, and batch ID from a Phase 3 event."""
    detail = event.get("detail")
    if not isinstance(detail, dict):
        raise ValueError("Event is missing a detail object")
    bucket = detail.get("bucket")
    manifest_key = detail.get("manifest_key")
    batch_id = detail.get("batch_id")
    if not bucket or not manifest_key or not batch_id:
        raise ValueError("Event detail is missing batch manifest information")
    return str(bucket), str(manifest_key), str(batch_id)


def _read_batch_manifest(s3_client: Any, bucket: str, key: str) -> dict[str, Any]:
    body = s3_client.get_object(Bucket=bucket, Key=key)["Body"].read()
    manifest = json.loads(body.decode("utf-8"))
    if not isinstance(manifest.get("curated_object_keys"), list):
        raise ValueError("Batch manifest is missing curated_object_keys")
    return manifest


def _read_schema_scripts() -> list[str]:
    """Load the idempotent DDL packaged beside the Lambda handler."""
    directory = Path(__file__).resolve().parent / "database"
    if not directory.is_dir():  # Local unit tests import source, not the zip.
        directory = Path(__file__).resolve().parents[2] / "database"
    return [(directory / name).read_text(encoding="utf-8") for name in SCHEMA_FILES]


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
    """Load one completed Phase 3 curated batch into the serving database."""
    secrets_client = boto3.client("secretsmanager")
    sns_client = boto3.client("sns")
    topic_arn = os.environ.get("SNS_TOPIC", "")

    if event.get("action") == "bootstrap":
        try:
            database = db_module.Database(db_module.get_connection(secrets_client))
            database.apply_schema(_read_schema_scripts())
            structured_log(LOGGER, status="BOOTSTRAPPED", scripts=len(SCHEMA_FILES))
            return {"status": "BOOTSTRAPPED", "scripts_applied": len(SCHEMA_FILES)}
        except Exception as exc:
            _publish_failure(sns_client, topic_arn, f"Schema bootstrap failed: {exc}")
            LOGGER.exception("Failed to bootstrap the serving schema")
            raise

    try:
        s3_client = boto3.client("s3")
        metadata_bucket, manifest_key, expected_batch_id = _extract_batch_ready(event)
        manifest = _read_batch_manifest(s3_client, metadata_bucket, manifest_key)
        if manifest.get("phase3_batch_id") != expected_batch_id:
            raise ValueError("Event batch_id does not match the batch manifest")
        source_file = str(manifest.get("source_filename") or manifest_key)
        curated_bucket = str(manifest.get("curated_bucket") or "")
        if not curated_bucket:
            raise ValueError("Batch manifest is missing curated_bucket")

        rows: list[dict[str, Any]] = []
        for key in manifest["curated_object_keys"]:
            body = s3_client.get_object(Bucket=curated_bucket, Key=key)["Body"].read()
            rows.extend(read_parquet_rows(body))
        if not rows:
            structured_log(
                LOGGER, source_file=source_file, status="EMPTY",
                message="curated object contained no rows",
            )
            return {"status": "EMPTY", "records_loaded": 0}
        if extract_batch_id(rows) != expected_batch_id:
            raise ValueError("Curated objects do not match the event batch_id")
        if manifest.get("source_checksum") != compute_checksum(rows):
            raise ValueError("Curated batch checksum does not match the batch manifest")

        connection = db_module.get_connection(secrets_client)
        database = db_module.Database(connection)

        try:
            return process_batch(database, rows, source_file=source_file, logger=LOGGER)
        except Exception as exc:
            _publish_failure(
                sns_client,
                topic_arn,
                f"Batch load failed for {expected_batch_id}: {exc}",
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
