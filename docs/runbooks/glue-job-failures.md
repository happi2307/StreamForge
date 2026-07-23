# Glue job failures

## Trigger

The `streamforge-dev-glue-job-failures` EventBridge rule sends an SNS alert when
the Phase 3 Glue job fails, times out, or is stopped.

## Investigate

1. Open the Glue job run for `streamforge-transform-customers` and review the error and continuous logs.
2. Identify the Phase 1 manifest and clean object associated with the run.
3. Check the quarantine prefix and the `RowsRead`, `RowsWritten`, and `RowsQuarantined` dashboard metrics.
4. Confirm the Glue role retains S3 and KMS access to clean, metadata, curated, and quarantine buckets.

## Recover

Resolve the job or data issue, then start a new job run. The curated output is
append-only; verify the partition before rerunning to avoid duplicate analytic
records.

## Escalate

Treat a timeout or repeated failure as a pipeline incident. Preserve the Glue
run ID, source keys, and CloudWatch log links in the incident record.
