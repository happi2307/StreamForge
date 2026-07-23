# Runbooks

Operational runbooks for StreamForge. Each entry lists the alert or symptom, how
to triage it, and how to recover.

## Lambda failures

- **Alarm:** `streamforge-processor-errors` or `streamforge-processor-throttles`.
- **Triage:** Open CloudWatch Logs for the `streamforge-processor` function and
  read the latest error. Errors are usually a malformed object or a missing
  permission; throttles mean concurrent invocations hit the account limit.
- **Recover:** Fix the input or the IAM/KMS permission, then re-upload the
  offending object to the raw bucket. For throttles, request a concurrency limit
  increase or add reserved concurrency.

## Glue job failures

- **Alert:** SNS message from the `streamforge-glue-job-failed` EventBridge rule
  (state `FAILED`, `TIMEOUT`, or `ERROR`).
- **Triage:** In the Glue console open the failed run and read the error and the
  CloudWatch log stream for the run id in the alert.
- **Recover:** Address the cause (schema drift, bad manifest, permissions), then
  re-run the job. Rows that failed transformation are written to the quarantine
  bucket instead of failing the batch, up to the invalid-percent threshold.

## Athena query failures

- **Symptom:** Query errors or empty results after new data lands.
- **Triage:** Confirm the crawler ran and the partition is registered; check the
  workgroup result location and KMS permissions.
- **Recover:** Run `MSCK REPAIR TABLE` (or re-run the crawler) to pick up new
  partitions, and verify the querying principal has `kms:Decrypt` on the key.

## High quarantine rate

- **Symptom:** A large share of a batch lands in the quarantine bucket.
- **Triage:** Inspect quarantined records for a common cause (upstream schema
  change, encoding, delimiter).
- **Recover:** Fix the source or the transform rules; reprocess the clean objects
  once corrected. Consider tightening or relaxing `phase3_max_invalid_percent`.

## KMS access issues

- **Symptom:** `AccessDenied` / `KMS.DisabledException` on read or write.
- **Triage:** Confirm the key is enabled and the failing role has `kms:Decrypt`
  and `kms:GenerateDataKey` on the environment key.
- **Recover:** Re-enable the key or add the missing grant to the role's inline
  policy. If an SSE-KMS SNS topic fails to publish, add the service principal to
  the key policy or fall back to an unencrypted topic.
