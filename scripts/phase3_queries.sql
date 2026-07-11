SELECT
  source_filename,
  COUNT(*) AS row_count,
  SUM(sales) AS total_sales
FROM streamforge_clean_db.customers_curated
GROUP BY source_filename
ORDER BY source_filename;

SELECT
  sales_category,
  COUNT(*) AS customer_count,
  SUM(sales) AS category_sales
FROM streamforge_clean_db.customers_curated
WHERE year = '<yyyy>'
  AND month = '<mm>'
  AND day = '<dd>'
GROUP BY sales_category
ORDER BY sales_category;

SELECT
  customer_id,
  name,
  email,
  sales,
  sales_category,
  source_filename,
  ingestion_timestamp
FROM streamforge_clean_db.customers_curated
WHERE year = '<yyyy>'
  AND month = '<mm>'
  AND day = '<dd>'
ORDER BY sales DESC
LIMIT 10;
