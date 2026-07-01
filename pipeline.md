# STREAMFORGE_PIPELINE_SPEC.md

# Project Overview

Build a phased serverless AWS data engineering platform.

Phase 1 focuses on automatically processing CSV files uploaded to Amazon S3.

When a CSV file is uploaded:

1. An S3 event is generated.
2. EventBridge captures the event.
3. EventBridge invokes an AWS Lambda function.
4. Lambda validates and cleans the data.
5. Valid records are written to a clean-data bucket.
6. Invalid records are written to a rejected-data bucket.
7. Processing statistics are logged.

The entire process must be fully automated with no manual intervention after file upload.

Later phases extend the platform into a queryable analytics pipeline using AWS Glue,
Athena, Parquet conversion, and partitioned storage.

---

# Phase 1 Scope

Implement ONLY the following:

* Amazon S3 buckets
* EventBridge trigger
* AWS Lambda function
* CSV validation
* CSV cleaning
* Logging
* Local testing
* Documentation

Do NOT implement:

* AWS Glue
* Athena
* Aurora PostgreSQL
* AWS DMS
* AWS SCT
* Terraform
* SNS
* CloudWatch dashboards

These belong to later phases.

---

# Architecture

CSV Upload
→ Raw S3 Bucket
→ EventBridge
→ Lambda
→ Validation & Cleaning
→ Clean Bucket
→ Rejected Bucket

---

# Required AWS Resources

## S3 Buckets

Create three buckets:

### Raw Bucket

Purpose:
Store incoming CSV files.

Example:

s3://dataflow-raw

### Clean Bucket

Purpose:
Store validated records.

Example:

s3://dataflow-clean

### Rejected Bucket

Purpose:
Store invalid records.

Example:

s3://dataflow-rejected

---

# Folder Structure

smart-dataflow/

├── lambda/
│   ├── handler.py
│   ├── validator.py
│   ├── requirements.txt
│
├── tests/
│   ├── test_validator.py
│
├── sample_data/
│   ├── customers.csv
│   ├── expected_clean.csv
│   ├── expected_rejected.csv
│
├── docs/
│   ├── architecture.md
│
├── README.md

---

# Input Dataset Format

Input CSV:

customer_id,name,email,sales

Example:

101,John,[john@gmail.com](mailto:john@gmail.com),500
102,,[mary@gmail.com](mailto:mary@gmail.com),600
103,Sam,samgmail.com,700
104,Raj,[raj@gmail.com](mailto:raj@gmail.com),1000

---

# Validation Rules

## Rule 1

customer_id must not be null.

---

## Rule 2

name must not be empty.

---

## Rule 3

email must be valid.

Examples:

Valid:

[john@gmail.com](mailto:john@gmail.com)

Invalid:

johngmail.com

john@

@gmail.com

---

## Rule 4

sales must be numeric.

---

## Rule 5

Remove duplicate customer_id values.

Keep first occurrence.

---

# Expected Output

## Clean Dataset

customer_id,name,email,sales
101,John,[john@gmail.com](mailto:john@gmail.com),500
104,Raj,[raj@gmail.com](mailto:raj@gmail.com),1000

## Rejected Dataset

customer_id,name,email,sales
102,,[mary@gmail.com](mailto:mary@gmail.com),600
103,Sam,samgmail.com,700

---

# Lambda Responsibilities

The Lambda function must:

1. Receive EventBridge event.
2. Extract bucket name and object key.
3. Download CSV file.
4. Validate data.
5. Split valid and invalid rows.
6. Upload valid rows to clean bucket.
7. Upload invalid rows to rejected bucket.
8. Return processing statistics.

Example response:

{
"total_records": 4,
"valid_records": 2,
"invalid_records": 2
}

---

# Logging Requirements

Log:

* File name
* Record count
* Valid record count
* Invalid record count
* Execution duration
* Errors

Example:

INFO Processing customers.csv
INFO Total Records: 4
INFO Valid Records: 2
INFO Invalid Records: 2

---

# Error Handling

Handle:

* Missing file
* Empty file
* Invalid CSV format
* AWS SDK exceptions

Lambda must not crash without logging.

---

# Coding Standards

Python 3.12

Use:

* boto3
* pandas

Follow:

* PEP8
* Type hints
* Modular code

Keep validation logic in validator.py

Keep Lambda entry point in handler.py

---

# Unit Tests

Create tests for:

* Valid email
* Invalid email
* Missing name
* Missing customer_id
* Duplicate customer_id
* Numeric sales validation

Target:

> 80% test coverage

---

# README Requirements

README must include:

1. Project Overview
2. Architecture Diagram
3. AWS Services Used
4. Setup Instructions
5. Deployment Instructions
6. Sample Input
7. Sample Output
8. Future Enhancements

---

# Acceptance Criteria

Project is complete when:

✓ Uploading a CSV to the raw bucket triggers Lambda automatically.

✓ Valid rows appear in clean bucket.

✓ Invalid rows appear in rejected bucket.

✓ Processing statistics are logged.

✓ Unit tests pass.

✓ README is complete.

✓ Architecture documentation exists.

---

# Phase 2 Scope

Phase 2 adds metadata discovery and SQL querying over the cleaned CSV output from
Phase 1.

Implement ONLY the following in Phase 2:

* AWS Glue Data Catalog database
* AWS Glue Crawler for clean-data bucket
* Athena query setup
* IAM permissions for Glue and Athena
* Documentation for running sample Athena queries
* Optional local SQL examples for expected query results

Do NOT implement in Phase 2:

* Parquet conversion
* Partitioned output
* Terraform
* Aurora PostgreSQL
* AWS DMS
* AWS SCT
* BI dashboards

These belong to later phases.

---

# Phase 2 Architecture

CSV Upload
→ Raw S3 Bucket
→ EventBridge
→ Lambda
→ Validation & Cleaning
→ Clean Bucket
→ Glue Crawler
→ Glue Data Catalog
→ Athena

---

# Phase 2 Required AWS Resources

## Glue Data Catalog Database

Purpose:
Store table metadata for the cleaned dataset.

Example:

streamforge_clean_db

## Glue Crawler

Purpose:
Scan the clean-data bucket and infer the CSV table schema.

Crawler source:

s3://dataflow-clean/

Crawler target database:

streamforge_clean_db

Expected table:

customers

## Athena Query Result Bucket

Purpose:
Store Athena query results.

Example:

s3://dataflow-athena-results

---

# Phase 2 Glue Table Requirements

The Glue crawler should detect the following columns:

* customer_id
* name
* email
* sales

Expected data types:

* customer_id: string or bigint
* name: string
* email: string
* sales: double or bigint

If Glue infers a less useful type, manually adjust the schema in the Glue Data
Catalog.

---

# Phase 2 Athena Requirements

Athena must be able to query the clean dataset.

Sample query:

```sql
SELECT
  customer_id,
  name,
  email,
  sales
FROM streamforge_clean_db.customers
ORDER BY customer_id;
```

Sample aggregation query:

```sql
SELECT
  COUNT(*) AS total_customers,
  SUM(sales) AS total_sales,
  AVG(sales) AS average_sales
FROM streamforge_clean_db.customers;
```

---

# Phase 2 IAM Requirements

Glue crawler role needs:

* Read access to the clean-data bucket
* Glue Data Catalog create/update permissions
* CloudWatch Logs permissions

Athena users or roles need:

* Read access to the clean-data bucket
* Read/write access to the Athena query results bucket
* Glue Data Catalog read permissions

---

# Phase 2 Acceptance Criteria

Phase 2 is complete when:

✓ Glue database exists.

✓ Glue crawler scans the clean-data bucket successfully.

✓ Glue table is created for cleaned customer data.

✓ Athena can query cleaned customer records.

✓ Athena query results are written to the Athena results bucket.

✓ README includes Phase 2 setup and query instructions.

---

# Phase 3 Scope

Phase 3 optimizes the analytics layer by converting cleaned CSV data into
Parquet and storing it with partitions for faster and cheaper Athena queries.

Implement ONLY the following in Phase 3:

* Parquet conversion job
* Partitioned S3 output layout
* Glue table for Parquet data
* Athena queries against Parquet table
* Documentation for partition strategy and query examples

Do NOT implement in Phase 3:

* Terraform
* Aurora PostgreSQL
* AWS DMS
* AWS SCT
* Streaming ingestion
* BI dashboards

These belong to later phases.

---

# Phase 3 Architecture

CSV Upload
→ Raw S3 Bucket
→ EventBridge
→ Lambda
→ Validation & Cleaning
→ Clean Bucket
→ Parquet Conversion
→ Curated Partitioned Bucket
→ Glue Data Catalog
→ Athena

---

# Phase 3 Required AWS Resources

## Curated Bucket

Purpose:
Store optimized Parquet files.

Example:

s3://dataflow-curated

## Parquet Conversion Job

Purpose:
Convert cleaned CSV files into Parquet format.

Recommended options:

* AWS Glue ETL job
* AWS Lambda only if files are small enough for Lambda memory and timeout limits

Preferred approach:

Use AWS Glue for scalable conversion.

## Glue Data Catalog Table

Purpose:
Expose the partitioned Parquet dataset to Athena.

Expected table:

customers_curated

---

# Phase 3 Partitioning Strategy

Partition curated data by ingestion date.

Recommended S3 layout:

s3://dataflow-curated/customers/year=2026/month=07/day=01/

Required partition columns:

* year
* month
* day

Optional partition columns for later:

* source_file
* region
* ingestion_batch_id

Avoid partitioning by high-cardinality fields such as customer_id or email.

---

# Phase 3 Parquet Requirements

The Parquet output must:

* Preserve all clean columns from Phase 1
* Add ingestion metadata columns
* Use compression
* Write files to the curated bucket
* Register or repair partitions in Glue/Athena

Recommended compression:

snappy

Required ingestion metadata columns:

* ingestion_timestamp
* source_bucket
* source_key

---

# Phase 3 Athena Requirements

Athena must query the Parquet table and use partitions.

Sample query:

```sql
SELECT
  customer_id,
  name,
  email,
  sales
FROM streamforge_clean_db.customers_curated
WHERE year = '2026'
  AND month = '07'
  AND day = '01';
```

Sample partition repair command:

```sql
MSCK REPAIR TABLE streamforge_clean_db.customers_curated;
```

---

# Phase 3 Acceptance Criteria

Phase 3 is complete when:

✓ Clean CSV data is converted to Parquet.

✓ Parquet files are written to the curated bucket.

✓ Curated data is partitioned by ingestion date.

✓ Glue table exists for curated Parquet data.

✓ Athena queries successfully read the Parquet table.

✓ Queries with partition filters scan less data than CSV queries.

✓ README includes Phase 3 setup, conversion, and query instructions.

---

# Future Phases

Phase 2:

* AWS Glue Data Catalog
* Glue Crawler
* Athena querying over clean CSV data

Phase 3:

* Parquet conversion
* Partitioned curated S3 data
* Athena querying over optimized Parquet data

Phase 4:

* Terraform

Phase 5:

* Aurora PostgreSQL

Phase 6:

* AWS SCT + AWS DMS

Do not implement future phases yet.
