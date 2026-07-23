# Athena query failures

## Trigger

The `streamforge-dev-athena-query-failures` EventBridge rule alerts on failed or
cancelled queries from the StreamForge Phase 2 and Phase 3 workgroups.

## Investigate

1. Open the query execution ID from the alert in Athena.
2. Check syntax, Glue table and partition metadata, and the query result location.
3. For access failures, verify the caller's Lake/Athena/S3 permissions and KMS access to the Athena results bucket.
4. For partition-related failures, confirm the expected curated objects and partitions exist.

## Recover

Correct the query or catalog issue and rerun it in the same workgroup. Avoid
changing workgroup encryption or result-location settings outside Terraform.
