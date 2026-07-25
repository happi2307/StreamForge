# Phase 5 database loader failures

## Trigger

One of the Phase 5 alarms enters `ALARM`:

- `streamforge-dev-phase5-loader-errors` — the loader Lambda raised an error.
- `streamforge-dev-phase5-loader-duration` — a load exceeded its time budget.
- `streamforge-dev-phase5-loader-dlq-messages` — an event reached the DLQ.
- `streamforge-dev-phase5-failed-records` — too many per-record rejections.

## Investigate

1. Open the `streamforge-dev-phase5-serving` CloudWatch dashboard and identify
   the affected window (invocations, errors, duration, Aurora capacity/connections).
2. Read the structured JSON logs in `/aws/lambda/streamforge-database-loader`.
   Filter by `batch_id`; each line carries `status`, `records_inserted`,
   `records_updated`, `records_failed`, and (on failure) `error`.
3. Query the audit tables (see `sql/audit_queries.sql`):
   - Failed batches: `status = 'FAILED'` in `audit.batch_metadata`.
   - Rejected rows: `audit.load_errors` for the `batch_id`.
4. If the error mentions connectivity/timeouts, check the Aurora cluster status,
   the `ServerlessDatabaseCapacity`/`DatabaseConnections` widgets, and that the
   loader security group can still reach Aurora on 5432.
5. If the error mentions `AccessDenied`/`Secrets`/`KMS`, confirm the loader role
   can read the RDS-managed secret and use the KMS key, and that the Secrets
   Manager / KMS VPC endpoints are healthy.

## Recover

- **Transient failure (Aurora scaling / connection):** the batch rolled back
  cleanly and is marked `FAILED`; no partial data was written. Re-drive it by
  re-emitting the curated object event (re-put the object, or replay the DLQ
  message). Idempotency skips any batch already `SUCCESS`.
- **Data failure (validation):** inspect `audit.load_errors`, correct the
  upstream curated data if needed, then replay. Do not hand-edit `analytics`
  tables — the loader is the only writer.
- **Poison event:** if a DLQ message cannot be processed, capture it for
  analysis and delete it once the underlying batch has been reloaded.

## Escalate

If loads fail across healthy inputs, or Aurora is unavailable, pause further
curated writes, and open an incident with the affected `batch_id`s, log lines,
and the `audit.batch_metadata` rows. Aurora point-in-time recovery covers the
backup retention window if data corruption is suspected.
