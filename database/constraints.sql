-- StreamForge Phase 5 — data-integrity constraints.
--
-- Primary keys, the sales business-key uniqueness, and the batch status check
-- are declared inline in schema.sql. This file adds the remaining integrity
-- rules and the foreign key between the sales fact and its customer.
--
-- Guarded with DO blocks so re-running is a no-op (ADD CONSTRAINT is not
-- idempotent on its own in PostgreSQL).

-- sales must be non-negative in the production customer table.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'customers_sales_nonnegative'
    ) THEN
        ALTER TABLE analytics.customers
            ADD CONSTRAINT customers_sales_nonnegative CHECK (sales >= 0);
    END IF;
END $$;

-- sales_amount must be non-negative in the sales fact table.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'sales_amount_nonnegative'
    ) THEN
        ALTER TABLE analytics.sales
            ADD CONSTRAINT sales_amount_nonnegative CHECK (sales_amount >= 0);
    END IF;
END $$;

-- Referential integrity: every sale belongs to a known customer.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'sales_customer_fk'
    ) THEN
        ALTER TABLE analytics.sales
            ADD CONSTRAINT sales_customer_fk
            FOREIGN KEY (customer_id) REFERENCES analytics.customers (customer_id);
    END IF;
END $$;
