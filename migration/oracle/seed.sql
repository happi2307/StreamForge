-- =====================================================
-- StreamForge Phase 6 - Oracle Seed Data
-- Realistic Enterprise Test Data for Migration
-- =====================================================

-- Insert REGIONS
INSERT INTO REGIONS (region_id, region_name, region_code, country) VALUES (1, 'North America East', 'NAE', 'USA');
INSERT INTO REGIONS (region_id, region_name, region_code, country) VALUES (2, 'North America West', 'NAW', 'USA');
INSERT INTO REGIONS (region_id, region_name, region_code, country) VALUES (3, 'Europe Central', 'EUC', 'Germany');
INSERT INTO REGIONS (region_id, region_name, region_code, country) VALUES (4, 'Europe West', 'EUW', 'UK');
INSERT INTO REGIONS (region_id, region_name, region_code, country) VALUES (5, 'Asia Pacific', 'APAC', 'Singapore');
COMMIT;

-- Insert EMPLOYEES (managers first, then reports)
INSERT INTO EMPLOYEES (employee_id, first_name, last_name, email, phone, hire_date, job_title, department, manager_id, salary, commission_pct, employee_status)
VALUES (3001, 'Sarah', 'Johnson', 'sarah.johnson@streamforge.com', '555-0101', DATE '2020-01-15', 'VP of Sales', 'Sales', NULL, 150000.00, 0.05, 'ACTIVE');

INSERT INTO EMPLOYEES (employee_id, first_name, last_name, email, phone, hire_date, job_title, department, manager_id, salary, commission_pct, employee_status)
VALUES (3002, 'Michael', 'Chen', 'michael.chen@streamforge.com', '555-0102', DATE '2020-03-20', 'Sales Manager', 'Sales', 3001, 95000.00, 0.10, 'ACTIVE');

INSERT INTO EMPLOYEES (employee_id, first_name, last_name, email, phone, hire_date, job_title, department, manager_id, salary, commission_pct, employee_status)
VALUES (3003, 'Emily', 'Rodriguez', 'emily.rodriguez@streamforge.com', '555-0103', DATE '2021-02-10', 'Sales Representative', 'Sales', 3002, 65000.00, 0.15, 'ACTIVE');

INSERT INTO EMPLOYEES (employee_id, first_name, last_name, email, phone, hire_date, job_title, department, manager_id, salary, commission_pct, employee_status)
VALUES (3004, 'David', 'Kim', 'david.kim@streamforge.com', '555-0104', DATE '2021-05-01', 'Sales Representative', 'Sales', 3002, 62000.00, 0.15, 'ACTIVE');

INSERT INTO EMPLOYEES (employee_id, first_name, last_name, email, phone, hire_date, job_title, department, manager_id, salary, commission_pct, employee_status)
VALUES (3005, 'Jessica', 'Brown', 'jessica.brown@streamforge.com', '555-0105', DATE '2022-01-10', 'Customer Support Lead', 'Support', 3001, 70000.00, NULL, 'ACTIVE');
COMMIT;

-- Insert SUPPLIERS
INSERT INTO SUPPLIERS (supplier_id, supplier_name, contact_name, email, phone, address, city, postal_code, region_id, supplier_status, payment_terms)
VALUES (2001, 'TechSupply International', 'Robert Wilson', 'robert@techsupply.com', '555-1001', '123 Industrial Blvd', 'New York', '10001', 1, 'ACTIVE', 'NET30');

INSERT INTO SUPPLIERS (supplier_id, supplier_name, contact_name, email, phone, address, city, postal_code, region_id, supplier_status, payment_terms)
VALUES (2002, 'Global Components Ltd', 'Lisa Anderson', 'lisa@globalcomp.com', '555-1002', '456 Commerce Street', 'Los Angeles', '90001', 2, 'ACTIVE', 'NET45');

INSERT INTO SUPPLIERS (supplier_id, supplier_name, contact_name, email, phone, address, city, postal_code, region_id, supplier_status, payment_terms)
VALUES (2003, 'EuroTech GmbH', 'Hans Mueller', 'hans@eurotech.de', '+49-555-1003', 'Hauptstrasse 789', 'Berlin', '10115', 3, 'ACTIVE', 'NET30');

INSERT INTO SUPPLIERS (supplier_id, supplier_name, contact_name, email, phone, address, city, postal_code, region_id, supplier_status, payment_terms)
VALUES (2004, 'Asia Electronics Co', 'Li Wei', 'liwei@asiaelec.sg', '+65-555-1004', '88 Innovation Drive', 'Singapore', '138639', 5, 'ACTIVE', 'NET60');
COMMIT;

-- Insert PRODUCTS
INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5001, 'Laptop Pro 15"', 'LAP-PRO-15', 'High-performance business laptop with 16GB RAM', 'Computers', 2001, 1299.99, 899.99, 45, 10);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5002, 'Wireless Mouse Premium', 'MOU-PREM-01', 'Ergonomic wireless mouse with 6 buttons', 'Accessories', 2002, 49.99, 25.99, 150, 30);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5003, 'Mechanical Keyboard RGB', 'KEY-RGB-MECH', 'RGB backlit mechanical keyboard with cherry switches', 'Accessories', 2002, 129.99, 75.99, 80, 20);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5004, '27" 4K Monitor', 'MON-4K-27', 'Professional 4K IPS display with HDR', 'Displays', 2003, 599.99, 399.99, 35, 10);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5005, 'USB-C Docking Station', 'DOCK-USBC-PRO', 'Universal USB-C docking station with dual display support', 'Accessories', 2001, 199.99, 129.99, 60, 15);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5006, 'Wireless Headset', 'HEAD-WIRE-BT', 'Bluetooth noise-cancelling wireless headset', 'Audio', 2004, 179.99, 99.99, 120, 25);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5007, 'External SSD 1TB', 'SSD-EXT-1TB', 'Portable external SSD with USB 3.2 Gen 2', 'Storage', 2004, 149.99, 89.99, 90, 20);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5008, 'Webcam HD Pro', 'CAM-HD-PRO', 'Full HD 1080p webcam with autofocus', 'Accessories', 2003, 89.99, 49.99, 110, 25);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5009, 'USB Hub 7-Port', 'HUB-USB-7P', '7-port powered USB 3.0 hub', 'Accessories', 2002, 39.99, 19.99, 200, 40);

INSERT INTO PRODUCTS (product_id, product_name, product_code, description, category, supplier_id, unit_price, cost_price, stock_quantity, reorder_level)
VALUES (5010, 'Laptop Stand Aluminum', 'STAND-LAP-ALU', 'Adjustable aluminum laptop stand', 'Accessories', 2001, 59.99, 29.99, 75, 20);
COMMIT;

-- Insert INVENTORY
INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5001, 'Warehouse A', 45, 5, 'A-12-03', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5002, 'Warehouse B', 150, 20, 'B-05-11', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5003, 'Warehouse B', 80, 10, 'B-06-08', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5004, 'Warehouse A', 35, 5, 'A-15-02', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5005, 'Warehouse A', 60, 8, 'A-10-07', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5006, 'Warehouse B', 120, 15, 'B-08-04', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5007, 'Warehouse C', 90, 12, 'C-03-09', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5008, 'Warehouse B', 110, 18, 'B-07-06', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5009, 'Warehouse C', 200, 30, 'C-01-12', DATE '2026-08-15');

INSERT INTO INVENTORY (product_id, warehouse_location, quantity_on_hand, quantity_reserved, bin_location, last_stock_check_date)
VALUES (5010, 'Warehouse A', 75, 10, 'A-11-05', DATE '2026-08-15');
COMMIT;

-- Insert CUSTOMERS
INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1001, 'Acme Corporation', 'contact@acmecorp.com', '555-2001', '100 Business Park Dr', 'Boston', '02101', 1, 'ACTIVE', 50000.00, DATE '2023-01-15', 'Premier enterprise customer');

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1002, 'Tech Innovations LLC', 'info@techinno.com', '555-2002', '250 Silicon Valley Blvd', 'San Francisco', '94102', 2, 'ACTIVE', 75000.00, DATE '2023-02-20', 'Long-term partnership');

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1003, 'Global Solutions GmbH', 'sales@globalsol.de', '+49-555-2003', 'Friedrichstrasse 50', 'Berlin', '10117', 3, 'ACTIVE', 60000.00, DATE '2023-03-10', NULL);

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1004, 'Digital Ventures Ltd', 'orders@digitalvent.co.uk', '+44-555-2004', '45 Oxford Street', 'London', 'W1D 2DZ', 4, 'ACTIVE', 40000.00, DATE '2023-05-12', NULL);

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1005, 'Pacific Trading Co', 'info@pacifictrade.sg', '+65-555-2005', '120 Marina Bay', 'Singapore', '018981', 5, 'ACTIVE', 55000.00, DATE '2023-06-01', 'Growing account');

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1006, 'Midwest Manufacturing', 'purchasing@midwestmfg.com', '555-2006', '500 Industrial Way', 'Chicago', '60601', 1, 'ACTIVE', 45000.00, DATE '2023-07-15', NULL);

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1007, 'Coastal Enterprises', 'orders@coastalent.com', '555-2007', '800 Harbor Drive', 'Seattle', '98101', 2, 'ACTIVE', 30000.00, DATE '2024-01-20', NULL);

INSERT INTO CUSTOMERS (customer_id, customer_name, email, phone, address, city, postal_code, region_id, customer_status, credit_limit, registration_date, notes)
VALUES (1008, 'SmartTech Industries', 'contact@smarttech.com', '555-2008', '350 Innovation Parkway', 'Austin', '78701', 1, 'SUSPENDED', 25000.00, DATE '2024-03-05', 'Payment issues - resolved');
COMMIT;

-- Insert ORDERS
INSERT INTO ORDERS (order_id, order_number, customer_id, employee_id, order_date, required_date, shipped_date, order_status, payment_method, shipping_address, billing_address)
VALUES (20001, 'ORD-20260801-001', 1001, 3003, DATE '2026-08-01', DATE '2026-08-08', DATE '2026-08-03', 'DELIVERED', 'CREDIT_CARD', '100 Business Park Dr, Boston, MA 02101', '100 Business Park Dr, Boston, MA 02101');

INSERT INTO ORDERS (order_id, order_number, customer_id, employee_id, order_date, required_date, shipped_date, order_status, payment_method, shipping_address, billing_address)
VALUES (20002, 'ORD-20260805-002', 1002, 3004, DATE '2026-08-05', DATE '2026-08-12', DATE '2026-08-07', 'SHIPPED', 'PURCHASE_ORDER', '250 Silicon Valley Blvd, San Francisco, CA 94102', '250 Silicon Valley Blvd, San Francisco, CA 94102');

INSERT INTO ORDERS (order_id, order_number, customer_id, employee_id, order_date, required_date, order_status, payment_method, shipping_address, billing_address)
VALUES (20003, 'ORD-20260810-003', 1003, 3003, DATE '2026-08-10', DATE '2026-08-20', 'PROCESSING', 'WIRE_TRANSFER', 'Friedrichstrasse 50, Berlin, 10117, Germany', 'Friedrichstrasse 50, Berlin, 10117, Germany');

INSERT INTO ORDERS (order_id, order_number, customer_id, employee_id, order_date, required_date, order_status, payment_method, shipping_address, billing_address)
VALUES (20004, 'ORD-20260812-004', 1004, 3004, DATE '2026-08-12', DATE '2026-08-19', 'PROCESSING', 'CREDIT_CARD', '45 Oxford Street, London, W1D 2DZ, UK', '45 Oxford Street, London, W1D 2DZ, UK');

INSERT INTO ORDERS (order_id, order_number, customer_id, employee_id, order_date, required_date, order_status, payment_method, shipping_address, billing_address)
VALUES (20005, 'ORD-20260815-005', 1005, 3003, DATE '2026-08-15', DATE '2026-08-25', 'PENDING', 'PURCHASE_ORDER', '120 Marina Bay, Singapore, 018981', '120 Marina Bay, Singapore, 018981');

INSERT INTO ORDERS (order_id, order_number, customer_id, employee_id, order_date, required_date, order_status, payment_method, shipping_address, billing_address)
VALUES (20006, 'ORD-20260817-006', 1006, 3004, DATE '2026-08-17', DATE '2026-08-24', 'PENDING', 'NET30', '500 Industrial Way, Chicago, IL 60601', '500 Industrial Way, Chicago, IL 60601');
COMMIT;

-- Insert ORDER_ITEMS
INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20001, 5001, 10, 1299.99, 5.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20001, 5004, 10, 599.99, 5.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20001, 5002, 20, 49.99, 10.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20002, 5001, 25, 1299.99, 10.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20002, 5005, 25, 199.99, 10.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20002, 5006, 30, 179.99, 8.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20003, 5004, 15, 599.99, 5.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20003, 5003, 15, 129.99, 5.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20004, 5007, 50, 149.99, 12.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20004, 5008, 50, 89.99, 12.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20005, 5001, 20, 1299.99, 8.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20005, 5004, 20, 599.99, 8.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20006, 5009, 100, 39.99, 15.00);

INSERT INTO ORDER_ITEMS (order_id, product_id, quantity, unit_price, discount_pct)
VALUES (20006, 5010, 50, 59.99, 15.00);
COMMIT;

-- Update order totals based on line items
UPDATE ORDERS o
SET order_total = (
    SELECT SUM(line_total)
    FROM ORDER_ITEMS
    WHERE order_id = o.order_id
),
tax_amount = (
    SELECT SUM(line_total) * 0.08
    FROM ORDER_ITEMS
    WHERE order_id = o.order_id
),
shipping_cost = 50.00;
COMMIT;

-- Insert PAYMENTS
INSERT INTO PAYMENTS (payment_id, order_id, payment_date, payment_amount, payment_method, transaction_id, payment_status)
VALUES (30001, 20001, DATE '2026-08-01', 19949.02, 'CREDIT_CARD', 'TXN-CC-20260801-001', 'COMPLETED');

INSERT INTO PAYMENTS (payment_id, order_id, payment_date, payment_amount, payment_method, transaction_id, payment_status)
VALUES (30002, 20002, DATE '2026-08-05', 39487.30, 'PURCHASE_ORDER', 'TXN-PO-20260805-002', 'COMPLETED');

INSERT INTO PAYMENTS (payment_id, order_id, payment_date, payment_amount, payment_method, transaction_id, payment_status, processor_response)
VALUES (30003, 20003, DATE '2026-08-10', 11809.35, 'WIRE_TRANSFER', 'TXN-WIRE-20260810-003', 'PENDING', 'Awaiting wire transfer confirmation');

INSERT INTO PAYMENTS (payment_id, order_id, payment_date, payment_amount, payment_method, transaction_id, payment_status)
VALUES (30004, 20004, DATE '2026-08-12', 11443.90, 'CREDIT_CARD', 'TXN-CC-20260812-004', 'COMPLETED');
COMMIT;

-- Insert SHIPMENTS
INSERT INTO SHIPMENTS (shipment_id, order_id, tracking_number, carrier, shipment_date, estimated_delivery_date, actual_delivery_date, shipment_status, shipping_cost, weight_kg)
VALUES (40001, 20001, 'TRK-UPS-20260803-001', 'UPS', DATE '2026-08-03', DATE '2026-08-08', DATE '2026-08-07', 'DELIVERED', 50.00, 85.5);

INSERT INTO SHIPMENTS (shipment_id, order_id, tracking_number, carrier, shipment_date, estimated_delivery_date, shipment_status, shipping_cost, weight_kg)
VALUES (40002, 20002, 'TRK-FEDEX-20260807-002', 'FedEx', DATE '2026-08-07', DATE '2026-08-12', 'IN_TRANSIT', 75.00, 120.3);
COMMIT;

-- Statistics
SELECT 'Data Load Summary:' AS info FROM dual;
SELECT 'REGIONS' AS table_name, COUNT(*) AS row_count FROM REGIONS UNION ALL
SELECT 'CUSTOMERS', COUNT(*) FROM CUSTOMERS UNION ALL
SELECT 'SUPPLIERS', COUNT(*) FROM SUPPLIERS UNION ALL
SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS UNION ALL
SELECT 'INVENTORY', COUNT(*) FROM INVENTORY UNION ALL
SELECT 'EMPLOYEES', COUNT(*) FROM EMPLOYEES UNION ALL
SELECT 'ORDERS', COUNT(*) FROM ORDERS UNION ALL
SELECT 'ORDER_ITEMS', COUNT(*) FROM ORDER_ITEMS UNION ALL
SELECT 'PAYMENTS', COUNT(*) FROM PAYMENTS UNION ALL
SELECT 'SHIPMENTS', COUNT(*) FROM SHIPMENTS;
