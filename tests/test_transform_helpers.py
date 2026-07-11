"""Unit tests for reusable Phase 3 transformation helpers."""

from __future__ import annotations

from jobs import transform_helpers as helpers


MANIFEST = {
    "raw_key": "incoming/customers.csv",
    "clean_key": "customers.csv",
    "source_filename": "customers.csv",
    "event_timestamp": "2026-07-11T10:15:00Z",
    "phase1_batch_id": "phase1-batch",
}


def test_normalize_name_title_cases_words() -> None:
    assert helpers.normalize_name("  john   DOE ") == "John Doe"


def test_normalize_email_lowercases_value() -> None:
    assert helpers.normalize_email(" TEST@Example.COM ") == "test@example.com"


def test_standardize_date_supports_us_short_format() -> None:
    assert helpers.standardize_date("07/10/26") == "2026-07-10"


def test_categorize_sales_ranges() -> None:
    assert helpers.categorize_sales(499) == "Low"
    assert helpers.categorize_sales(500) == "Medium"
    assert helpers.categorize_sales(1000) == "High"


def test_transform_record_adds_metadata_and_partitions() -> None:
    curated, quarantined = helpers.transform_record(
        {"customer_id": "101", "name": "john DOE", "email": " JOHN@EXAMPLE.COM ", "sales": "500"},
        MANIFEST,
        pipeline_version="3.0.0",
        processed_timestamp="2026-07-11T10:20:00Z",
        phase3_batch_id="phase3-batch",
    )

    assert quarantined is None
    assert curated is not None
    assert curated["name"] == "John Doe"
    assert curated["email"] == "john@example.com"
    assert curated["sales"] == 500
    assert curated["sales_category"] == "Medium"
    assert curated["phase1_batch_id"] == "phase1-batch"
    assert curated["phase3_batch_id"] == "phase3-batch"
    assert curated["year"] == "2026"
    assert curated["month"] == "07"
    assert curated["day"] == "11"


def test_transform_record_quarantines_invalid_sales() -> None:
    curated, quarantined = helpers.transform_record(
        {"customer_id": "101", "name": "John", "email": "john@example.com", "sales": "bad"},
        MANIFEST,
        pipeline_version="3.0.0",
        processed_timestamp="2026-07-11T10:20:00Z",
        phase3_batch_id="phase3-batch",
    )

    assert curated is None
    assert quarantined is not None
    assert quarantined["error_reason"] == "invalid_sales"
    assert quarantined["reason"] == "invalid_sales"
    assert quarantined["source_filename"] == "customers.csv"


def test_transform_record_quarantines_schema_mismatch_for_missing_date_column() -> None:
    curated, quarantined = helpers.transform_record(
        {"customer_id": "101", "name": "John", "email": "john@example.com", "sales": "700"},
        MANIFEST,
        pipeline_version="3.0.0",
        date_column="order_date",
        processed_timestamp="2026-07-11T10:20:00Z",
        phase3_batch_id="phase3-batch",
    )

    assert curated is None
    assert quarantined is not None
    assert quarantined["error_reason"] == "schema_mismatch"


def test_invalid_threshold_helper() -> None:
    assert not helpers.should_fail_invalid_threshold(1, 20, 10)
    assert helpers.should_fail_invalid_threshold(3, 20, 10)
