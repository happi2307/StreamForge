# ADR 0003: Parquet vs CSV for the curated layer

- Status: Accepted
- Date: 2026-07-23

## Context

Phase 2 queries the clean CSV data directly with Athena. Phase 3 adds a curated
layer. The curated layer can stay as CSV or convert to a columnar format.

## Decision

Write the curated layer as Parquet, partitioned by ingestion date, in the
curated bucket.

## Consequences

- Athena scans far less data for column-projected and partition-filtered
  queries, which lowers cost and latency versus CSV.
- Parquet carries typed schema, avoiding the string-typing that raw CSV forces on
  the catalog.
- The clean CSV layer is kept as the source of truth so the curated layer can be
  rebuilt; conversion happens in the Phase 3 Glue job.
- Writers and readers must agree on the partition scheme; the Glue job and the
  curated Glue table both use the `customers` prefix partitioned by date.
