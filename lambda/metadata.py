"""Helpers for Phase 1 processing manifests and lineage metadata."""

from __future__ import annotations

import json
import posixpath
import uuid
from datetime import datetime, timezone
from typing import Any, Mapping


DEFAULT_METADATA_PREFIX = "metadata"
DEFAULT_PHASE1_PIPELINE_VERSION = "1.1.0"


def utc_now_iso() -> str:
    """Return the current UTC timestamp in ISO-8601 form."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def extract_event_timestamp(event: Mapping[str, Any]) -> str:
    """Return the event timestamp if present, otherwise use the current time."""
    value = event.get("time")
    if isinstance(value, str):
        try:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
            return value.replace("+00:00", "Z")
        except ValueError:
            pass
    return utc_now_iso()


def build_manifest_key(source_key: str, prefix: str = DEFAULT_METADATA_PREFIX) -> str:
    """Map a source object key to its metadata manifest key."""
    clean_prefix = prefix.strip("/")
    parts = [clean_prefix] if clean_prefix else []
    parts.append(f"{source_key}.json")
    return posixpath.join(*parts)


def build_processing_manifest(
    *,
    source_bucket: str,
    source_key: str,
    clean_bucket: str,
    clean_key: str,
    rejected_bucket: str,
    rejected_key: str,
    event_timestamp: str,
    processed_timestamp: str,
    phase1_batch_id: str,
    phase1_pipeline_version: str,
    total_records: int,
    valid_records: int,
    invalid_records: int,
    execution_duration_ms: float,
    lambda_request_id: str | None = None,
) -> dict[str, Any]:
    """Build a manifest payload describing one Phase 1 processing run."""
    manifest = {
        "raw_bucket": source_bucket,
        "raw_key": source_key,
        "clean_bucket": clean_bucket,
        "clean_key": clean_key,
        "rejected_bucket": rejected_bucket,
        "rejected_key": rejected_key,
        "source_filename": posixpath.basename(source_key),
        "event_timestamp": event_timestamp,
        "phase1_processed_timestamp": processed_timestamp,
        "phase1_batch_id": phase1_batch_id,
        "phase1_pipeline_version": phase1_pipeline_version,
        "total_records": total_records,
        "valid_records": valid_records,
        "invalid_records": invalid_records,
        "execution_duration_ms": round(execution_duration_ms, 1),
    }
    if lambda_request_id:
        manifest["lambda_request_id"] = lambda_request_id
    return manifest


def serialize_manifest(manifest: Mapping[str, Any]) -> bytes:
    """Serialize a manifest as stable JSON bytes."""
    return json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8")


def new_phase1_batch_id() -> str:
    """Generate a unique identifier for one Phase 1 processing run."""
    return str(uuid.uuid4())
