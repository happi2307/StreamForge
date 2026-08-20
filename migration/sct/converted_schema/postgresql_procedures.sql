-- =====================================================
-- StreamForge Phase 6 - Converted PostgreSQL Procedures
-- Converted from Oracle PL/SQL to PostgreSQL PL/pgSQL
-- =====================================================

-- Procedure 1: Calculate order totals
CREATE OR REPLACE PROCEDURE calculate_order_total(
    p_order_id IN BIGINT,
    INOUT p_total NUMERIC DEFAULT 0,
    INOUT p_tax NUMERIC DEFAULT 0,
    INOUT p_grand_total NUMERIC DEFAULT 0
) AS $$
DECLARE
    v_subtotal NUMERIC := 0;
    v_tax_rate NUMERIC := 0.08;
BEGIN
    -- Calculate subtotal from order items
    SELECT COALESCE(SUM(line_total), 0)
    INTO v_subtotal
    FROM order_items
    WHERE order_id = p_order_id;

    -- Calculate tax
    p_tax := v_subtotal * v_tax_rate;
    p_total := v_subtotal;
    p_grand_total := v_subtotal + p_tax;

    -- Log the calculation
    RAISE NOTICE 'Order % total: %', p_order_id, p_grand_total;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_total := 0;
        p_tax := 0;
        p_grand_total := 0;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculating order total: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Procedure 2: Reserve inventory for order
CREATE OR REPLACE PROCEDURE reserve_inventory(
    p_order_id IN BIGINT,
    INOUT p_success VARCHAR DEFAULT 'SUCCESS'
) AS $$
DECLARE
    v_product_id BIGINT;
    v_quantity INTEGER;
    v_available INTEGER;
    order_items_cur CURSOR FOR
        SELECT product_id, quantity
        FROM order_items
        WHERE order_id = p_order_id;
BEGIN
    p_success := 'SUCCESS';

    -- Loop through all order items
    OPEN order_items_cur;
    LOOP
        FETCH order_items_cur INTO v_product_id, v_quantity;
        EXIT WHEN NOT FOUND;

        -- Check available inventory
        SELECT quantity_available
        INTO v_available
        FROM inventory
        WHERE product_id = v_product_id
        FOR UPDATE;

        IF v_available < v_quantity THEN
            p_success := 'INSUFFICIENT_INVENTORY';
            ROLLBACK;
            EXIT;
        END IF;

        -- Reserve the inventory
        UPDATE inventory
        SET quantity_reserved = quantity_reserved + v_quantity,
            quantity_available = quantity_available - v_quantity,
            updated_date = CURRENT_TIMESTAMP
        WHERE product_id = v_product_id;

    END LOOP;
    CLOSE order_items_cur;

    IF p_success = 'SUCCESS' THEN
        COMMIT;
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_success := 'PRODUCT_NOT_FOUND';
        ROLLBACK;
    WHEN OTHERS THEN
        p_success := 'ERROR';
        ROLLBACK;
        RAISE EXCEPTION 'Error reserving inventory: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Procedure 3: Process payment
CREATE OR REPLACE PROCEDURE process_payment(
    p_order_id IN BIGINT,
    p_payment_amount IN NUMERIC,
    p_payment_method IN VARCHAR,
    INOUT p_payment_id BIGINT DEFAULT NULL
) AS $$
DECLARE
    v_order_total NUMERIC;
    v_transaction_id VARCHAR(100);
BEGIN
    -- Get order total
    SELECT order_total + tax_amount + shipping_cost
    INTO v_order_total
    FROM orders
    WHERE order_id = p_order_id;

    -- Verify payment amount
    IF p_payment_amount < v_order_total THEN
        RAISE EXCEPTION 'Payment amount insufficient';
    END IF;

    -- Generate transaction ID
    v_transaction_id := 'TXN-' || p_payment_method || '-' ||
                        TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS') || '-' ||
                        nextval('payments_payment_id_seq'::regclass)::TEXT;

    -- Insert payment record
    INSERT INTO payments (
        order_id, payment_date, payment_amount,
        payment_method, transaction_id, payment_status
    ) VALUES (
        p_order_id, CURRENT_TIMESTAMP, p_payment_amount,
        p_payment_method, v_transaction_id, 'COMPLETED'
    ) RETURNING payment_id INTO p_payment_id;

    -- Update order status
    UPDATE orders
    SET order_status = 'PROCESSING',
        updated_date = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION 'Order not found';
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE EXCEPTION 'Error processing payment: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Function 1: Get customer credit status
CREATE OR REPLACE FUNCTION get_customer_credit_status(
    p_customer_id IN BIGINT
) RETURNS VARCHAR AS $$
DECLARE
    v_credit_limit NUMERIC;
    v_total_outstanding NUMERIC := 0;
    v_available_credit NUMERIC;
    v_status VARCHAR(50);
BEGIN
    -- Get customer credit limit
    SELECT credit_limit
    INTO v_credit_limit
    FROM customers
    WHERE customer_id = p_customer_id;

    -- Calculate outstanding orders (unpaid)
    SELECT COALESCE(SUM(o.order_total + o.tax_amount + o.shipping_cost), 0)
    INTO v_total_outstanding
    FROM orders o
    LEFT JOIN payments p ON o.order_id = p.order_id AND p.payment_status = 'COMPLETED'
    WHERE o.customer_id = p_customer_id
      AND o.order_status IN ('PENDING', 'PROCESSING')
      AND p.payment_id IS NULL;

    v_available_credit := v_credit_limit - v_total_outstanding;

    -- Determine status
    IF v_available_credit <= 0 THEN
        v_status := 'CREDIT_LIMIT_EXCEEDED';
    ELSIF v_available_credit < (v_credit_limit * 0.1) THEN
        v_status := 'CREDIT_WARNING';
    ELSE
        v_status := 'CREDIT_OK';
    END IF;

    RETURN v_status;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'CUSTOMER_NOT_FOUND';
    WHEN OTHERS THEN
        RETURN 'ERROR';
END;
$$ LANGUAGE plpgsql;

-- Function 2: Calculate employee commission
CREATE OR REPLACE FUNCTION calculate_employee_commission(
    p_employee_id IN BIGINT,
    p_start_date IN TIMESTAMP,
    p_end_date IN TIMESTAMP
) RETURNS NUMERIC AS $$
DECLARE
    v_total_sales NUMERIC := 0;
    v_commission_pct NUMERIC;
    v_commission_amount NUMERIC := 0;
BEGIN
    -- Get employee commission percentage
    SELECT COALESCE(commission_pct, 0)
    INTO v_commission_pct
    FROM employees
    WHERE employee_id = p_employee_id;

    -- Calculate total sales for the period
    SELECT COALESCE(SUM(order_total), 0)
    INTO v_total_sales
    FROM orders
    WHERE employee_id = p_employee_id
      AND order_date BETWEEN p_start_date AND p_end_date
      AND order_status IN ('SHIPPED', 'DELIVERED');

    -- Calculate commission
    v_commission_amount := v_total_sales * v_commission_pct;

    RETURN v_commission_amount;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
    WHEN OTHERS THEN
        RETURN -1;
END;
$$ LANGUAGE plpgsql;

-- Schema for Order Management (replaces Oracle package)
CREATE SCHEMA IF NOT EXISTS order_management;

-- Function: Create order
CREATE OR REPLACE FUNCTION order_management.create_order(
    p_customer_id IN BIGINT,
    p_employee_id IN BIGINT,
    OUT p_order_id BIGINT
) AS $$
DECLARE
    v_order_number VARCHAR(50);
BEGIN
    -- Generate order number
    v_order_number := 'ORD-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' ||
                      nextval('orders_order_id_seq'::regclass)::TEXT;

    -- Insert order
    INSERT INTO orders (
        order_number, customer_id, employee_id,
        order_date, order_status
    ) VALUES (
        v_order_number, p_customer_id, p_employee_id,
        CURRENT_TIMESTAMP, 'PENDING'
    ) RETURNING order_id INTO p_order_id;

    COMMIT;
END;
$$ LANGUAGE plpgsql;

-- Function: Add order item
CREATE OR REPLACE FUNCTION order_management.add_order_item(
    p_order_id IN BIGINT,
    p_product_id IN BIGINT,
    p_quantity IN INTEGER,
    p_discount_pct IN NUMERIC DEFAULT 0
) RETURNS VOID AS $$
DECLARE
    v_unit_price NUMERIC;
BEGIN
    -- Get current product price
    SELECT unit_price
    INTO v_unit_price
    FROM products
    WHERE product_id = p_product_id;

    -- Insert order item
    INSERT INTO order_items (
        order_id, product_id, quantity, unit_price, discount_pct
    ) VALUES (
        p_order_id, p_product_id, p_quantity, v_unit_price, p_discount_pct
    );

    COMMIT;
END;
$$ LANGUAGE plpgsql;

-- Function: Get order status
CREATE OR REPLACE FUNCTION order_management.get_order_status(
    p_order_id IN BIGINT
) RETURNS VARCHAR AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT order_status
    INTO v_status
    FROM orders
    WHERE order_id = p_order_id;

    RETURN v_status;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'NOT_FOUND';
END;
$$ LANGUAGE plpgsql;

-- View: Order summary
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    o.order_number,
    o.order_date,
    c.customer_name,
    c.email AS customer_email,
    e.first_name || ' ' || e.last_name AS sales_rep,
    o.order_status,
    o.order_total,
    o.tax_amount,
    o.shipping_cost,
    (o.order_total + o.tax_amount + o.shipping_cost) AS grand_total,
    p.payment_status,
    s.shipment_status,
    s.tracking_number
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN employees e ON o.employee_id = e.employee_id
LEFT JOIN payments p ON o.order_id = p.order_id
LEFT JOIN shipments s ON o.order_id = s.order_id;

-- Materialized view: Sales by region
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_sales_by_region AS
SELECT
    r.region_name,
    r.region_code,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    SUM(o.order_total) AS total_sales,
    AVG(o.order_total) AS avg_order_value,
    MAX(o.order_date) AS last_order_date
FROM regions r
JOIN customers c ON r.region_id = c.region_id
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_status IN ('SHIPPED', 'DELIVERED')
GROUP BY r.region_name, r.region_code;

-- Create index on materialized view
CREATE INDEX idx_mv_sales_region_code ON mv_sales_by_region(region_code);

-- Function to refresh materialized view
CREATE OR REPLACE FUNCTION refresh_sales_by_region()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_sales_by_region;
    RAISE NOTICE 'Materialized view mv_sales_by_region refreshed at %', CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Helper function for hierarchical employee queries (replaces CONNECT BY)
CREATE OR REPLACE FUNCTION get_employee_hierarchy(p_root_employee_id BIGINT DEFAULT NULL)
RETURNS TABLE (
    employee_id BIGINT,
    first_name VARCHAR,
    last_name VARCHAR,
    manager_id BIGINT,
    level INTEGER,
    path TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE emp_hierarchy AS (
        -- Anchor: root employees (managers with no manager)
        SELECT
            e.employee_id,
            e.first_name,
            e.last_name,
            e.manager_id,
            1 AS level,
            e.employee_id::TEXT AS path
        FROM employees e
        WHERE (p_root_employee_id IS NULL AND e.manager_id IS NULL)
           OR (p_root_employee_id IS NOT NULL AND e.employee_id = p_root_employee_id)

        UNION ALL

        -- Recursive: employees reporting to the hierarchy
        SELECT
            e.employee_id,
            e.first_name,
            e.last_name,
            e.manager_id,
            eh.level + 1,
            eh.path || ' -> ' || e.employee_id::TEXT
        FROM employees e
        JOIN emp_hierarchy eh ON e.manager_id = eh.employee_id
    )
    SELECT * FROM emp_hierarchy ORDER BY level, employee_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON SCHEMA order_management IS 'Order management functions (converted from Oracle package)';
COMMENT ON FUNCTION get_employee_hierarchy IS 'Hierarchical employee query (replaces Oracle CONNECT BY)';
COMMENT ON FUNCTION refresh_sales_by_region IS 'Refresh sales by region materialized view';
