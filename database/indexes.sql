-- StreamForge Phase 5 — performance indexes on business keys.
-- Idempotent: safe to run repeatedly. Primary keys and the sales unique
-- constraint already create their own indexes; these cover query/lookup paths.

-- Serving lookups by business key and category.
CREATE INDEX IF NOT EXISTS idx_customers_batch_id
    ON analytics.customers (batch_id);
CREATE INDEX IF NOT EXISTS idx_customers_processed_timestamp
    ON analytics.customers (processed_timestamp);
CREATE INDEX IF NOT EXISTS idx_customers_sales_category
    ON analytics.customers (sales_category);

-- Sales fact access patterns: by customer, by batch, by date.
CREATE INDEX IF NOT EXISTS idx_sales_customer_id
    ON analytics.sales (customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_batch_id
    ON analytics.sales (batch_id);
CREATE INDEX IF NOT EXISTS idx_sales_ingestion_date
    ON analytics.sales (ingestion_date);

-- Audit reporting: recent batches and error triage by batch.
CREATE INDEX IF NOT EXISTS idx_batch_metadata_status
    ON audit.batch_metadata (status);
CREATE INDEX IF NOT EXISTS idx_batch_metadata_processed_timestamp
    ON audit.batch_metadata (processed_timestamp);
CREATE INDEX IF NOT EXISTS idx_load_errors_batch_id
    ON audit.load_errors (batch_id);
