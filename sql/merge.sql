-- StreamForge Phase 5 — MERGE (upsert) from staging into production.
--
-- The loader runs these statements inside a single transaction, after staging
-- has been populated and validated for the batch. :batch_id is bound by the
-- loader (pg8000 uses %s placeholders at runtime; the named form here documents
-- intent for operators running the SQL by hand).
--
-- Business key: customer_id. Never INSERT blindly — upsert so replays and
-- late-arriving corrections never create duplicate customers.

-- 1. Upsert customers. INSERT ... ON CONFLICT is the reliable PostgreSQL upsert
--    idiom and works on every supported Aurora PostgreSQL major version.
INSERT INTO analytics.customers AS c (
    customer_id, name, email, sales, sales_category,
    batch_id, processed_timestamp, source_filename, pipeline_version, updated_at
)
SELECT
    s.customer_id,
    s.name,
    s.email,
    s.sales,
    s.sales_category,
    s.batch_id,
    NULLIF(s.processed_timestamp, '')::timestamptz,
    s.source_filename,
    s.pipeline_version,
    now()
FROM staging.customers s
WHERE s.batch_id = :batch_id
ON CONFLICT (customer_id) DO UPDATE
SET name                = EXCLUDED.name,
    email               = EXCLUDED.email,
    sales               = EXCLUDED.sales,
    sales_category      = EXCLUDED.sales_category,
    batch_id            = EXCLUDED.batch_id,
    processed_timestamp = EXCLUDED.processed_timestamp,
    source_filename     = EXCLUDED.source_filename,
    pipeline_version    = EXCLUDED.pipeline_version,
    updated_at          = now();

-- 2. Upsert the per-batch sales fact. (customer_id, batch_id) is unique.
INSERT INTO analytics.sales AS f (
    customer_id, sales_amount, sales_category,
    batch_id, source_filename, ingestion_date, processed_timestamp
)
SELECT
    s.customer_id,
    s.sales,
    s.sales_category,
    s.batch_id,
    s.source_filename,
    NULLIF(s.ingestion_timestamp, '')::timestamptz::date,
    NULLIF(s.processed_timestamp, '')::timestamptz
FROM staging.customers s
WHERE s.batch_id = :batch_id
ON CONFLICT (customer_id, batch_id) DO UPDATE
SET sales_amount        = EXCLUDED.sales_amount,
    sales_category      = EXCLUDED.sales_category,
    source_filename     = EXCLUDED.source_filename,
    ingestion_date      = EXCLUDED.ingestion_date,
    processed_timestamp = EXCLUDED.processed_timestamp,
    loaded_at           = now();

-- ---------------------------------------------------------------------------
-- SQL:2003 MERGE equivalent (PostgreSQL 15+ / Aurora PostgreSQL 15+).
-- Kept for reference; the loader uses the ON CONFLICT form above for maximum
-- version portability.
-- ---------------------------------------------------------------------------
-- MERGE INTO analytics.customers c
-- USING (SELECT * FROM staging.customers WHERE batch_id = :batch_id) s
-- ON c.customer_id = s.customer_id
-- WHEN MATCHED THEN UPDATE
--     SET name = s.name, email = s.email, sales = s.sales,
--         sales_category = s.sales_category, batch_id = s.batch_id,
--         source_filename = s.source_filename,
--         pipeline_version = s.pipeline_version, updated_at = now()
-- WHEN NOT MATCHED THEN INSERT
--     (customer_id, name, email, sales, sales_category, batch_id,
--      source_filename, pipeline_version)
--     VALUES (s.customer_id, s.name, s.email, s.sales, s.sales_category,
--             s.batch_id, s.source_filename, s.pipeline_version);
