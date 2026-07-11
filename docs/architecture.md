# Phase 1 Architecture

```mermaid
flowchart LR
    Upload[CSV upload] --> Raw[(Raw S3 bucket)]
    Raw --> EventBridge[Amazon EventBridge]
    EventBridge --> Lambda[AWS Lambda]
    Lambda --> Validation[Validate and clean]
    Validation --> Clean[(Clean S3 bucket)]
    Validation --> Rejected[(Rejected S3 bucket)]
    Lambda --> Logs[CloudWatch Logs]
```

Only the raw bucket emits object-created events. EventBridge routes those events
to the Python 3.12 Lambda. The Lambda reads the object, applies the validation
rules, and writes separate CSV outputs to the clean and rejected buckets.

## Phase 2 Architecture

```mermaid
flowchart LR
    Upload[CSV upload] --> Raw[(Raw S3 bucket)]
    Raw --> EventBridge[Amazon EventBridge]
    EventBridge --> Lambda[AWS Lambda]
    Lambda --> Validation[Validate and clean]
    Validation --> Clean[(Clean S3 bucket)]
    Clean --> Crawler[AWS Glue Crawler]
    Crawler --> Catalog[Glue Data Catalog]
    Catalog --> Athena[Amazon Athena]
    Athena --> Results[(Athena results bucket)]
```

Phase 2 keeps the Phase 1 ingestion path intact and adds a query layer over the
clean bucket. The Glue crawler infers schema from the cleaned CSV data, the
catalog stores the metadata, and Athena runs SQL queries whose results are
written to a separate KMS-encrypted results bucket.

## Phase 3 Architecture

```mermaid
flowchart LR
    Upload[CSV upload] --> Raw[(Raw S3 bucket)]
    Raw --> EventBridge[Amazon EventBridge]
    EventBridge --> Lambda[AWS Lambda]
    Lambda --> Clean[(Clean S3 bucket)]
    Lambda --> Rejected[(Rejected S3 bucket)]
    Lambda --> Metadata[(Metadata bucket)]
    Clean --> GlueJob[AWS Glue ETL Job]
    Metadata --> GlueJob
    GlueJob --> Curated[(Curated Parquet bucket)]
    GlueJob --> Quarantine[(Quarantine bucket)]
    Curated --> Catalog[Glue Data Catalog]
    Catalog --> Athena[Amazon Athena]
```

Phase 3 reads both the clean CSV objects and the Phase 1 sidecar manifests. The
Glue job applies business transformations, enriches records with lineage
metadata, writes valid rows to partitioned Parquet, and writes malformed
transformed rows to a quarantine location instead of failing the whole batch by
default.
