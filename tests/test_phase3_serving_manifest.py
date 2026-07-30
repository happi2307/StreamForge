from __future__ import annotations

from jobs.transform_job import build_serving_batch_manifest


def test_serving_manifest_binds_one_batch_to_its_curated_objects() -> None:
    records = [
        {"customer_id": "102", "sales": 600},
        {"customer_id": "101", "sales": 500},
    ]

    manifest = build_serving_batch_manifest(
        batch_id="phase3-batch",
        source_manifest_key="metadata/incoming/customers.csv.json",
        source_manifest={"source_filename": "customers.csv"},
        curated_bucket="curated",
        curated_object_keys=["customers/year=2026/part-000.parquet"],
        records=records,
        pipeline_version="3.0.0",
    )

    assert manifest["phase3_batch_id"] == "phase3-batch"
    assert manifest["records_written"] == 2
    assert manifest["curated_object_keys"] == ["customers/year=2026/part-000.parquet"]
    assert manifest["source_checksum"]
