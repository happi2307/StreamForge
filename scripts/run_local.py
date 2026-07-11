"""Run the Phase 1 pipeline locally, without AWS.

This mimics the Lambda flow using local folders instead of S3 buckets:

    local_buckets/raw/       -> drop CSV files here ("upload")
    local_buckets/clean/     <- valid rows land here
    local_buckets/rejected/  <- invalid rows land here

Usage:
    python scripts/run_local.py                      # process every CSV in raw/
    python scripts/run_local.py sample_data/customers.csv
"""

from __future__ import annotations

import importlib
import json
import logging
import sys
import time
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# Import the shared validation logic ("lambda" is a reserved keyword).
validate_and_split = importlib.import_module("lambda.validator").validate_and_split
metadata = importlib.import_module("lambda.metadata")

BUCKETS = ROOT / "local_buckets"
RAW = BUCKETS / "raw"
CLEAN = BUCKETS / "clean"
REJECTED = BUCKETS / "rejected"
MANIFESTS = BUCKETS / "metadata"

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
LOGGER = logging.getLogger("streamforge.local")


def process_file(path: Path) -> dict[str, int]:
    """Validate one CSV and write clean/rejected copies to the local buckets."""
    start = time.perf_counter()
    LOGGER.info("Processing %s", path.name)

    data = pd.read_csv(path)
    clean, rejected = validate_and_split(data)

    CLEAN.mkdir(parents=True, exist_ok=True)
    REJECTED.mkdir(parents=True, exist_ok=True)
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    clean.to_csv(CLEAN / path.name, index=False)
    rejected.to_csv(REJECTED / path.name, index=False)

    stats = {
        "total_records": int(len(data)),
        "valid_records": int(len(clean)),
        "invalid_records": int(len(rejected)),
    }
    duration_ms = (time.perf_counter() - start) * 1000
    processed_timestamp = metadata.utc_now_iso()
    batch_id = metadata.new_phase1_batch_id()
    event_timestamp = processed_timestamp
    manifest = metadata.build_processing_manifest(
        source_bucket="local-raw",
        source_key=path.name,
        clean_bucket="local-clean",
        clean_key=path.name,
        rejected_bucket="local-rejected",
        rejected_key=path.name,
        event_timestamp=event_timestamp,
        processed_timestamp=processed_timestamp,
        phase1_batch_id=batch_id,
        phase1_pipeline_version=metadata.DEFAULT_PHASE1_PIPELINE_VERSION,
        total_records=stats["total_records"],
        valid_records=stats["valid_records"],
        invalid_records=stats["invalid_records"],
        execution_duration_ms=duration_ms,
    )
    manifest_key = metadata.build_manifest_key(path.name)
    manifest_path = MANIFESTS / Path(manifest_key)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    LOGGER.info("Total Records: %d", stats["total_records"])
    LOGGER.info("Valid Records: %d", stats["valid_records"])
    LOGGER.info("Invalid Records: %d", stats["invalid_records"])
    LOGGER.info("Execution duration: %.1f ms", duration_ms)
    LOGGER.info("Clean  -> %s", CLEAN / path.name)
    LOGGER.info("Rejected -> %s", REJECTED / path.name)
    LOGGER.info("Metadata -> %s", manifest_path)
    return stats


def main(argv: list[str]) -> int:
    if argv:
        targets = [Path(arg) for arg in argv]
    else:
        RAW.mkdir(parents=True, exist_ok=True)
        targets = sorted(RAW.glob("*.csv"))

    if not targets:
        LOGGER.warning("No CSV files found. Drop a file in %s and re-run.", RAW)
        return 1

    for path in targets:
        if not path.exists():
            LOGGER.error("File not found: %s", path)
            continue
        try:
            process_file(path)
        except Exception:  # noqa: BLE001 - mirror Lambda's log-then-continue behavior
            LOGGER.exception("Failed to process %s", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
