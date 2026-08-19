-- StreamForge Phase 5 — Aurora PostgreSQL serving schema.
--
-- Idempotent DDL: safe to run repeatedly during provisioning. Loaded once when
-- the database is bootstrapped. Column names mirror the Phase 3 curated Parquet
-- dataset so the loader can map rows without a translation layer.
--
-- Schemas:
--   staging    scratch space; curated rows land here before validation/merge.
--   analytics  production-ready tables served to dashboards/applications.
--   audit      batch bookkeeping and rejected-record capture.

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

-- ---------------------------------------------------------------------------
-- Staging
-- ---------------------------------------------------------------------------
-- UNLOGGED for load throughput; contents are disposable and rebuilt per batch.
-- Mirrors the curated record shape produced by jobs/transform_helpers.py.
CREATE UNLOGGED TABLE IF NOT EXISTS staging.customers (
    customer_id         TEXT,
    name                TEXT,
    email               TEXT,
    sales               BIGINT,
    sales_category      TEXT,
    ingestion_timestamp TEXT,
    processed_timestamp TEXT,
    phase1_batch_id     TEXT,
    batch_id            TEXT,  -- Phase 3 phase3_batch_id; the Phase 5 batch key.
    source_filename     TEXT,
    source_raw_key      TEXT,
    source_clean_key    TEXT,
    pipeline_version    TEXT
);

-- ---------------------------------------------------------------------------
-- Analytics (production)
-- ---------------------------------------------------------------------------
-- One row per customer. customer_id is the business/upsert key.
CREATE TABLE IF NOT EXISTS analytics.customers (
    customer_id         TEXT        NOT NULL,
    name                TEXT,
    email               TEXT,
    sales               BIGINT      NOT NULL DEFAULT 0,
    sales_category      TEXT,
    batch_id            TEXT        NOT NULL,
    processed_timestamp TIMESTAMPTZ,
    source_filename     TEXT,
    pipeline_version    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT customers_pkey PRIMARY KEY (customer_id)
);

-- Per-customer, per-batch sales fact. (customer_id, batch_id) keeps re-runs
-- idempotent even if a batch is replayed.
CREATE TABLE IF NOT EXISTS analytics.sales (
    sale_id             BIGSERIAL,
    customer_id         TEXT        NOT NULL,
    sales_amount        BIGINT      NOT NULL,
    sales_category      TEXT,
    batch_id            TEXT        NOT NULL,
    source_filename     TEXT,
    ingestion_date      DATE,
    processed_timestamp TIMESTAMPTZ,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT sales_pkey PRIMARY KEY (sale_id),
    CONSTRAINT sales_customer_batch_key UNIQUE (customer_id, batch_id)
);

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------
-- One row per processed batch; the source of truth for idempotency/incremental
-- loading. A SUCCESS row means the batch was already loaded and is skipped.
CREATE TABLE IF NOT EXISTS audit.batch_metadata (
    batch_id            TEXT        NOT NULL,
    source_file         TEXT,
    processed_timestamp TIMESTAMPTZ,
    start_time          TIMESTAMPTZ,
    end_time            TIMESTAMPTZ,
    records_loaded      INTEGER     NOT NULL DEFAULT 0,
    records_updated     INTEGER     NOT NULL DEFAULT 0,
    records_failed      INTEGER     NOT NULL DEFAULT 0,
    duration_ms         INTEGER,
    status              TEXT        NOT NULL DEFAULT 'IN_PROGRESS',
    checksum            TEXT,
    pipeline_version    TEXT,
    CONSTRAINT batch_metadata_pkey PRIMARY KEY (batch_id),
    CONSTRAINT batch_status_check
        CHECK (status IN ('IN_PROGRESS', 'SUCCESS', 'FAILED', 'SKIPPED'))
);

-- Rejected records captured during a load; the batch continues around them.
CREATE TABLE IF NOT EXISTS audit.load_errors (
    error_id        BIGSERIAL,
    batch_id        TEXT        NOT NULL,
    customer_id     TEXT,
    error_message   TEXT        NOT NULL,
    error_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_file     TEXT,
    CONSTRAINT load_errors_pkey PRIMARY KEY (error_id)
);
