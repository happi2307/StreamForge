# High quarantine rate

## Trigger

The `streamforge-dev-high-quarantine-rate` alarm enters `ALARM` when the
percentage of Phase 3 records written to quarantine exceeds the configured
`phase3_max_invalid_percent` threshold.

## Investigate

1. Check the Phase 3 dashboard counts for rows read, written, and quarantined.
2. Inspect the quarantine S3 prefix partitioned by `reason`, `year`, `month`, and `day`.
3. Compare the source CSV and Phase 1 manifest to identify schema, sales, or date-format changes.
4. Confirm the alarm period contains a complete Glue job run before estimating the batch rate.

## Recover

Fix the source-data contract or transformation code, then rerun the affected
batch. Quarantined rows are retained as evidence; do not delete them during
incident response.

## Escalate

Pause downstream analytics consumption if the invalid data affects a published
partition or the source contract changed unexpectedly.
