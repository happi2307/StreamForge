"""Glue-compatible Phase 3 job for curated Parquet output and quarantine handling."""

from __future__ import annotations

import argparse
import csv
import io
import json
from dataclasses import dataclass
from typing import Any

import boto3

try:
    from jobs.transform_helpers import should_fail_invalid_threshold, transform_record
except ImportError:  # pragma: no cover - used by Glue when helper module is flat
    from transform_helpers import should_fail_invalid_threshold, transform_record


@dataclass(frozen=True)
class JobConfig:
    input_bucket: str
    metadata_bucket: str
    curated_bucket: str
    quarantine_bucket: str
    input_prefix: str
    metadata_prefix: str
    curated_prefix: str
    quarantine_prefix: str
    database_name: str
    curated_table: str
    quarantine_table: str | None
    pipeline_version: str
    max_invalid_percent: float
    date_column: str | None


def _parse_args(argv: list[str] | None = None) -> JobConfig:
    parser = argparse.ArgumentParser()
    parser.add_argument("--JOB_NAME", default="")
    parser.add_argument("--INPUT_BUCKET", required=True)
    parser.add_argument("--METADATA_BUCKET", required=True)
    parser.add_argument("--CURATED_BUCKET", required=True)
    parser.add_argument("--QUARANTINE_BUCKET", required=True)
    parser.add_argument("--INPUT_PREFIX", default="")
    parser.add_argument("--METADATA_PREFIX", default="metadata")
    parser.add_argument("--CURATED_PREFIX", default="customers")
    parser.add_argument("--QUARANTINE_PREFIX", default="")
    parser.add_argument("--DATABASE_NAME", default="streamforge_clean_db")
    parser.add_argument("--CURATED_TABLE", default="customers_curated")
    parser.add_argument("--QUARANTINE_TABLE", default="")
    parser.add_argument("--PIPELINE_VERSION", default="3.0.0")
    parser.add_argument("--MAX_INVALID_PERCENT", type=float, default=10.0)
    parser.add_argument("--DATE_COLUMN", default="")
    args, _unknown = parser.parse_known_args(argv)
    return JobConfig(
        input_bucket=args.INPUT_BUCKET,
        metadata_bucket=args.METADATA_BUCKET,
        curated_bucket=args.CURATED_BUCKET,
        quarantine_bucket=args.QUARANTINE_BUCKET,
        input_prefix=args.INPUT_PREFIX.strip("/"),
        metadata_prefix=args.METADATA_PREFIX.strip("/"),
        curated_prefix=args.CURATED_PREFIX.strip("/"),
        quarantine_prefix=args.QUARANTINE_PREFIX.strip("/"),
        database_name=args.DATABASE_NAME,
        curated_table=args.CURATED_TABLE,
        quarantine_table=args.QUARANTINE_TABLE or None,
        pipeline_version=args.PIPELINE_VERSION,
        max_invalid_percent=args.MAX_INVALID_PERCENT,
        date_column=args.DATE_COLUMN or None,
    )


def _list_manifest_keys(s3_client: Any, bucket: str, prefix: str) -> list[str]:
    manifest_keys: list[str] = []
    continuation_token: str | None = None

    while True:
        kwargs: dict[str, Any] = {"Bucket": bucket, "Prefix": f"{prefix}/"}
        if continuation_token:
            kwargs["ContinuationToken"] = continuation_token
        response = s3_client.list_objects_v2(**kwargs)
        contents = response.get("Contents", [])
        manifest_keys.extend(
            item["Key"]
            for item in contents
            if item["Key"].endswith(".json") and not item["Key"].endswith("/")
        )
        if not response.get("IsTruncated"):
            break
        continuation_token = response.get("NextContinuationToken")

    return sorted(manifest_keys)


def _read_json(s3_client: Any, bucket: str, key: str) -> dict[str, Any]:
    response = s3_client.get_object(Bucket=bucket, Key=key)
    return json.loads(response["Body"].read().decode("utf-8"))


def _read_csv_rows(s3_client: Any, bucket: str, key: str) -> list[dict[str, Any]]:
    response = s3_client.get_object(Bucket=bucket, Key=key)
    text = response["Body"].read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(text)))


def _write_dataset(
    spark_session: Any,
    records: list[dict[str, Any]],
    *,
    destination: str,
    format_name: str,
    mode: str,
    partition_columns: list[str],
) -> None:
    if not records:
        return
    frame = spark_session.createDataFrame(records)
    writer = frame.write.mode(mode).partitionBy(*partition_columns)
    if format_name == "parquet":
        writer = writer.option("compression", "snappy")
    writer.format(format_name).save(destination)


def run_job(config: JobConfig) -> dict[str, int]:
    """Execute the Phase 3 transformation job."""
    from pyspark.sql import SparkSession

    spark = SparkSession.builder.appName("streamforge-phase3").getOrCreate()
    s3_client = boto3.client("s3")

    curated_records: list[dict[str, Any]] = []
    quarantined_records: list[dict[str, Any]] = []

    for manifest_key in _list_manifest_keys(
        s3_client, config.metadata_bucket, config.metadata_prefix
    ):
        manifest = _read_json(s3_client, config.metadata_bucket, manifest_key)
        if config.input_prefix and not manifest["clean_key"].startswith(
            f"{config.input_prefix}/"
        ):
            continue
        rows = _read_csv_rows(s3_client, config.input_bucket, manifest["clean_key"])
        for row in rows:
            curated, quarantined = transform_record(
                row,
                manifest,
                pipeline_version=config.pipeline_version,
                date_column=config.date_column,
            )
            if curated is not None:
                curated_records.append(curated)
            if quarantined is not None:
                quarantined_records.append(quarantined)

    total_records = len(curated_records) + len(quarantined_records)
    curated_destination = (
        f"s3://{config.curated_bucket}/{config.curated_prefix}/".rstrip("/") + "/"
    )
    quarantine_destination = (
        f"s3://{config.quarantine_bucket}/{config.quarantine_prefix}/".rstrip("/") + "/"
    )
    _write_dataset(
        spark,
        curated_records,
        destination=curated_destination,
        format_name="parquet",
        mode="append",
        partition_columns=["year", "month", "day"],
    )
    _write_dataset(
        spark,
        quarantined_records,
        destination=quarantine_destination,
        format_name="json",
        mode="append",
        partition_columns=["reason", "year", "month", "day"],
    )

    if should_fail_invalid_threshold(
        len(quarantined_records), total_records, config.max_invalid_percent
    ):
        raise RuntimeError(
            "Invalid-row threshold exceeded after writing outputs: "
            f"{len(quarantined_records)} of {total_records} rows quarantined"
        )

    return {
        "rows_read": total_records,
        "rows_written": len(curated_records),
        "rows_quarantined": len(quarantined_records),
    }


def main(argv: list[str] | None = None) -> int:
    config = _parse_args(argv)
    stats = run_job(config)
    print(json.dumps(stats, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    main()
