# ADR 005: Aurora PostgreSQL Serverless v2 serving layer (Phase 5)

## Status

Accepted.

## Context

Phases 1–3 land curated, partitioned Parquet in S3, queryable through Athena.
Phase 5 needs a relational serving layer so dashboards, applications, and
reporting can query production-ready tables with joins, indexes, transactions,
and sub-second point lookups — access patterns Athena serves poorly. The loader
must be automatic, idempotent, incremental, and transaction-safe, and reuse the
project's existing KMS/SNS/CloudWatch operational controls.

## Decision

- **Engine:** Amazon Aurora PostgreSQL **Serverless v2**. It auto-scales
  capacity (ACUs) to demo-idle levels, is KMS-encrypted, and provides the
  `MERGE`/`INSERT ... ON CONFLICT` upserts, transactions, and constraints the
  spec requires. Provisioned instances were rejected for always-on cost.
- **Networking:** a new **private-only VPC** (no internet/NAT). The loader
  Lambda runs in the VPC and reaches S3, Secrets Manager, KMS, CloudWatch, and
  STS through **VPC endpoints**, avoiding NAT cost while keeping Aurora private.
  This is the first VPC in the project; the Phase 1/dashboard Lambdas stay
  out-of-VPC because they only call managed AWS APIs.
- **Driver:** `pg8000`, a pure-Python PostgreSQL driver, so the loader packages
  into a Lambda zip without native builds; `pyarrow` reads curated Parquet.
- **Credentials:** the RDS-managed master-user secret in Secrets Manager, read
  by the loader at runtime. No credentials in code or environment.
- **Load pattern:** curated → `staging` → validate → upsert (`ON CONFLICT`) into
  `analytics` → `audit`, all in one transaction. Idempotency keys on the Phase 3
  `phase3_batch_id`; an already-`SUCCESS` batch is skipped.

## Consequences

Introduces VPC networking and an always-available (if idle-scaled) database,
adding cost and operational surface versus pure serverless S3/Athena. In return
the platform gains transactional, indexed, low-latency serving with full audit
and recovery. Reserved loader concurrency of 1 serialises a batch's multiple
Parquet part-file events; batch-level idempotency makes the extra events cheap
no-ops. Query-level audit logging (pgaudit/Performance Insights deep dive) is a
documented follow-up. SCT/DMS-based heterogeneous migration is deferred to
Phase 6.
