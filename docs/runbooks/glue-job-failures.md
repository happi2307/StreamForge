# Glue job failures

## Trigger

The `streamforge-dev-glue-job-failures` EventBridge rule sends an SNS alert when
the Phase 3 Glue job fails, times out, or is stopped.

## Verified alert path

On 2026-07-28, controlled batch
`jr_3dca0bb9f6c88f5d3c431e6652ba035e3f85d7ae8435909c707c097f447dd4fb`
failed after startup because its sole row was quarantined for invalid sales.
The rule recorded one invocation and no `FailedInvocations`; the isolated input
and metadata objects were then removed.

## Investigate

1. Open the Glue job run for `streamforge-transform-customers` and review the error and continuous logs.
2. Identify the Phase 1 manifest and clean object associated with the run.
3. Check the quarantine prefix and the `RowsRead`, `RowsWritten`, and `RowsQuarantined` dashboard metrics.
4. Confirm the Glue role retains S3 and KMS access to clean, metadata, curated, and quarantine buckets.
5. For encrypted continuous logs, verify the Glue role has
   `logs:AssociateKmsKey` scoped to this job's log groups and that the KMS key
   policy permits the CloudWatch Logs encryption contexts for both `error` and
   `output` groups.

## Recover

Resolve the job or data issue, then start a new job run. The curated output is
append-only; verify the partition before rerunning to avoid duplicate analytic
records.

## Escalate

Treat a timeout or repeated failure as a pipeline incident. Preserve the Glue
run ID, source keys, and CloudWatch log links in the incident record.
