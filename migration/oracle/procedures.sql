-- =====================================================
-- StreamForge Phase 6 - Oracle Stored Procedures
-- Demonstrates PL/SQL features for conversion testing
-- =====================================================

-- Procedure 1: Calculate order totals
CREATE OR REPLACE PROCEDURE calculate_order_total(
    p_order_id IN NUMBER,
    p_total OUT NUMBER,
    p_tax OUT NUMBER,
    p_grand_total OUT NUMBER
) AS
    v_subtotal NUMBER := 0;
    v_tax_rate NUMBER := 0.08;
BEGIN
    -- Calculate subtotal from order items
    SELECT NVL(SUM(line_total), 0)
    INTO v_subtotal
    FROM ORDER_ITEMS
    WHERE order_id = p_order_id;

    -- Calculate tax
    p_tax := v_subtotal * v_tax_rate;
    p_total := v_subtotal;
    p_grand_total := v_subtotal + p_tax;

    -- Log the calculation
    DBMS_OUTPUT.PUT_LINE('Order ' || p_order_id || ' total: ' || p_grand_total);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_total := 0;
        p_tax := 0;
        p_grand_total := 0;
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20001, 'Error calculating order total: ' || SQLERRM);
END calculate_order_total;
/

-- Procedure 2: Update inventory after order
CREATE OR REPLACE PROCEDURE reserve_inventory(
    p_order_id IN NUMBER,
    p_success OUT VARCHAR2
) AS
    v_product_id NUMBER;
    v_quantity NUMBER;
    v_available NUMBER;

    CURSOR order_items_cur IS
        SELECT product_id, quantity
        FROM ORDER_ITEMS
        WHERE order_id = p_order_id;
BEGIN
    p_success := 'SUCCESS';

    -- Loop through all order items
    OPEN order_items_cur;
    LOOP
        FETCH order_items_cur INTO v_product_id, v_quantity;
        EXIT WHEN order_items_cur%NOTFOUND;

        -- Check available inventory
        SELECT quantity_available
        INTO v_available
        FROM INVENTORY
        WHERE product_id = v_product_id
        FOR UPDATE;

        IF v_available < v_quantity THEN
            p_success := 'INSUFFICIENT_INVENTORY';
            ROLLBACK;
            EXIT;
        END IF;

        -- Reserve the inventory
        UPDATE INVENTORY
        SET quantity_reserved = quantity_reserved + v_quantity,
            quantity_available = quantity_available - v_quantity,
            updated_date = SYSDATE
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
        RAISE_APPLICATION_ERROR(-20002, 'Error reserving inventory: ' || SQLERRM);
END reserve_inventory;
/

-- Procedure 3: Process payment
CREATE OR REPLACE PROCEDURE process_payment(
    p_order_id IN NUMBER,
    p_payment_amount IN NUMBER,
    p_payment_method IN VARCHAR2,
    p_payment_id OUT NUMBER
) AS
    v_order_total NUMBER;
    v_transaction_id VARCHAR2(100);
BEGIN
    -- Get order total
    SELECT order_total + tax_amount + shipping_cost
    INTO v_order_total
    FROM ORDERS
    WHERE order_id = p_order_id;

    -- Verify payment amount
    IF p_payment_amount < v_order_total THEN
        RAISE_APPLICATION_ERROR(-20003, 'Payment amount insufficient');
    END IF;

    -- Generate transaction ID
    v_transaction_id := 'TXN-' || p_payment_method || '-' ||
                        TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || '-' ||
                        TO_CHAR(payments_seq.NEXTVAL);

    -- Insert payment record
    INSERT INTO PAYMENTS (
        payment_id, order_id, payment_date, payment_amount,
        payment_method, transaction_id, payment_status
    ) VALUES (
        payments_seq.NEXTVAL, p_order_id, SYSDATE, p_payment_amount,
        p_payment_method, v_transaction_id, 'COMPLETED'
    ) RETURNING payment_id INTO p_payment_id;

    -- Update order status
    UPDATE ORDERS
    SET order_status = 'PROCESSING',
        updated_date = SYSDATE
    WHERE order_id = p_order_id;

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'Order not found');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20005, 'Error processing payment: ' || SQLERRM);
END process_payment;
/

-- Function 1: Get customer credit status
CREATE OR REPLACE FUNCTION get_customer_credit_status(
    p_customer_id IN NUMBER
) RETURN VARCHAR2 AS
    v_credit_limit NUMBER;
    v_total_outstanding NUMBER := 0;
    v_available_credit NUMBER;
    v_status VARCHAR2(50);
BEGIN
    -- Get customer credit limit
    SELECT credit_limit
    INTO v_credit_limit
    FROM CUSTOMERS
    WHERE customer_id = p_customer_id;

    -- Calculate outstanding orders (unpaid)
    SELECT NVL(SUM(o.order_total + o.tax_amount + o.shipping_cost), 0)
    INTO v_total_outstanding
    FROM ORDERS o
    LEFT JOIN PAYMENTS p ON o.order_id = p.order_id AND p.payment_status = 'COMPLETED'
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
END get_customer_credit_status;
/

-- Function 2: Calculate employee commission
CREATE OR REPLACE FUNCTION calculate_employee_commission(
    p_employee_id IN NUMBER,
    p_start_date IN DATE,
    p_end_date IN DATE
) RETURN NUMBER AS
    v_total_sales NUMBER := 0;
    v_commission_pct NUMBER;
    v_commission_amount NUMBER := 0;
BEGIN
    -- Get employee commission percentage
    SELECT NVL(commission_pct, 0)
    INTO v_commission_pct
    FROM EMPLOYEES
    WHERE employee_id = p_employee_id;

    -- Calculate total sales for the period
    SELECT NVL(SUM(order_total), 0)
    INTO v_total_sales
    FROM ORDERS
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
END calculate_employee_commission;
/

-- Package: Order Management
CREATE OR REPLACE PACKAGE order_management AS
    -- Package procedures and functions
    PROCEDURE create_order(
        p_customer_id IN NUMBER,
        p_employee_id IN NUMBER,
        p_order_id OUT NUMBER
    );

    PROCEDURE add_order_item(
        p_order_id IN NUMBER,
        p_product_id IN NUMBER,
        p_quantity IN NUMBER,
        p_discount_pct IN NUMBER DEFAULT 0
    );

    FUNCTION get_order_status(
        p_order_id IN NUMBER
    ) RETURN VARCHAR2;

END order_management;
/

CREATE OR REPLACE PACKAGE BODY order_management AS

    PROCEDURE create_order(
        p_customer_id IN NUMBER,
        p_employee_id IN NUMBER,
        p_order_id OUT NUMBER
    ) AS
        v_order_number VARCHAR2(50);
    BEGIN
        -- Generate order number
        v_order_number := 'ORD-' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '-' ||
                          TO_CHAR(orders_seq.NEXTVAL);

        -- Insert order
        INSERT INTO ORDERS (
            order_id, order_number, customer_id, employee_id,
            order_date, order_status
        ) VALUES (
            orders_seq.CURRVAL, v_order_number, p_customer_id, p_employee_id,
            SYSDATE, 'PENDING'
        ) RETURNING order_id INTO p_order_id;

        COMMIT;
    END create_order;

    PROCEDURE add_order_item(
        p_order_id IN NUMBER,
        p_product_id IN NUMBER,
        p_quantity IN NUMBER,
        p_discount_pct IN NUMBER DEFAULT 0
    ) AS
        v_unit_price NUMBER;
    BEGIN
        -- Get current product price
        SELECT unit_price
        INTO v_unit_price
        FROM PRODUCTS
        WHERE product_id = p_product_id;

        -- Insert order item
        INSERT INTO ORDER_ITEMS (
            order_id, product_id, quantity, unit_price, discount_pct
        ) VALUES (
            p_order_id, p_product_id, p_quantity, v_unit_price, p_discount_pct
        );

        COMMIT;
    END add_order_item;

    FUNCTION get_order_status(
        p_order_id IN NUMBER
    ) RETURN VARCHAR2 AS
        v_status VARCHAR2(20);
    BEGIN
        SELECT order_status
        INTO v_status
        FROM ORDERS
        WHERE order_id = p_order_id;

        RETURN v_status;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'NOT_FOUND';
    END get_order_status;

END order_management;
/

-- Create a view for reporting
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
FROM ORDERS o
JOIN CUSTOMERS c ON o.customer_id = c.customer_id
LEFT JOIN EMPLOYEES e ON o.employee_id = e.employee_id
LEFT JOIN PAYMENTS p ON o.order_id = p.order_id
LEFT JOIN SHIPMENTS s ON o.order_id = s.order_id;

-- Materialized view for performance
CREATE MATERIALIZED VIEW mv_sales_by_region
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    r.region_name,
    r.region_code,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    SUM(o.order_total) AS total_sales,
    AVG(o.order_total) AS avg_order_value,
    MAX(o.order_date) AS last_order_date
FROM REGIONS r
JOIN CUSTOMERS c ON r.region_id = c.region_id
JOIN ORDERS o ON c.customer_id = o.customer_id
WHERE o.order_status IN ('SHIPPED', 'DELIVERED')
GROUP BY r.region_name, r.region_code;

COMMIT;
