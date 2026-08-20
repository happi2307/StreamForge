-- =====================================================
-- StreamForge Phase 6 - Validation SQL Queries
-- PostgreSQL queries for manual validation
-- =====================================================

-- =====================================================
-- Row Count Validation
-- =====================================================

-- Compare row counts across all tables
SELECT
    'regions' as table_name,
    COUNT(*) as row_count
FROM regions
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'suppliers', COUNT(*) FROM suppliers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL
SELECT 'employees', COUNT(*) FROM employees
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
UNION ALL
SELECT 'shipments', COUNT(*) FROM shipments
ORDER BY table_name;

-- =====================================================
-- Primary Key Validation
-- =====================================================

-- Check for duplicate primary keys
SELECT 'regions' as table_name, region_id, COUNT(*) as duplicate_count
FROM regions
GROUP BY region_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'customers', customer_id::text, COUNT(*)
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'products', product_id::text, COUNT(*)
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- =====================================================
-- Foreign Key Validation
-- =====================================================

-- Find orphaned customer records (region_id not in regions)
SELECT
    c.customer_id,
    c.customer_name,
    c.region_id as invalid_region_id
FROM customers c
LEFT JOIN regions r ON c.region_id = r.region_id
WHERE c.region_id IS NOT NULL
  AND r.region_id IS NULL;

-- Find orphaned orders (customer_id not in customers)
SELECT
    o.order_id,
    o.order_number,
    o.customer_id as invalid_customer_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Find orphaned order_items (order_id not in orders)
SELECT
    oi.order_item_id,
    oi.order_id as invalid_order_id
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Find orphaned order_items (product_id not in products)
SELECT
    oi.order_item_id,
    oi.product_id as invalid_product_id
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- =====================================================
-- NULL Constraint Validation
-- =====================================================

-- Check for NULL values in NOT NULL columns
SELECT 'customers.customer_name' as column_name, COUNT(*) as null_count
FROM customers WHERE customer_name IS NULL
UNION ALL
SELECT 'customers.email', COUNT(*) FROM customers WHERE email IS NULL
UNION ALL
SELECT 'products.product_name', COUNT(*) FROM products WHERE product_name IS NULL
UNION ALL
SELECT 'products.unit_price', COUNT(*) FROM products WHERE unit_price IS NULL
UNION ALL
SELECT 'orders.order_number', COUNT(*) FROM orders WHERE order_number IS NULL
UNION ALL
SELECT 'orders.customer_id', COUNT(*) FROM orders WHERE customer_id IS NULL
UNION ALL
SELECT 'order_items.quantity', COUNT(*) FROM order_items WHERE quantity IS NULL
UNION ALL
SELECT 'payments.payment_amount', COUNT(*) FROM payments WHERE payment_amount IS NULL;

-- =====================================================
-- Data Consistency Validation
-- =====================================================

-- Verify order totals match sum of line items
SELECT
    o.order_id,
    o.order_number,
    o.order_total as stored_total,
    COALESCE(SUM(oi.line_total), 0) as calculated_total,
    o.order_total - COALESCE(SUM(oi.line_total), 0) as difference
FROM orders o
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY o.order_id, o.order_number, o.order_total
HAVING ABS(o.order_total - COALESCE(SUM(oi.line_total), 0)) > 0.01
ORDER BY ABS(o.order_total - COALESCE(SUM(oi.line_total), 0)) DESC;

-- Verify inventory calculations
SELECT
    inventory_id,
    product_id,
    quantity_on_hand,
    quantity_reserved,
    quantity_available,
    (quantity_on_hand - quantity_reserved) as calculated_available,
    quantity_available - (quantity_on_hand - quantity_reserved) as difference
FROM inventory
WHERE quantity_available != (quantity_on_hand - quantity_reserved);

-- Verify order item line totals
SELECT
    order_item_id,
    order_id,
    quantity,
    unit_price,
    discount_pct,
    line_total as stored_line_total,
    ROUND(quantity * unit_price * (1 - COALESCE(discount_pct, 0) / 100), 2) as calculated_line_total,
    line_total - ROUND(quantity * unit_price * (1 - COALESCE(discount_pct, 0) / 100), 2) as difference
FROM order_items
WHERE ABS(line_total - ROUND(quantity * unit_price * (1 - COALESCE(discount_pct, 0) / 100), 2)) > 0.01;

-- Verify payment amounts match order totals
SELECT
    p.payment_id,
    p.order_id,
    o.order_number,
    p.payment_amount,
    (o.order_total + o.tax_amount + o.shipping_cost) as expected_amount,
    p.payment_amount - (o.order_total + o.tax_amount + o.shipping_cost) as difference
FROM payments p
JOIN orders o ON p.order_id = o.order_id
WHERE p.payment_status = 'COMPLETED'
  AND ABS(p.payment_amount - (o.order_total + o.tax_amount + o.shipping_cost)) > 0.01;

-- =====================================================
-- Business Rule Validation
-- =====================================================

-- Verify no negative inventory quantities
SELECT
    inventory_id,
    product_id,
    quantity_on_hand,
    quantity_reserved,
    quantity_available
FROM inventory
WHERE quantity_on_hand < 0
   OR quantity_reserved < 0
   OR quantity_available < 0;

-- Verify no negative prices
SELECT
    product_id,
    product_name,
    unit_price,
    cost_price
FROM products
WHERE unit_price < 0 OR cost_price < 0;

-- Verify order status consistency
SELECT
    o.order_id,
    o.order_number,
    o.order_status,
    p.payment_status,
    s.shipment_status
FROM orders o
LEFT JOIN payments p ON o.order_id = p.order_id
LEFT JOIN shipments s ON o.order_id = s.order_id
WHERE (o.order_status = 'DELIVERED' AND s.shipment_status != 'DELIVERED')
   OR (o.order_status = 'SHIPPED' AND s.shipment_status NOT IN ('SHIPPED', 'IN_TRANSIT', 'DELIVERED'));

-- =====================================================
-- Data Range Validation
-- =====================================================

-- Check date ranges are reasonable
SELECT
    'orders' as table_name,
    MIN(order_date) as min_date,
    MAX(order_date) as max_date,
    COUNT(*) as record_count
FROM orders
UNION ALL
SELECT
    'payments',
    MIN(payment_date),
    MAX(payment_date),
    COUNT(*)
FROM payments
UNION ALL
SELECT
    'shipments',
    MIN(shipment_date),
    MAX(shipment_date),
    COUNT(*)
FROM shipments;

-- =====================================================
-- Aggregate Comparison
-- =====================================================

-- Summary statistics for validation
SELECT
    'Total Customers' as metric,
    COUNT(*) as value
FROM customers
UNION ALL
SELECT 'Active Customers', COUNT(*) FROM customers WHERE customer_status = 'ACTIVE'
UNION ALL
SELECT 'Total Orders', COUNT(*) FROM orders
UNION ALL
SELECT 'Completed Orders', COUNT(*) FROM orders WHERE order_status IN ('SHIPPED', 'DELIVERED')
UNION ALL
SELECT 'Total Products', COUNT(*) FROM products
UNION ALL
SELECT 'Active Products', COUNT(*) FROM products WHERE discontinued = 'N'
UNION ALL
SELECT 'Total Order Items', COUNT(*) FROM order_items
UNION ALL
SELECT 'Total Payments', COUNT(*) FROM payments
UNION ALL
SELECT 'Completed Payments', COUNT(*) FROM payments WHERE payment_status = 'COMPLETED';

-- Financial aggregates
SELECT
    'Total Order Value' as metric,
    SUM(order_total)::numeric(15,2) as amount
FROM orders
UNION ALL
SELECT
    'Total Tax Amount',
    SUM(tax_amount)::numeric(15,2)
FROM orders
UNION ALL
SELECT
    'Total Shipping Cost',
    SUM(shipping_cost)::numeric(15,2)
FROM orders
UNION ALL
SELECT
    'Total Payments Received',
    SUM(payment_amount)::numeric(15,2)
FROM payments
WHERE payment_status = 'COMPLETED';

-- =====================================================
-- Index Validation
-- =====================================================

-- Verify all expected indexes exist
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'regions', 'customers', 'suppliers', 'products',
    'inventory', 'employees', 'orders', 'order_items',
    'payments', 'shipments'
  )
ORDER BY tablename, indexname;

-- =====================================================
-- Constraint Validation
-- =====================================================

-- Verify all foreign key constraints exist
SELECT
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    tc.constraint_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, tc.constraint_name;

-- Verify all check constraints exist
SELECT
    tc.table_name,
    tc.constraint_name,
    cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
    ON tc.constraint_name = cc.constraint_name
WHERE tc.constraint_type = 'CHECK'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, tc.constraint_name;

-- =====================================================
-- Sample Data Verification
-- =====================================================

-- Compare sample records (spot check)
SELECT
    customer_id,
    customer_name,
    email,
    customer_status,
    credit_limit
FROM customers
ORDER BY customer_id
LIMIT 10;

SELECT
    order_id,
    order_number,
    customer_id,
    order_date,
    order_status,
    order_total
FROM orders
ORDER BY order_id
LIMIT 10;

-- =====================================================
-- Performance Check
-- =====================================================

-- Check table statistics are up to date
SELECT
    schemaname,
    tablename,
    n_live_tup as row_count,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;

-- Suggest ANALYZE if needed
-- Run: ANALYZE tablename;
