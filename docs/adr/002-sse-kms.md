# ADR 002: Use SSE-KMS for protected data and operations resources

## Status

Accepted.

## Context

The data lake contains customer data and requires auditable encryption controls
across S3, Athena results, SNS alerts, SQS dead letters, and CloudWatch Logs.

## Decision

Use one customer-managed KMS key per environment, enable automatic rotation,
and grant narrowly scoped service access. S3 buckets, Athena workgroups, SNS,
SQS, and the Lambda log group use that key.

## Consequences

SSE-KMS adds key and API costs plus key-policy maintenance, but supports audit
trails, rotation, service-specific access, and explicit encryption-context
controls for CloudWatch Logs.
