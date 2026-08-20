# StreamForge Phase 6 - Step-by-Step Migration Guide

## Overview

This guide provides detailed step-by-step instructions for executing a heterogeneous database migration from Oracle to Aurora PostgreSQL using AWS DMS and SCT.

---

## Prerequisites

### Required AWS Services
- [ ] AWS Account with appropriate permissions
- [ ] VPC with private subnets
- [ ] Aurora PostgreSQL cluster (from Phase 5)
- [ ] KMS key for encryption
- [ ] S3 bucket for reports
- [ ] SNS topic for notifications
- [ ] Secrets Manager for credentials

### Required Tools
- [ ] AWS CLI configured
- [ ] AWS Schema Conversion Tool (SCT) installed
- [ ] Terraform >= 1.5.0
- [ ] Oracle SQL*Plus client
- [ ] PostgreSQL psql client
- [ ] Python 3.12+ (for validation Lambda)

### Required Access
- [ ] Oracle source database credentials
- [ ] Aurora PostgreSQL credentials
- [ ] IAM permissions for DMS, Lambda, CloudWatch
- [ ] Network connectivity to databases

---

## Phase 1: Environment Setup (Day 1)

### Step 1.1: Provision Oracle Source Database

```bash
# Connect to Oracle
sqlplus / as sysdba

# Create schema
@migration/oracle/schema.sql

# Load seed data
@migration/oracle/seed.sql

# Create procedures
@migration/oracle/procedures.sql

# Verify installation
SELECT table_name FROM user_tables ORDER BY table_name;
```

**Expected Output:**
```
TABLE_NAME
----------
CUSTOMERS
EMPLOYEES
INVENTORY
ORDERS
ORDER_ITEMS
PAYMENTS
PRODUCTS
REGIONS
SHIPMENTS
SUPPLIERS
```

### Step 1.2: Store Oracle Credentials in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name streamforge-dev-oracle-source \
  --description "Oracle source database credentials for migration" \
  --secret-string '{
    "username": "system",
    "password": "YourOraclePassword",
    "host": "oracle.example.com",
    "port": 1521,
    "dbname": "ORCL",
    "engine": "oracle"
  }' \
  --kms-key-id alias/streamforge-dev \
  --region us-east-1
```

**Save the ARN for later:**
```bash
export ORACLE_SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id streamforge-dev-oracle-source \
  --query 'ARN' \
  --output text)

echo $ORACLE_SECRET_ARN
```

### Step 1.3: Enable Oracle Supplemental Logging

```sql
-- Required for CDC
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable for each table
ALTER TABLE regions ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE customers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE suppliers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE products ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE inventory ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE employees ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE order_items ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE payments ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE shipments ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Verify
SELECT supplemental_log_data_min FROM v$database;
```

---

## Phase 2: Schema Assessment (Day 2)

### Step 2.1: Install AWS Schema Conversion Tool

Download from: https://aws.amazon.com/dms/schema-conversion-tool/

### Step 2.2: Create SCT Project

1. Launch AWS SCT
2. Click **File → New Project**
3. Project Name: `StreamForge-Oracle-to-PostgreSQL`
4. Location: `C:\StreamForge\migration\sct\`

### Step 2.3: Connect to Oracle Source

1. Click **Connect to Oracle**
2. Enter connection details:
   - Server Name: `oracle.example.com`
   - Port: `1521`
   - Oracle SID: `ORCL`
   - Username: `system`
   - Password: `[from Secrets Manager]`
3. Click **Test Connection**
4. Click **OK**

### Step 2.4: Connect to PostgreSQL Target

1. Click **Connect to Amazon RDS for PostgreSQL**
2. Enter connection details:
   - Server Name: `[Aurora cluster endpoint]`
   - Port: `5432`
   - Database: `streamforge`
   - Username: `postgres`
   - Password: `[from Secrets Manager]`
3. Click **Test Connection**
4. Click **OK**

### Step 2.5: Generate Assessment Report

1. Right-click Oracle schema in left panel
2. Select **Create Report**
3. Wait for analysis to complete (2-5 minutes)
4. Review report:
   - Summary page shows conversion feasibility
   - Action Items tab lists manual changes needed
   - SQL tab shows problematic SQL

**Export Report:**
```
File → Save Report As → HTML
Location: migration/sct/assessment/assessment-report.html
```

### Step 2.6: Review Assessment Results

Expected findings:
- ✅ Tables: 100% automatic conversion
- ✅ Indexes: 100% automatic conversion
- ✅ Constraints: 100% automatic conversion
- ✅ Sequences: Converted to IDENTITY columns
- ⚠️ Triggers: Manual review required
- ⚠️ Procedures: Manual conversion needed
- ⚠️ Packages: Reorganize into schemas
- ⚠️ Materialized Views: Manual refresh logic

---

## Phase 3: Schema Conversion (Day 3)

### Step 3.1: Convert Schema with SCT

1. Select Oracle schema in left panel
2. Right-click → **Convert Schema**
3. Review conversion summary
4. Click **Yes** to proceed
5. Converted schema appears in right panel (PostgreSQL)

### Step 3.2: Review Converted Objects

**Tables:**
- Verify all 10 tables converted
- Check data types (NUMBER → BIGINT/NUMERIC)
- Verify constraints maintained

**Sequences:**
- Converted to `GENERATED BY DEFAULT AS IDENTITY`
- Starting values preserved

**Indexes:**
- All indexes converted
- Same columns indexed

**Triggers:**
- Converted to PostgreSQL functions
- Review logic for accuracy

### Step 3.3: Manual Remediation

**Convert Packages to Schemas:**

SCT doesn't convert Oracle packages. Manual steps:

```sql
-- Oracle Package: order_management
-- Converted to PostgreSQL schema: order_management

CREATE SCHEMA order_management;

CREATE FUNCTION order_management.create_order(...) ...;
CREATE FUNCTION order_management.add_order_item(...) ...;
CREATE FUNCTION order_management.get_order_status(...) ...;
```

**Update Function Syntax:**

Replace Oracle-specific functions:
- `NVL()` → `COALESCE()`
- `SYSDATE` → `CURRENT_TIMESTAMP`
- `TO_CHAR()` format strings (Oracle → PostgreSQL)
- `RAISE_APPLICATION_ERROR` → `RAISE EXCEPTION`

### Step 3.4: Export Converted Schema

```
Right-click PostgreSQL schema → Save as SQL
Location: migration/sct/converted_schema/postgresql_schema_sct.sql
```

**Merge with manually converted:**
```bash
cd migration/sct/converted_schema
cat postgresql_schema_sct.sql postgresql_procedures.sql > combined_schema.sql
```

---

## Phase 4: Deploy Target Schema (Day 4)

### Step 4.1: Connect to Aurora PostgreSQL

```bash
# Get Aurora endpoint
export AURORA_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier streamforge-dev-aurora \
  --query 'DBClusters[0].Endpoint' \
  --output text)

# Get credentials from Secrets Manager
export AURORA_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id streamforge-dev-aurora \
  --query 'SecretString' \
  --output text | jq -r '.password')

# Connect
psql -h $AURORA_ENDPOINT -U postgres -d streamforge
```

### Step 4.2: Deploy Schema

```bash
# Deploy tables, indexes, constraints
psql -h $AURORA_ENDPOINT -U postgres -d streamforge \
  -f migration/sct/converted_schema/postgresql_schema.sql

# Deploy functions and procedures
psql -h $AURORA_ENDPOINT -U postgres -d streamforge \
  -f migration/sct/converted_schema/postgresql_procedures.sql
```

### Step 4.3: Verify Schema Deployment

```sql
-- Verify tables
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Verify indexes
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- Verify functions
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
ORDER BY routine_name;

-- Verify foreign keys
SELECT 
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name;
```

**Expected:**
- 10 tables created
- 20+ indexes created
- 5+ stored procedures/functions
- 10+ foreign key constraints

---

## Phase 5: Deploy Migration Infrastructure (Day 5)

### Step 5.1: Prepare Terraform Configuration

```bash
cd migration/terraform

# Copy example configuration
cp dev.tfvars.example dev.tfvars

# Edit with your values
vim dev.tfvars
```

**Update variables:**
```hcl
vpc_id              = "vpc-xxxxx"
private_subnet_ids  = ["subnet-xxxxx", "subnet-yyyyy"]
oracle_source_secret_arn = "arn:aws:secretsmanager:..."
aurora_target_secret_arn = "arn:aws:secretsmanager:..."
aurora_cluster_endpoint  = "streamforge-dev-aurora..."
kms_key_arn         = "arn:aws:kms:..."
s3_reports_bucket   = "streamforge-dev-migration-reports-..."
sns_topic_arn       = "arn:aws:sns:..."
```

### Step 5.2: Initialize Terraform

```bash
terraform init
```

### Step 5.3: Plan Infrastructure

```bash
terraform plan -var-file=dev.tfvars -out=migration.tfplan
```

**Review planned resources:**
- DMS replication instance
- DMS subnet group
- DMS security group
- DMS source endpoint (Oracle)
- DMS target endpoint (Aurora)
- DMS replication task
- Validation Lambda function
- Lambda security group
- CloudWatch log groups
- CloudWatch dashboard
- CloudWatch alarms
- EventBridge rules
- IAM roles and policies

### Step 5.4: Apply Infrastructure

```bash
terraform apply migration.tfplan
```

**Deployment time:** 10-15 minutes

### Step 5.5: Verify Infrastructure

```bash
# Check DMS replication instance
aws dms describe-replication-instances \
  --filters "Name=replication-instance-id,Values=streamforge-dev-dms-instance"

# Check endpoints
aws dms describe-endpoints \
  --filters "Name=endpoint-id,Values=streamforge-dev-oracle-source"

aws dms describe-endpoints \
  --filters "Name=endpoint-id,Values=streamforge-dev-aurora-target"

# Check replication task
aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=streamforge-dev-replication-task"

# Check validation Lambda
aws lambda get-function \
  --function-name streamforge-dev-migration-validation
```

### Step 5.6: Test Endpoints

```bash
# Test Oracle source endpoint
aws dms test-connection \
  --replication-instance-arn <instance-arn> \
  --endpoint-arn <oracle-endpoint-arn>

# Test Aurora target endpoint
aws dms test-connection \
  --replication-instance-arn <instance-arn> \
  --endpoint-arn <aurora-endpoint-arn>
```

**Wait for status:** `successful`

---

## Phase 6: Execute Full Load Migration (Day 6)

### Step 6.1: Get Record Counts from Oracle

```sql
-- Run on Oracle
SELECT 'regions' as table_name, COUNT(*) as row_count FROM regions UNION ALL
SELECT 'customers', COUNT(*) FROM customers UNION ALL
SELECT 'suppliers', COUNT(*) FROM suppliers UNION ALL
SELECT 'products', COUNT(*) FROM products UNION ALL
SELECT 'inventory', COUNT(*) FROM inventory UNION ALL
SELECT 'employees', COUNT(*) FROM employees UNION ALL
SELECT 'orders', COUNT(*) FROM orders UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items UNION ALL
SELECT 'payments', COUNT(*) FROM payments UNION ALL
SELECT 'shipments', COUNT(*) FROM shipments;
```

**Save results for validation**

### Step 6.2: Start Replication Task

```bash
# Get task ARN
export TASK_ARN=$(aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=streamforge-dev-replication-task" \
  --query 'ReplicationTasks[0].ReplicationTaskArn' \
  --output text)

# Start task
aws dms start-replication-task \
  --replication-task-arn $TASK_ARN \
  --start-replication-task-type start-replication

echo "Migration started at $(date)"
```

### Step 6.3: Monitor Progress

**CloudWatch Dashboard:**
```
https://console.aws.amazon.com/cloudwatch/home#dashboards:name=streamforge-dev-migration-dashboard
```

**CLI Monitoring:**
```bash
# Watch task status
watch -n 10 "aws dms describe-replication-tasks \
  --filters \"Name=replication-task-arn,Values=$TASK_ARN\" \
  --query 'ReplicationTasks[0].[Status,ReplicationTaskStats]' \
  --output table"

# View logs
aws logs tail /aws/dms/tasks/streamforge-dev-replication-task --follow
```

**Key Metrics:**
- FullLoadThroughputRowsSource
- FullLoadThroughputRowsTarget
- FullLoadProgressPercent

**Expected Duration:** 5-30 minutes (depending on data volume)

### Step 6.4: Verify Full Load Completion

```bash
# Check task status
aws dms describe-replication-tasks \
  --replication-task-arn $TASK_ARN \
  --query 'ReplicationTasks[0].Status' \
  --output text
```

**Expected Status:** `running` (CDC mode after full load)

---

## Phase 7: Change Data Capture Testing (Day 7)

### Step 7.1: Verify CDC is Active

```bash
# Check CDC latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/DMS \
  --metric-name CDCLatencySource \
  --dimensions Name=ReplicationTaskIdentifier,Value=streamforge-dev-replication-task \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

**Expected Latency:** < 60 seconds

### Step 7.2: Test INSERT Replication

```sql
-- On Oracle
INSERT INTO customers (customer_name, email, region_id, customer_status)
VALUES ('CDC Test Customer', 'cdc.test@streamforge.com', 1, 'ACTIVE');
COMMIT;

-- Note the customer_id
SELECT customer_id, customer_name, email 
FROM customers 
WHERE email = 'cdc.test@streamforge.com';
```

**Wait 30-60 seconds**

```sql
-- On PostgreSQL
SELECT customer_id, customer_name, email, created_date
FROM customers
WHERE email = 'cdc.test@streamforge.com';
```

**Verify record replicated**

### Step 7.3: Test UPDATE Replication

```sql
-- On Oracle
UPDATE customers
SET customer_name = 'CDC Test Customer UPDATED'
WHERE email = 'cdc.test@streamforge.com';
COMMIT;
```

**Wait 30-60 seconds**

```sql
-- On PostgreSQL
SELECT customer_name, updated_date
FROM customers
WHERE email = 'cdc.test@streamforge.com';
```

**Verify update replicated**

### Step 7.4: Test DELETE Replication

```sql
-- On Oracle
DELETE FROM customers
WHERE email = 'cdc.test@streamforge.com';
COMMIT;
```

**Wait 30-60 seconds**

```sql
-- On PostgreSQL
SELECT COUNT(*)
FROM customers
WHERE email = 'cdc.test@streamforge.com';
```

**Expected:** 0 rows (deleted)

---

## Phase 8: Validation (Day 8)

### Step 8.1: Automatic Validation

Validation runs automatically after full load via EventBridge trigger.

**Check validation execution:**
```bash
# Get Lambda logs
aws logs tail /aws/lambda/streamforge-dev-migration-validation --follow

# Check recent execution
aws lambda list-invocations \
  --function-name streamforge-dev-migration-validation \
  --max-items 1
```

### Step 8.2: Manual Validation

```bash
# Invoke validation Lambda
aws lambda invoke \
  --function-name streamforge-dev-migration-validation \
  --payload '{
    "migration_id": "manual-validation-001",
    "oracle_row_counts": {
      "regions": 5,
      "customers": 8,
      "suppliers": 4,
      "products": 10,
      "inventory": 10,
      "employees": 5,
      "orders": 6,
      "order_items": 14,
      "payments": 4,
      "shipments": 2
    }
  }' \
  response.json

# View response
cat response.json | jq '.'
```

### Step 8.3: Review Validation Report

```bash
# Download report from S3
aws s3 cp s3://streamforge-dev-migration-reports/migration_reports/manual-validation-001/ . --recursive

# View report
cat validation_*.json | jq '.'
```

**Check overall status:**
```bash
cat validation_*.json | jq '.overall_status'
```

**Expected:** `"PASS"`

### Step 8.4: Run Manual SQL Validation

```bash
# Run validation queries
psql -h $AURORA_ENDPOINT -U postgres -d streamforge \
  -f migration/validation/sql/validation_queries.sql > validation_results.txt

# Review results
less validation_results.txt
```

---

## Phase 9: Performance Optimization (Day 9)

### Step 9.1: Update Statistics

```sql
-- On PostgreSQL
ANALYZE regions;
ANALYZE customers;
ANALYZE suppliers;
ANALYZE products;
ANALYZE inventory;
ANALYZE employees;
ANALYZE orders;
ANALYZE order_items;
ANALYZE payments;
ANALYZE shipments;
```

### Step 9.2: Refresh Materialized Views

```sql
SELECT refresh_sales_by_region();

-- Or manually
REFRESH MATERIALIZED VIEW mv_sales_by_region;
```

### Step 9.3: Monitor Performance

```sql
-- Check table sizes
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check index usage
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

---

## Phase 10: Cutover Planning (Day 10)

### Step 10.1: Document Current State

```bash
# Create cutover document
cat > cutover_plan.md <<EOF
# StreamForge Migration Cutover Plan

## Current State
- Migration Date: $(date)
- Oracle Version: 19c
- PostgreSQL Version: 15.x
- CDC Latency: < 60 seconds
- Validation Status: PASS
- Application Status: Running on Oracle

## Cutover Steps
1. Stop application writes (T-0h)
2. Wait for CDC to catch up (< 10s latency)
3. Run final validation
4. Switch application to PostgreSQL
5. Monitor for 1 hour
6. Set Oracle to read-only

## Rollback Plan
1. Stop application
2. Switch back to Oracle
3. Investigate issues
4. Resume CDC from checkpoint

## Success Criteria
- All validation checks PASS
- Application functions normally
- Performance meets SLAs
- No data loss
EOF
```

### Step 10.2: Schedule Cutover Window

**Recommended:** Low-traffic period (weekend/evening)

**Estimated Downtime:** 15-30 minutes

### Step 10.3: Prepare Rollback

```bash
# Take Aurora snapshot before cutover
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier streamforge-dev-aurora \
  --db-cluster-snapshot-identifier streamforge-pre-cutover-$(date +%Y%m%d)

# Document Oracle restore procedure
# Keep Oracle running read-only for 7 days
```

---

## Troubleshooting

See main [README.md](README.md#troubleshooting) for common issues and solutions.

---

## Success Checklist

- [ ] Oracle source provisioned and populated
- [ ] Supplemental logging enabled
- [ ] SCT assessment completed
- [ ] Schema converted and deployed to Aurora
- [ ] Migration infrastructure deployed with Terraform
- [ ] Endpoints tested successfully
- [ ] Full load completed
- [ ] CDC operational and tested
- [ ] Validation passed (all checks)
- [ ] Performance optimized
- [ ] Cutover plan documented
- [ ] Rollback procedure tested
- [ ] Monitoring dashboard configured
- [ ] Team trained on new system

---

## Next Steps

After successful migration:
1. Monitor Aurora performance for 7 days
2. Decommission Oracle source
3. Update application documentation
4. Archive migration reports
5. Conduct retrospective meeting

**Congratulations on completing the migration!** 🎉
