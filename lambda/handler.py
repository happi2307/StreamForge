"""AWS Lambda entry point for customer CSV processing.

The function is triggered by EventBridge when an object is created in the raw
S3 bucket. It downloads the CSV, validates and cleans the rows, and writes the
clean and rejected rows to their respective buckets.
"""

from __future__ import annotations

import io
import logging
import os
import time
from typing import Any

import boto3
import pandas as pd
from botocore.exceptions import BotoCoreError, ClientError

try:  # Support both Lambda (flat) and local package imports.
    from metadata import (
        DEFAULT_METADATA_PREFIX,
        DEFAULT_PHASE1_PIPELINE_VERSION,
        build_manifest_key,
        build_processing_manifest,
        extract_event_timestamp,
        new_phase1_batch_id,
        serialize_manifest,
        utc_now_iso,
    )
    from validator import validate_and_split
except ImportError:  # pragma: no cover - exercised only outside the package
    # "lambda" is a reserved keyword, so import the module dynamically.
    import importlib

    metadata = importlib.import_module("lambda.metadata")
    DEFAULT_METADATA_PREFIX = metadata.DEFAULT_METADATA_PREFIX
    DEFAULT_PHASE1_PIPELINE_VERSION = metadata.DEFAULT_PHASE1_PIPELINE_VERSION
    build_manifest_key = metadata.build_manifest_key
    build_processing_manifest = metadata.build_processing_manifest
    extract_event_timestamp = metadata.extract_event_timestamp
    new_phase1_batch_id = metadata.new_phase1_batch_id
    serialize_manifest = metadata.serialize_manifest
    utc_now_iso = metadata.utc_now_iso
    validate_and_split = importlib.import_module("lambda.validator").validate_and_split


LOGGER = logging.getLogger(__name__)
if not LOGGER.handlers:
    logging.basicConfig(level=logging.INFO)
LOGGER.setLevel(logging.INFO)

CLEAN_BUCKET_ENV = "CLEAN_BUCKET"
REJECTED_BUCKET_ENV = "REJECTED_BUCKET"
METADATA_BUCKET_ENV = "METADATA_BUCKET"
METADATA_PREFIX_ENV = "METADATA_PREFIX"
PHASE1_PIPELINE_VERSION_ENV = "PHASE1_PIPELINE_VERSION"


def _extract_source(event: dict[str, Any]) -> tuple[str, str]:
    """Return the (bucket, key) for the object described by *event*.

    Supports the EventBridge S3 "Object Created" detail shape.
    """
    detail = event.get("detail")
    if not isinstance(detail, dict):
        raise ValueError("Event is missing an S3 'detail' object")

    bucket = (detail.get("bucket") or {}).get("name")
    key = (detail.get("object") or {}).get("key")
    if not bucket or not key:
        raise ValueError("Event detail is missing bucket name or object key")
    return str(bucket), str(key)


def _get_env_bucket(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Required environment variable {name} is not set")
    return value


def _get_optional_env(name: str, default: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        return default
    return value


def _write_csv(client: Any, bucket: str, key: str, frame: pd.DataFrame) -> None:
    """Upload *frame* as a CSV object to ``s3://bucket/key``."""
    buffer = io.StringIO()
    frame.to_csv(buffer, index=False)
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=buffer.getvalue().encode("utf-8"),
        ContentType="text/csv",
    )


def _write_manifest(client: Any, bucket: str, key: str, manifest: dict[str, Any]) -> None:
    """Upload a processing manifest as a JSON object to ``s3://bucket/key``."""
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=serialize_manifest(manifest),
        ContentType="application/json",
    )


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, int]:
    """Handle an S3 object-created event delivered by EventBridge."""
    start = time.perf_counter()
    client = boto3.client("s3")
    phase1_batch_id = new_phase1_batch_id()

    try:
        source_bucket, key = _extract_source(event)
        clean_bucket = _get_env_bucket(CLEAN_BUCKET_ENV)
        rejected_bucket = _get_env_bucket(REJECTED_BUCKET_ENV)
        metadata_bucket = _get_optional_env(METADATA_BUCKET_ENV, clean_bucket)
        metadata_prefix = _get_optional_env(METADATA_PREFIX_ENV, DEFAULT_METADATA_PREFIX)
        phase1_pipeline_version = _get_optional_env(
            PHASE1_PIPELINE_VERSION_ENV, DEFAULT_PHASE1_PIPELINE_VERSION
        )
        event_timestamp = extract_event_timestamp(event)

        LOGGER.info("Processing %s", key)

        response = client.get_object(Bucket=source_bucket, Key=key)
        body = response["Body"].read()
        if not body.strip():
            raise ValueError(f"Object {key} is empty")

        try:
            data = pd.read_csv(io.BytesIO(body))
        except pd.errors.EmptyDataError as exc:
            raise ValueError(f"Object {key} contains no parseable CSV data") from exc
        except pd.errors.ParserError as exc:
            raise ValueError(f"Object {key} is not valid CSV") from exc

        clean, rejected = validate_and_split(data)

        _write_csv(client, clean_bucket, key, clean)
        _write_csv(client, rejected_bucket, key, rejected)

        stats = {
            "total_records": int(len(data)),
            "valid_records": int(len(clean)),
            "invalid_records": int(len(rejected)),
        }

        duration_ms = (time.perf_counter() - start) * 1000
        processed_timestamp = utc_now_iso()
        manifest = build_processing_manifest(
            source_bucket=source_bucket,
            source_key=key,
            clean_bucket=clean_bucket,
            clean_key=key,
            rejected_bucket=rejected_bucket,
            rejected_key=key,
            event_timestamp=event_timestamp,
            processed_timestamp=processed_timestamp,
            phase1_batch_id=phase1_batch_id,
            phase1_pipeline_version=phase1_pipeline_version,
            total_records=stats["total_records"],
            valid_records=stats["valid_records"],
            invalid_records=stats["invalid_records"],
            execution_duration_ms=duration_ms,
            lambda_request_id=getattr(context, "aws_request_id", None),
        )
        manifest_key = build_manifest_key(key, metadata_prefix)
        _write_manifest(client, metadata_bucket, manifest_key, manifest)

        LOGGER.info("Total Records: %d", stats["total_records"])
        LOGGER.info("Valid Records: %d", stats["valid_records"])
        LOGGER.info("Invalid Records: %d", stats["invalid_records"])
        LOGGER.info("Metadata Manifest: s3://%s/%s", metadata_bucket, manifest_key)
        LOGGER.info("Execution duration: %.1f ms", duration_ms)
        return stats

    except (ClientError, BotoCoreError):
        LOGGER.exception("AWS SDK error while processing event")
        raise
    except Exception:
        LOGGER.exception("Failed to process event")
        raise
