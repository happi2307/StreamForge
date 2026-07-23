"""Authenticated API handlers for the StreamForge web console."""

from __future__ import annotations

import json
import logging
import os
import re
import uuid
from typing import Any

import boto3
from botocore.exceptions import ClientError
from botocore.config import Config


MAX_UPLOAD_BYTES = 10 * 1024 * 1024
UPLOAD_EXPIRY_SECONDS = 900
DOWNLOAD_EXPIRY_SECONDS = 900
LOGGER = logging.getLogger(__name__)


def _response(status_code: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }


def _claims(event: dict[str, Any]) -> dict[str, Any]:
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]
    except KeyError as exc:
        raise ValueError("Authenticated user claims are required") from exc


def _user_prefix(event: dict[str, Any]) -> str:
    subject = str(_claims(event).get("sub", "")).strip()
    if not subject:
        raise ValueError("Authenticated user subject is required")
    return f"uploads/{subject}/"


def _sanitize_filename(filename: Any) -> str:
    name = str(filename or "").strip()
    if not name.lower().endswith(".csv"):
        raise ValueError("Only .csv uploads are supported")
    sanitized = re.sub(r"[^A-Za-z0-9._-]", "_", name.rsplit("/", 1)[-1])
    if not sanitized or sanitized == ".csv":
        raise ValueError("A valid CSV filename is required")
    return sanitized


def _parse_body(event: dict[str, Any]) -> dict[str, Any]:
    try:
        return json.loads(event.get("body") or "{}")
    except json.JSONDecodeError as exc:
        raise ValueError("Request body must be valid JSON") from exc


def _env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Required environment variable {name} is not set")
    return value


def create_upload(event: dict[str, Any], s3_client: Any) -> dict[str, Any]:
    body = _parse_body(event)
    filename = _sanitize_filename(body.get("filename"))
    size = int(body.get("size", 0))
    if size <= 0 or size > MAX_UPLOAD_BYTES:
        raise ValueError(f"Upload size must be between 1 and {MAX_UPLOAD_BYTES} bytes")

    raw_bucket = _env("RAW_BUCKET")
    key = f"{_user_prefix(event)}{uuid.uuid4()}-{filename}"
    upload_url = s3_client.generate_presigned_url(
        "put_object",
        Params={"Bucket": raw_bucket, "Key": key, "ContentType": "text/csv"},
        ExpiresIn=UPLOAD_EXPIRY_SECONDS,
        HttpMethod="PUT",
    )
    return _response(
        201,
        {
            "upload_url": upload_url,
            "key": key,
            "expires_in_seconds": UPLOAD_EXPIRY_SECONDS,
        },
    )


def get_status(event: dict[str, Any], s3_client: Any) -> dict[str, Any]:
    key = str((event.get("queryStringParameters") or {}).get("key", ""))
    if not key.startswith(_user_prefix(event)):
        return _response(403, {"message": "Upload is not owned by this user"})

    metadata_bucket = _env("METADATA_BUCKET")
    metadata_prefix = _env("METADATA_PREFIX").strip("/")
    manifest_key = f"{metadata_prefix}/{key}.json"
    try:
        manifest = json.loads(
            s3_client.get_object(Bucket=metadata_bucket, Key=manifest_key)["Body"]
            .read()
            .decode("utf-8")
        )
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in {"NoSuchKey", "404"}:
            return _response(200, {"status": "PROCESSING", "key": key})
        raise

    links = {}
    for name, bucket_field, key_field in (
        ("clean", "clean_bucket", "clean_key"),
        ("rejected", "rejected_bucket", "rejected_key"),
    ):
        output_key = str(manifest.get(key_field, ""))
        if output_key.startswith(_user_prefix(event)):
            links[name] = s3_client.generate_presigned_url(
                "get_object",
                Params={"Bucket": manifest[bucket_field], "Key": output_key},
                ExpiresIn=DOWNLOAD_EXPIRY_SECONDS,
            )

    return _response(
        200,
        {
            "status": "COMPLETE",
            "key": key,
            "batch_id": manifest["phase1_batch_id"],
            "source_filename": manifest["source_filename"],
            "processed_timestamp": manifest["phase1_processed_timestamp"],
            "total_records": manifest["total_records"],
            "valid_records": manifest["valid_records"],
            "invalid_records": manifest["invalid_records"],
            "downloads": links,
        },
    )


def lambda_handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    """Route authenticated HTTP API requests."""
    # SSE-KMS uploads require SigV4 presigned URLs.  us-east-1 can otherwise
    # default to the legacy S3 signature version for generated upload links.
    s3_client = boto3.client("s3", config=Config(signature_version="s3v4"))
    try:
        route = event.get("routeKey")
        if route == "POST /uploads":
            return create_upload(event, s3_client)
        if route == "GET /status":
            return get_status(event, s3_client)
        return _response(404, {"message": "Route not found"})
    except ValueError as exc:
        return _response(400, {"message": str(exc)})
    except ClientError as exc:
        LOGGER.exception(
            "Dashboard storage request failed: %s",
            exc.response.get("Error", {}).get("Code", "unknown"),
        )
        return _response(502, {"message": "Storage service request failed"})
