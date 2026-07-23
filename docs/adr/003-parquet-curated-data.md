# ADR 003: Publish curated data as partitioned Parquet

## Status

Accepted.

## Context

Clean CSV is useful for transparent validation, but it is inefficient for
repeated analytic queries.

## Decision

Phase 3 transforms validated CSV into Snappy-compressed Parquet partitioned by
the source ingestion date. Invalid transformed rows are retained in a separate
quarantine location.

## Consequences

Athena scans less data and downstream consumers receive typed, lineage-rich
records. The pipeline gains Glue ETL complexity and requires partition-aware
query practices.
