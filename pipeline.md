# PHASE_1_SPEC.md

# Project Overview

Build Phase 1 of a serverless AWS data engineering platform.

The objective is to automatically process CSV files uploaded to Amazon S3.

When a CSV file is uploaded:

1. An S3 event is generated.
2. EventBridge captures the event.
3. EventBridge invokes an AWS Lambda function.
4. Lambda validates and cleans the data.
5. Valid records are written to a clean-data bucket.
6. Invalid records are written to a rejected-data bucket.
7. Processing statistics are logged.

The entire process must be fully automated with no manual intervention after file upload.

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

# Future Phases

Phase 2:

* AWS Glue
* Glue Crawler
* Athena

Phase 3:

* Parquet conversion
* Partitioning

Phase 4:

* Terraform

Phase 5:

* Aurora PostgreSQL

Phase 6:

* AWS SCT + AWS DMS

Do not implement future phases yet.
