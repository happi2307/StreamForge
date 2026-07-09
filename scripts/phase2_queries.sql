CREATE EXTERNAL TABLE IF NOT EXISTS streamforge_clean_db.customers (
  customer_id BIGINT,
  name STRING,
  email STRING,
  sales BIGINT
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
WITH SERDEPROPERTIES (
  'field.delim' = ','
)
STORED AS TEXTFILE
LOCATION 's3://streamforge-clean-<account-id>-<region>/'
TBLPROPERTIES (
  'skip.header.line.count' = '1'
);

SELECT
  customer_id,
  name,
  email,
  sales
FROM streamforge_clean_db.customers
ORDER BY customer_id;

SELECT
  COUNT(*) AS total_customers,
  SUM(sales) AS total_sales,
  AVG(sales) AS average_sales
FROM streamforge_clean_db.customers;
