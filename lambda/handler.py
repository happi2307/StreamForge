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
    from validator import validate_and_split
except ImportError:  # pragma: no cover - exercised only outside the package
    # "lambda" is a reserved keyword, so import the module dynamically.
    import importlib

    validate_and_split = importlib.import_module("lambda.validator").validate_and_split


LOGGER = logging.getLogger(__name__)
if not LOGGER.handlers:
    logging.basicConfig(level=logging.INFO)
LOGGER.setLevel(logging.INFO)

CLEAN_BUCKET_ENV = "CLEAN_BUCKET"
REJECTED_BUCKET_ENV = "REJECTED_BUCKET"


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


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, int]:
    """Handle an S3 object-created event delivered by EventBridge."""
    start = time.perf_counter()
    client = boto3.client("s3")

    try:
        source_bucket, key = _extract_source(event)
        clean_bucket = _get_env_bucket(CLEAN_BUCKET_ENV)
        rejected_bucket = _get_env_bucket(REJECTED_BUCKET_ENV)

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
        LOGGER.info("Total Records: %d", stats["total_records"])
        LOGGER.info("Valid Records: %d", stats["valid_records"])
        LOGGER.info("Invalid Records: %d", stats["invalid_records"])
        LOGGER.info("Execution duration: %.1f ms", duration_ms)
        return stats

    except (ClientError, BotoCoreError):
        LOGGER.exception("AWS SDK error while processing event")
        raise
    except Exception:
        LOGGER.exception("Failed to process event")
        raise
