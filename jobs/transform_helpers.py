"""Pure helpers for Phase 3 curated transformations."""

from __future__ import annotations

import string
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Mapping


DEFAULT_DATE_FORMATS = ("%Y-%m-%d", "%m/%d/%y", "%m/%d/%Y", "%Y/%m/%d")


@dataclass(frozen=True)
class Phase3Metadata:
    """Lineage metadata attached to each curated record."""

    ingestion_timestamp: str
    processed_timestamp: str
    phase1_batch_id: str
    phase3_batch_id: str
    source_filename: str
    source_raw_key: str
    source_clean_key: str
    pipeline_version: str


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def normalize_name(value: Any) -> str | None:
    """Return a title-cased customer name."""
    if value is None:
        return None
    text = " ".join(str(value).strip().split())
    if not text:
        return None
    return string.capwords(text.lower())


def normalize_email(value: Any) -> str | None:
    """Return a lowercase email address."""
    if value is None:
        return None
    text = str(value).strip().lower()
    return text or None


def standardize_date(
    value: Any, formats: tuple[str, ...] = DEFAULT_DATE_FORMATS
) -> str | None:
    """Parse a supported date representation into ISO-8601 date form."""
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None

    for fmt in formats:
        try:
            return datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            continue
    raise ValueError(f"Unsupported date value: {text}")


def parse_sales(value: Any) -> int:
    """Convert sales to an integer value."""
    if value is None:
        raise ValueError("sales is missing")
    text = str(value).strip()
    if not text:
        raise ValueError("sales is empty")
    parsed = float(text)
    if not parsed.is_integer():
        raise ValueError("sales must be a whole number")
    return int(parsed)


def categorize_sales(sales: int) -> str:
    """Return a categorical label for a sales value."""
    if sales < 500:
        return "Low"
    if sales < 1000:
        return "Medium"
    return "High"


def derive_partition_parts(ingestion_timestamp: str) -> dict[str, str]:
    """Derive year/month/day partition strings from an ISO-8601 timestamp."""
    parsed = datetime.fromisoformat(ingestion_timestamp.replace("Z", "+00:00"))
    return {
        "year": parsed.strftime("%Y"),
        "month": parsed.strftime("%m"),
        "day": parsed.strftime("%d"),
    }


def should_fail_invalid_threshold(
    invalid_count: int, total_count: int, max_invalid_percent: float
) -> bool:
    """Return whether the invalid-row ratio exceeds the configured threshold."""
    if total_count <= 0:
        return False
    return (invalid_count / total_count) * 100 > max_invalid_percent


def build_phase3_metadata(
    manifest: Mapping[str, Any],
    *,
    pipeline_version: str,
    processed_timestamp: str | None = None,
    phase3_batch_id: str | None = None,
) -> Phase3Metadata:
    """Create a stable metadata payload from a Phase 1 manifest."""
    return Phase3Metadata(
        ingestion_timestamp=str(manifest["event_timestamp"]),
        processed_timestamp=processed_timestamp or _utc_now_iso(),
        phase1_batch_id=str(manifest["phase1_batch_id"]),
        phase3_batch_id=phase3_batch_id or str(uuid.uuid4()),
        source_filename=str(manifest["source_filename"]),
        source_raw_key=str(manifest["raw_key"]),
        source_clean_key=str(manifest["clean_key"]),
        pipeline_version=pipeline_version,
    )


def build_quarantine_record(
    row: Mapping[str, Any], *, error_reason: str, metadata: Phase3Metadata
) -> dict[str, Any]:
    """Build a quarantine payload for one malformed transformed row."""
    partitions = derive_partition_parts(metadata.ingestion_timestamp)
    return {
        "raw_record": dict(row),
        "error_reason": error_reason,
        "reason": error_reason,
        "source_filename": metadata.source_filename,
        "ingestion_timestamp": metadata.ingestion_timestamp,
        "processed_timestamp": metadata.processed_timestamp,
        "phase1_batch_id": metadata.phase1_batch_id,
        "phase3_batch_id": metadata.phase3_batch_id,
        "pipeline_version": metadata.pipeline_version,
        **partitions,
    }


def transform_record(
    row: Mapping[str, Any],
    manifest: Mapping[str, Any],
    *,
    pipeline_version: str,
    date_column: str | None = None,
    processed_timestamp: str | None = None,
    phase3_batch_id: str | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """Transform one clean row into its curated form or quarantine payload."""
    metadata = build_phase3_metadata(
        manifest,
        pipeline_version=pipeline_version,
        processed_timestamp=processed_timestamp,
        phase3_batch_id=phase3_batch_id,
    )

    try:
        curated = {
            key: (" ".join(str(value).split()) if isinstance(value, str) else value)
            for key, value in row.items()
        }
        curated["name"] = normalize_name(curated.get("name"))
        curated["email"] = normalize_email(curated.get("email"))
        curated["sales"] = parse_sales(curated.get("sales"))
        curated["sales_category"] = categorize_sales(curated["sales"])

        if date_column:
            if date_column not in curated:
                raise KeyError("schema_mismatch")
            curated[date_column] = standardize_date(curated.get(date_column))

        curated.update(
            {
                "ingestion_timestamp": metadata.ingestion_timestamp,
                "processed_timestamp": metadata.processed_timestamp,
                "phase1_batch_id": metadata.phase1_batch_id,
                "phase3_batch_id": metadata.phase3_batch_id,
                "source_filename": metadata.source_filename,
                "source_raw_key": metadata.source_raw_key,
                "source_clean_key": metadata.source_clean_key,
                "pipeline_version": metadata.pipeline_version,
            }
        )
        curated.update(derive_partition_parts(metadata.ingestion_timestamp))
        return curated, None

    except KeyError:
        return None, build_quarantine_record(
            row, error_reason="schema_mismatch", metadata=metadata
        )
    except ValueError as exc:
        reason = (
            "date_parse_error"
            if date_column and "date" in str(exc).lower()
            else "invalid_sales"
        )
        return None, build_quarantine_record(
            row, error_reason=reason, metadata=metadata
        )
