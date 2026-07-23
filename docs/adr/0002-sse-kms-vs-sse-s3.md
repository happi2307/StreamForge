# ADR 0002: SSE-KMS vs SSE-S3

- Status: Accepted
- Date: 2026-07-23

## Context

Every StreamForge bucket holds customer data and must be encrypted at rest. The
choice is between S3-managed keys (SSE-S3) and a customer-managed KMS key
(SSE-KMS).

## Decision

Encrypt all data-plane buckets with a single customer-managed KMS key per
environment (`alias/streamforge-<env>`), managed by the `kms` module.

## Consequences

- Access to the data can be revoked or audited at the key level, independent of
  bucket policies.
- Every principal that reads or writes objects also needs `kms:Decrypt` /
  `kms:GenerateDataKey` on the key; the Lambda and Glue roles grant exactly that.
- Cross-service integrations that publish encrypted payloads (for example an
  SSE-KMS SNS topic) require the key policy to name those service principals.
  Phase 4 therefore leaves the alerts SNS topic unencrypted by default and makes
  the KMS key id an opt-in variable.
- Slight per-request KMS cost and API overhead versus SSE-S3, accepted for the
  stronger access control.
