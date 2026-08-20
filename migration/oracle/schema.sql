-- =====================================================
-- StreamForge Phase 6 - Oracle Source Database Schema
-- Enterprise Sample Schema for Migration Testing
-- =====================================================

-- REGIONS Table
CREATE TABLE REGIONS (
    region_id NUMBER(10) PRIMARY KEY,
    region_name VARCHAR2(100) NOT NULL,
    region_code VARCHAR2(10) UNIQUE NOT NULL,
    country VARCHAR2(100),
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE
);

CREATE SEQUENCE regions_seq START WITH 1 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER regions_bir
BEFORE INSERT ON REGIONS
FOR EACH ROW
BEGIN
    IF :new.region_id IS NULL THEN
        :new.region_id := regions_seq.NEXTVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_regions_code ON REGIONS(region_code);

-- CUSTOMERS Table
CREATE TABLE CUSTOMERS (
    customer_id NUMBER(10) PRIMARY KEY,
    customer_name VARCHAR2(200) NOT NULL,
    email VARCHAR2(255) UNIQUE NOT NULL,
    phone VARCHAR2(20),
    address VARCHAR2(500),
    city VARCHAR2(100),
    postal_code VARCHAR2(20),
    region_id NUMBER(10),
    customer_status VARCHAR2(20) DEFAULT 'ACTIVE',
    credit_limit NUMBER(12,2) DEFAULT 5000.00,
    registration_date DATE DEFAULT SYSDATE,
    last_login_date TIMESTAMP,
    notes CLOB,
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_customers_region FOREIGN KEY (region_id) REFERENCES REGIONS(region_id),
    CONSTRAINT chk_customer_status CHECK (customer_status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED'))
);

CREATE SEQUENCE customers_seq START WITH 1000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER customers_bir
BEFORE INSERT ON CUSTOMERS
FOR EACH ROW
BEGIN
    IF :new.customer_id IS NULL THEN
        :new.customer_id := customers_seq.NEXTVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_customers_email ON CUSTOMERS(email);
CREATE INDEX idx_customers_region ON CUSTOMERS(region_id);
CREATE INDEX idx_customers_status ON CUSTOMERS(customer_status);

-- SUPPLIERS Table
CREATE TABLE SUPPLIERS (
    supplier_id NUMBER(10) PRIMARY KEY,
    supplier_name VARCHAR2(200) NOT NULL,
    contact_name VARCHAR2(100),
    email VARCHAR2(255) NOT NULL,
    phone VARCHAR2(20),
    address VARCHAR2(500),
    city VARCHAR2(100),
    postal_code VARCHAR2(20),
    region_id NUMBER(10),
    supplier_status VARCHAR2(20) DEFAULT 'ACTIVE',
    payment_terms VARCHAR2(50),
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_suppliers_region FOREIGN KEY (region_id) REFERENCES REGIONS(region_id),
    CONSTRAINT chk_supplier_status CHECK (supplier_status IN ('ACTIVE', 'INACTIVE'))
);

CREATE SEQUENCE suppliers_seq START WITH 2000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER suppliers_bir
BEFORE INSERT ON SUPPLIERS
FOR EACH ROW
BEGIN
    IF :new.supplier_id IS NULL THEN
        :new.supplier_id := suppliers_seq.NEXTVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_suppliers_email ON SUPPLIERS(email);
CREATE INDEX idx_suppliers_region ON SUPPLIERS(region_id);

-- PRODUCTS Table
CREATE TABLE PRODUCTS (
    product_id NUMBER(10) PRIMARY KEY,
    product_name VARCHAR2(200) NOT NULL,
    product_code VARCHAR2(50) UNIQUE NOT NULL,
    description CLOB,
    category VARCHAR2(100),
    supplier_id NUMBER(10),
    unit_price NUMBER(10,2) NOT NULL,
    cost_price NUMBER(10,2),
    stock_quantity NUMBER(10) DEFAULT 0,
    reorder_level NUMBER(10) DEFAULT 10,
    discontinued VARCHAR2(1) DEFAULT 'N',
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES SUPPLIERS(supplier_id),
    CONSTRAINT chk_unit_price CHECK (unit_price >= 0),
    CONSTRAINT chk_discontinued CHECK (discontinued IN ('Y', 'N'))
);

CREATE SEQUENCE products_seq START WITH 5000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER products_bir
BEFORE INSERT ON PRODUCTS
FOR EACH ROW
BEGIN
    IF :new.product_id IS NULL THEN
        :new.product_id := products_seq.NEXTVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_products_code ON PRODUCTS(product_code);
CREATE INDEX idx_products_supplier ON PRODUCTS(supplier_id);
CREATE INDEX idx_products_category ON PRODUCTS(category);

-- INVENTORY Table
CREATE TABLE INVENTORY (
    inventory_id NUMBER(10) PRIMARY KEY,
    product_id NUMBER(10) NOT NULL,
    warehouse_location VARCHAR2(100),
    quantity_on_hand NUMBER(10) DEFAULT 0,
    quantity_reserved NUMBER(10) DEFAULT 0,
    quantity_available NUMBER(10) DEFAULT 0,
    last_stock_check_date DATE,
    bin_location VARCHAR2(50),
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES PRODUCTS(product_id),
    CONSTRAINT chk_quantities CHECK (quantity_on_hand >= 0 AND quantity_reserved >= 0)
);

CREATE SEQUENCE inventory_seq START WITH 10000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER inventory_bir
BEFORE INSERT ON INVENTORY
FOR EACH ROW
BEGIN
    IF :new.inventory_id IS NULL THEN
        :new.inventory_id := inventory_seq.NEXTVAL;
    END IF;
    :new.quantity_available := :new.quantity_on_hand - :new.quantity_reserved;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_inventory_product ON INVENTORY(product_id);

-- EMPLOYEES Table
CREATE TABLE EMPLOYEES (
    employee_id NUMBER(10) PRIMARY KEY,
    first_name VARCHAR2(50) NOT NULL,
    last_name VARCHAR2(50) NOT NULL,
    email VARCHAR2(255) UNIQUE NOT NULL,
    phone VARCHAR2(20),
    hire_date DATE DEFAULT SYSDATE,
    job_title VARCHAR2(100),
    department VARCHAR2(100),
    manager_id NUMBER(10),
    salary NUMBER(10,2),
    commission_pct NUMBER(3,2),
    employee_status VARCHAR2(20) DEFAULT 'ACTIVE',
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_employees_manager FOREIGN KEY (manager_id) REFERENCES EMPLOYEES(employee_id),
    CONSTRAINT chk_employee_status CHECK (employee_status IN ('ACTIVE', 'INACTIVE', 'ON_LEAVE'))
);

CREATE SEQUENCE employees_seq START WITH 3000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER employees_bir
BEFORE INSERT ON EMPLOYEES
FOR EACH ROW
BEGIN
    IF :new.employee_id IS NULL THEN
        :new.employee_id := employees_seq.NEXTVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_employees_email ON EMPLOYEES(email);
CREATE INDEX idx_employees_manager ON EMPLOYEES(manager_id);
CREATE INDEX idx_employees_dept ON EMPLOYEES(department);

-- ORDERS Table
CREATE TABLE ORDERS (
    order_id NUMBER(10) PRIMARY KEY,
    order_number VARCHAR2(50) UNIQUE NOT NULL,
    customer_id NUMBER(10) NOT NULL,
    employee_id NUMBER(10),
    order_date DATE DEFAULT SYSDATE,
    required_date DATE,
    shipped_date DATE,
    order_status VARCHAR2(20) DEFAULT 'PENDING',
    order_total NUMBER(12,2) DEFAULT 0,
    tax_amount NUMBER(12,2) DEFAULT 0,
    shipping_cost NUMBER(10,2) DEFAULT 0,
    payment_method VARCHAR2(50),
    shipping_address VARCHAR2(500),
    billing_address VARCHAR2(500),
    notes CLOB,
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES CUSTOMERS(customer_id),
    CONSTRAINT fk_orders_employee FOREIGN KEY (employee_id) REFERENCES EMPLOYEES(employee_id),
    CONSTRAINT chk_order_status CHECK (order_status IN ('PENDING', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED'))
);

CREATE SEQUENCE orders_seq START WITH 20000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER orders_bir
BEFORE INSERT ON ORDERS
FOR EACH ROW
BEGIN
    IF :new.order_id IS NULL THEN
        :new.order_id := orders_seq.NEXTVAL;
    END IF;
    IF :new.order_number IS NULL THEN
        :new.order_number := 'ORD-' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '-' || orders_seq.CURRVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_orders_customer ON ORDERS(customer_id);
CREATE INDEX idx_orders_employee ON ORDERS(employee_id);
CREATE INDEX idx_orders_status ON ORDERS(order_status);
CREATE INDEX idx_orders_date ON ORDERS(order_date);

-- ORDER_ITEMS Table
CREATE TABLE ORDER_ITEMS (
    order_item_id NUMBER(10) PRIMARY KEY,
    order_id NUMBER(10) NOT NULL,
    product_id NUMBER(10) NOT NULL,
    quantity NUMBER(10) NOT NULL,
    unit_price NUMBER(10,2) NOT NULL,
    discount_pct NUMBER(5,2) DEFAULT 0,
    line_total NUMBER(12,2),
    created_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES ORDERS(order_id),
    CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES PRODUCTS(product_id),
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_unit_price CHECK (unit_price >= 0)
);

CREATE SEQUENCE order_items_seq START WITH 50000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER order_items_bir
BEFORE INSERT ON ORDER_ITEMS
FOR EACH ROW
BEGIN
    IF :new.order_item_id IS NULL THEN
        :new.order_item_id := order_items_seq.NEXTVAL;
    END IF;
    :new.line_total := :new.quantity * :new.unit_price * (1 - NVL(:new.discount_pct, 0) / 100);
    :new.created_date := SYSDATE;
END;
/

CREATE INDEX idx_order_items_order ON ORDER_ITEMS(order_id);
CREATE INDEX idx_order_items_product ON ORDER_ITEMS(product_id);

-- PAYMENTS Table
CREATE TABLE PAYMENTS (
    payment_id NUMBER(10) PRIMARY KEY,
    order_id NUMBER(10) NOT NULL,
    payment_date DATE DEFAULT SYSDATE,
    payment_amount NUMBER(12,2) NOT NULL,
    payment_method VARCHAR2(50) NOT NULL,
    transaction_id VARCHAR2(100) UNIQUE,
    payment_status VARCHAR2(20) DEFAULT 'PENDING',
    processor_response CLOB,
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES ORDERS(order_id),
    CONSTRAINT chk_payment_amount CHECK (payment_amount >= 0),
    CONSTRAINT chk_payment_status CHECK (payment_status IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED'))
);

CREATE SEQUENCE payments_seq START WITH 30000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER payments_bir
BEFORE INSERT ON PAYMENTS
FOR EACH ROW
BEGIN
    IF :new.payment_id IS NULL THEN
        :new.payment_id := payments_seq.NEXTVAL;
    END IF;
    IF :new.transaction_id IS NULL THEN
        :new.transaction_id := 'TXN-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || '-' || payments_seq.CURRVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_payments_order ON PAYMENTS(order_id);
CREATE INDEX idx_payments_status ON PAYMENTS(payment_status);
CREATE INDEX idx_payments_date ON PAYMENTS(payment_date);

-- SHIPMENTS Table
CREATE TABLE SHIPMENTS (
    shipment_id NUMBER(10) PRIMARY KEY,
    order_id NUMBER(10) NOT NULL,
    tracking_number VARCHAR2(100) UNIQUE,
    carrier VARCHAR2(100),
    shipment_date DATE DEFAULT SYSDATE,
    estimated_delivery_date DATE,
    actual_delivery_date DATE,
    shipment_status VARCHAR2(20) DEFAULT 'PREPARING',
    shipping_cost NUMBER(10,2),
    weight_kg NUMBER(8,2),
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_shipments_order FOREIGN KEY (order_id) REFERENCES ORDERS(order_id),
    CONSTRAINT chk_shipment_status CHECK (shipment_status IN ('PREPARING', 'SHIPPED', 'IN_TRANSIT', 'DELIVERED', 'RETURNED'))
);

CREATE SEQUENCE shipments_seq START WITH 40000 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER shipments_bir
BEFORE INSERT ON SHIPMENTS
FOR EACH ROW
BEGIN
    IF :new.shipment_id IS NULL THEN
        :new.shipment_id := shipments_seq.NEXTVAL;
    END IF;
    IF :new.tracking_number IS NULL THEN
        :new.tracking_number := 'TRK-' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '-' || shipments_seq.CURRVAL;
    END IF;
    :new.created_date := SYSDATE;
    :new.updated_date := SYSDATE;
END;
/

CREATE INDEX idx_shipments_order ON SHIPMENTS(order_id);
CREATE INDEX idx_shipments_tracking ON SHIPMENTS(tracking_number);
CREATE INDEX idx_shipments_status ON SHIPMENTS(shipment_status);

-- Create comments for documentation
COMMENT ON TABLE REGIONS IS 'Geographic regions for business operations';
COMMENT ON TABLE CUSTOMERS IS 'Customer master data';
COMMENT ON TABLE SUPPLIERS IS 'Supplier master data';
COMMENT ON TABLE PRODUCTS IS 'Product catalog';
COMMENT ON TABLE INVENTORY IS 'Product inventory tracking';
COMMENT ON TABLE EMPLOYEES IS 'Employee master data';
COMMENT ON TABLE ORDERS IS 'Sales orders';
COMMENT ON TABLE ORDER_ITEMS IS 'Line items for sales orders';
COMMENT ON TABLE PAYMENTS IS 'Payment transactions';
COMMENT ON TABLE SHIPMENTS IS 'Shipment tracking data';
