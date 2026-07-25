# PHASE_5_SPEC.md

# Project

**StreamForge – Enterprise Serverless Data Pipeline**

# Phase 5

**Automated Database Loading & Downstream Data Serving**

---

# Objective

Phase 5 extends the existing serverless data lake by introducing a production-grade serving layer.

Curated Parquet datasets produced during Phase 3 are automatically loaded into a relational database, making them available for dashboards, applications, reporting, and downstream analytics.

The implementation should support incremental processing, auditing, validation, recovery, and production operational practices.

---

# Previous Phases

## Phase 1

- S3 Raw Ingestion
- EventBridge
- Lambda Validation
- Clean Bucket
- Rejected Bucket
- Processing Metadata

## Phase 2

- Glue Catalog
- Athena
- Analytics over Clean Data

## Phase 3

- Glue ETL
- Business Transformations
- Curated Parquet Dataset
- Metadata Enrichment
- Quarantine Handling

## Phase 4

- Terraform
- GitHub Actions
- IAM
- KMS
- CloudWatch
- SNS
- Operational Monitoring

Phase 5 must integrate with all previous phases without modifying their existing behavior.

---

# Objectives

Implement:

- Aurora PostgreSQL
- Database schema
- Automated loading
- Incremental loading
- Upsert strategy
- Transaction management
- Audit logging
- Load validation
- Monitoring
- Error recovery
- Documentation

Do NOT implement:

- AWS SCT
- AWS DMS
- Schema conversion
- AI-assisted migration

These belong to Phase 6.

---

# High-Level Architecture

```
CSV Upload

↓

Raw Bucket

↓

EventBridge

↓

Lambda Validation

↓

Clean Bucket

↓

Glue ETL

↓

Curated Bucket (Parquet)

↓

Glue Catalog

↓

Athena

↓

EventBridge

↓

Database Loader Lambda

↓

Aurora PostgreSQL

↓

Applications / Dashboards / Reporting
```

---

# Design Principles

- Database loading is independent from Glue.
- Glue publishes curated datasets only.
- EventBridge triggers the loading workflow.
- Loader is idempotent.
- Every batch is auditable.
- Failed batches are recoverable.
- Duplicate processing must never occur.

---

# AWS Services

Use:

- Amazon Aurora PostgreSQL
- AWS Lambda
- Amazon EventBridge
- Amazon S3
- AWS Secrets Manager
- Amazon CloudWatch
- Amazon SNS
- IAM
- KMS

---

# Repository Structure

```
project-root/

├── database/
│   ├── schema.sql
│   ├── indexes.sql
│   ├── constraints.sql
│
├── lambda/
│   └── database_loader/
│
├── sql/
│   ├── merge.sql
│   ├── validation.sql
│   ├── audit_queries.sql
│
├── docs/
│   ├── database_architecture.md
│
├── tests/
│
└── README.md
```

---

# Database

Use:

Amazon Aurora PostgreSQL

Database:

```
streamforge
```

Schemas

```
staging

analytics

audit
```

---

# Required Tables

## analytics.customers

Stores production-ready customer records.

Primary Key

```
customer_id
```

---

## analytics.sales

Stores sales information.

---

## audit.batch_metadata

Stores metadata about every processed batch.

Suggested columns

```
batch_id

source_file

processed_timestamp

records_loaded

records_failed

duration_ms

status

checksum
```

---

## audit.load_errors

Stores rejected database records.

Columns

```
batch_id

customer_id

error_message

timestamp

source_file
```

---

# Loader Workflow

```
Curated Parquet

↓

EventBridge

↓

Database Loader Lambda

↓

Read Metadata

↓

Validate Batch

↓

Load into Staging Tables

↓

Run Validation

↓

MERGE into Analytics Tables

↓

Update Audit Tables

↓

Send Notifications

↓

Complete
```

---

# Loading Strategy

Never load directly into production tables.

Instead:

```
Curated

↓

Staging Tables

↓

Validation

↓

MERGE

↓

Production Tables
```

---

# Incremental Loading

Every dataset contains

```
batch_id

processed_timestamp

source_filename
```

Loader must

- detect already processed batches
- skip duplicate batches
- log skipped batches

---

# Idempotency

The loader must be safe to execute multiple times.

Requirements

- duplicate batch detection
- transaction rollback
- MERGE instead of INSERT
- no duplicate customer records

---

# Upsert Strategy

Business key

```
customer_id
```

Pseudo logic

```
IF customer exists

UPDATE

ELSE

INSERT
```

---

# Transaction Handling

Wrap every batch in a database transaction.

If any critical step fails

```
ROLLBACK

log error

update audit

send notification
```

No partial loads are allowed.

---

# Validation

Before MERGE

Validate

- row count
- mandatory fields
- primary key uniqueness
- foreign key consistency
- numeric values
- duplicate keys

After MERGE

Validate

- source count equals destination count
- total sales
- customer totals
- duplicate count

---

# Metadata

Every loaded record should contain

```
batch_id

processed_timestamp

source_filename

pipeline_version
```

---

# Audit Logging

Store

```
batch_id

start_time

end_time

records_loaded

records_updated

records_failed

duration_ms

status

checksum
```

---

# Error Handling

If an individual record fails

```
log record

store in audit.load_errors

continue processing
```

If a critical failure occurs

```
rollback transaction

mark batch failed

notify SNS
```

---

# Secrets Management

Database credentials must never be stored in code.

Store credentials in

AWS Secrets Manager

Lambda retrieves credentials at runtime.

---

# Security

Aurora

- encrypted using KMS
- private networking if VPC already exists
- IAM least privilege

Lambda

- Secrets Manager access
- Aurora connection
- CloudWatch Logs
- SNS publish

---

# Performance Requirements

Implement

- batch inserts
- connection reuse
- transactions
- prepared statements
- indexes on business keys

Suggested indexes

```
customer_id

batch_id

processed_timestamp
```

---

# Monitoring

CloudWatch Dashboard

Include

- successful loads
- failed loads
- load duration
- database errors
- retry count
- skipped batches
- records inserted
- records updated

---

# CloudWatch Alarms

Create alarms

- database loader failures
- Aurora connection failures
- load duration threshold exceeded
- excessive failed records
- repeated retries

---

# SNS Notifications

Notify on

- batch failure
- Aurora unavailable
- validation failure
- successful deployment (optional)

---

# Configuration

Use environment variables

```
DB_SECRET_NAME

DB_HOST

DB_NAME

DB_SCHEMA

SNS_TOPIC

PIPELINE_VERSION

LOG_LEVEL
```

Avoid hardcoded values.

---

# Logging

Use structured JSON logging.

Example

```json
{
  "pipeline": "streamforge",
  "stage": "database_loader",
  "batch_id": "20260725001",
  "records_inserted": 1245,
  "records_updated": 18,
  "records_failed": 2,
  "duration_ms": 3210,
  "status": "SUCCESS"
}
```

Every log should contain

- timestamp
- batch_id
- stage
- status
- duration
- filename

---

# Testing

Create tests for

- duplicate batches
- MERGE logic
- rollback behavior
- validation failures
- audit logging
- connection failures
- Secrets Manager retrieval

Integration tests

- load sample batch
- verify row counts
- verify audit tables
- verify retries

---

# Documentation

Update README

Include

- database architecture
- schema diagram
- loading workflow
- audit workflow
- retry strategy
- recovery strategy
- validation strategy
- performance tuning
- screenshots

---

# Required Diagrams

Create

- database architecture
- loading workflow
- transaction flow
- audit workflow
- retry flow

---

# Deliverables

- Aurora PostgreSQL database
- Database schema
- Loader Lambda
- SQL scripts
- Audit tables
- Validation scripts
- Monitoring
- Documentation
- Integration tests

---

# Acceptance Criteria

Database

- Aurora PostgreSQL deployed
- schema created successfully

Loading

- curated Parquet automatically loaded
- staging tables used
- MERGE implemented
- duplicate batches skipped

Validation

- source and destination counts verified
- invalid records captured
- audit records created

Operations

- rollback works correctly
- SNS alerts function
- CloudWatch metrics available
- structured logs generated

Security

- Secrets Manager used
- KMS encryption enabled
- IAM least privilege

Documentation

- README updated
- architecture diagrams included
- deployment instructions verified

---

# Success Metrics

Phase 5 is successful when the project demonstrates:

- Production-grade relational data loading
- Idempotent batch processing
- Incremental loading
- Transaction-safe database operations
- Comprehensive auditing
- Automatic validation
- Secure credential management
- Operational monitoring and alerting
- Recoverable failure handling
- Enterprise-ready downstream data serving

The completed Phase 5 should provide a reliable serving layer and prepare StreamForge for **Phase 6**, where heterogeneous database migration using AWS Schema Conversion Tool (SCT) and AWS Database Migration Service (DMS) will be implemented.
