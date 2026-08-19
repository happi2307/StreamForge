-- StreamForge Phase 5 — batch validation queries.
--
-- The loader runs the pre-merge checks against staging (bind :batch_id) before
-- merging, and the post-merge checks after merging to prove the load landed.
-- Each query returns a single row the loader inspects; a failed invariant
-- aborts the transaction (ROLLBACK) and marks the batch FAILED.

-- ===========================================================================
-- PRE-MERGE (run against staging.customers for the batch)
-- ===========================================================================

-- Row count staged for the batch (must be > 0 to proceed).
SELECT count(*) AS staged_rows
FROM staging.customers
WHERE batch_id = :batch_id;

-- Mandatory fields present. missing_* must all be 0.
SELECT
    count(*) FILTER (WHERE customer_id IS NULL OR customer_id = '') AS missing_customer_id,
    count(*) FILTER (WHERE sales IS NULL)                           AS missing_sales,
    count(*) FILTER (WHERE sales < 0)                               AS negative_sales
FROM staging.customers
WHERE batch_id = :batch_id;

-- Primary-key uniqueness / duplicate business keys within the batch.
-- Returns one row per duplicated customer_id; an empty result set is a pass.
SELECT customer_id, count(*) AS occurrences
FROM staging.customers
WHERE batch_id = :batch_id
GROUP BY customer_id
HAVING count(*) > 1;

-- ===========================================================================
-- POST-MERGE (run after the upsert, inside the same transaction)
-- ===========================================================================

-- Source (staging) vs destination (sales fact) row counts for the batch.
-- staged_rows must equal loaded_rows.
SELECT
    (SELECT count(*) FROM staging.customers WHERE batch_id = :batch_id) AS staged_rows,
    (SELECT count(*) FROM analytics.sales   WHERE batch_id = :batch_id) AS loaded_rows;

-- Total sales reconciliation for the batch (staging must equal destination).
SELECT
    (SELECT coalesce(sum(sales), 0)        FROM staging.customers WHERE batch_id = :batch_id) AS staged_total,
    (SELECT coalesce(sum(sales_amount), 0) FROM analytics.sales   WHERE batch_id = :batch_id) AS loaded_total;

-- Duplicate customers in the production table (data-integrity guard; the PK
-- makes this structurally impossible, but it is asserted as a defensive check).
SELECT customer_id, count(*) AS occurrences
FROM analytics.customers
GROUP BY customer_id
HAVING count(*) > 1;
