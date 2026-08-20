# StreamForge Phase 6: Enterprise Database Modernization & Migration

## Overview

Phase 6 transforms StreamForge into a complete enterprise modernization platform by implementing an end-to-end heterogeneous database migration workflow from **Oracle Database** to **Amazon Aurora PostgreSQL**.

This phase demonstrates:
- Oracle schema assessment and conversion
- Automated schema migration with AWS SCT
- Full load and Change Data Capture (CDC) replication with AWS DMS
- Comprehensive validation framework
- Migration monitoring and reporting
- Production-ready infrastructure automation

---

## Architecture

```
┌─────────────────┐
│ Oracle Database │
│   (Source)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   AWS SCT       │
│  Assessment     │
│  Conversion     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PostgreSQL      │
│ Schema DDL      │
└─────────────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────┐
│   AWS DMS       │──────▶│   Aurora     │
│ Replication     │      │ PostgreSQL   │
│  - Full Load    │      │  (Target)    │
│  - CDC          │      └──────┬───────┘
└────────┬────────┘             │
         │                      │
         ▼                      ▼
┌─────────────────┐      ┌──────────────┐
│  Validation     │      │  Migration   │
│  Lambda         │──────▶│  Reports     │
│                 │      │  (S3)        │
└────────┬────────┘      └──────────────┘
         │
         ▼
┌─────────────────┐
│  CloudWatch     │
│  Dashboard      │
│  Alarms         │
└─────────────────┘
```

---

## Components

### 1. Oracle Source Database

**Location:** `oracle/`

Enterprise-grade sample schema with:
- 10 tables (REGIONS, CUSTOMERS, SUPPLIERS, PRODUCTS, INVENTORY, EMPLOYEES, ORDERS, ORDER_ITEMS, PAYMENTS, SHIPMENTS)
- Primary keys, foreign keys, indexes
- Sequences and triggers
- Stored procedures and functions
- PL/SQL packages
- Views and materialized views
- Realistic business data

**Files:**
- `schema.sql` - Complete DDL for all tables
- `seed.sql` - Sample data (100+ records)
- `procedures.sql` - Stored procedures, functions, packages

### 2. AWS Schema Conversion Tool (SCT)

**Location:** `sct/`

AWS SCT performs:
- Automated schema assessment
- Complexity analysis
- Schema conversion (Oracle → PostgreSQL)
- Object compatibility reporting

**Output:**
- `assessment/` - SCT assessment reports
- `reports/` - Conversion reports, unsupported objects
- `converted_schema/` - PostgreSQL DDL

**Converted Schema:**
- `postgresql_schema.sql` - Tables, indexes, constraints
- `postgresql_procedures.sql` - Functions and procedures (PL/pgSQL)

### 3. AWS Database Migration Service (DMS)

**Location:** `dms/`

DMS handles:
- Full load migration (initial data copy)
- Change Data Capture (CDC) for ongoing replication
- Table-level validation
- Error handling and retry logic

**Configuration:**
- `task_config/table_mappings.json` - Table selection and transformation rules
- `task_config/task_settings.json` - Replication task settings
- `endpoint_configs/` - Source and target endpoint configurations

**Features:**
- Parallel load for performance
- LOB handling
- DDL replication
- Automatic validation
- CloudWatch logging

### 4. Validation Engine

**Location:** `validation/lambda/`

Lambda-based validation framework that performs:

**Row Count Validation:**
- Compares record counts between Oracle and PostgreSQL
- Per-table validation
- Mismatch detection and reporting

**Primary Key Validation:**
- Ensures uniqueness
- Detects duplicates
- Verifies identity sequences

**Foreign Key Validation:**
- Referential integrity checks
- Orphaned record detection
- Cross-table consistency

**Data Consistency:**
- Business logic validation
- Calculated field verification
- Aggregate value matching
- NULL constraint validation

**Checksum Validation:**
- Table-level checksums
- Data integrity verification

**Output:**
- JSON validation reports stored in S3
- CloudWatch metrics
- SNS notifications for failures

### 5. Infrastructure as Code

**Location:** `terraform/`

Terraform modules provision:

**DMS Infrastructure (`dms.tf`):**
- DMS replication instance
- Subnet groups and security groups
- Source endpoint (Oracle)
- Target endpoint (Aurora PostgreSQL)
- Replication task
- IAM roles and policies

**Validation Infrastructure (`validation.tf`):**
- Validation Lambda function
- VPC configuration
- IAM roles and policies
- EventBridge triggers
- CloudWatch log groups

**Monitoring (`dashboard.tf`):**
- CloudWatch dashboard
- Custom metrics
- Alarms for:
  - DMS CPU/Memory/Storage
  - CDC latency
  - Replication lag
  - Validation failures
  - Task state changes

**All infrastructure:**
- Encrypted with KMS
- Private networking
- Least privilege IAM
- Tagged for compliance
- Logged to CloudWatch

---

## Migration Workflow

### Phase 1: Assessment

```bash
# 1. Deploy Oracle source database
sqlplus / as sysdba @oracle/schema.sql
sqlplus / as sysdba @oracle/seed.sql
sqlplus / as sysdba @oracle/procedures.sql

# 2. Run AWS SCT assessment
# - Launch AWS SCT GUI
# - Connect to Oracle source
# - Create assessment report
# - Review complexity and compatibility
# - Save report to sct/assessment/
```

**Assessment Output:**
- Database migration complexity score
- Automated conversion percentage
- Manual remediation items
- Estimated effort

### Phase 2: Schema Conversion

```bash
# 1. Convert schema with AWS SCT
# - Convert tables, indexes, constraints
# - Convert sequences to IDENTITY columns
# - Convert triggers to PostgreSQL functions
# - Convert PL/SQL procedures to PL/pgSQL
# - Export converted DDL

# 2. Manual remediation
# - Review unsupported objects
# - Convert Oracle packages to schemas
# - Replace Oracle-specific functions (NVL → COALESCE, SYSDATE → CURRENT_TIMESTAMP)
# - Test stored procedures
```

**Converted Schema Location:** `sct/converted_schema/`

### Phase 3: Deploy Target Schema

```bash
# Deploy to Aurora PostgreSQL
psql -h <aurora-endpoint> -U postgres -d streamforge -f sct/converted_schema/postgresql_schema.sql
psql -h <aurora-endpoint> -U postgres -d streamforge -f sct/converted_schema/postgresql_procedures.sql

# Verify schema
psql -h <aurora-endpoint> -U postgres -d streamforge -c "\dt"
psql -h <aurora-endpoint> -U postgres -d streamforge -c "\df"
```

### Phase 4: Deploy Migration Infrastructure

```bash
# Initialize Terraform
cd migration/terraform
terraform init

# Review plan
terraform plan -var-file=dev.tfvars

# Deploy infrastructure
terraform apply -var-file=dev.tfvars
```

**Resources Created:**
- DMS replication instance
- Source and target endpoints
- Replication task (full-load-and-cdc)
- Validation Lambda
- CloudWatch dashboard and alarms
- EventBridge rules
- IAM roles and security groups

### Phase 5: Execute Migration

```bash
# Start DMS replication task
aws dms start-replication-task \
  --replication-task-arn <task-arn> \
  --start-replication-task-type start-replication

# Monitor progress
aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=<task-arn>"

# Check CloudWatch dashboard
# Navigate to: CloudWatch → Dashboards → streamforge-dev-migration-dashboard
```

**Full Load Progress:**
- Initial data copy from Oracle to Aurora
- Parallel table loading
- Progress tracked in CloudWatch
- Completion triggers validation Lambda

### Phase 6: Change Data Capture (CDC)

After full load completes, CDC automatically begins:

```bash
# Monitor CDC latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/DMS \
  --metric-name CDCLatencySource \
  --dimensions Name=ReplicationTaskIdentifier,Value=<task-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Test CDC with changes on Oracle
sqlplus / as sysdba <<EOF
INSERT INTO CUSTOMERS (customer_name, email, region_id) 
VALUES ('CDC Test Customer', 'cdc@test.com', 1);
COMMIT;
EOF

# Verify replication to Aurora
psql -h <aurora-endpoint> -U postgres -d streamforge \
  -c "SELECT * FROM customers WHERE email = 'cdc@test.com';"
```

**CDC Features:**
- Near real-time replication
- INSERT, UPDATE, DELETE capture
- Transaction consistency
- Automatic retry on errors
- Latency monitoring

### Phase 7: Validation

```bash
# Validation runs automatically after full load
# Or invoke manually:
aws lambda invoke \
  --function-name streamforge-dev-migration-validation \
  --payload '{"migration_id":"manual-validation-001"}' \
  response.json

# View validation report
aws s3 cp s3://<reports-bucket>/migration_reports/manual-validation-001/ . --recursive

# Check validation metrics
aws cloudwatch get-metric-statistics \
  --namespace StreamForge/Migration \
  --metric-name ValidationStatus \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

**Validation Report Contents:**
```json
{
  "migration_id": "oracle-prod-001",
  "validation_timestamp": "2026-08-20T12:34:56Z",
  "overall_status": "PASS",
  "source_database": "Oracle 19c",
  "target_database": "Aurora PostgreSQL",
  "validation_results": {
    "row_counts": { "status": "PASS", "tables": {...} },
    "primary_keys": { "status": "PASS", "checks": [...] },
    "foreign_keys": { "status": "PASS", "checks": [...] },
    "null_constraints": { "status": "PASS", "checks": [...] },
    "data_consistency": { "status": "PASS", "checks": [...] },
    "checksums": {...}
  },
  "summary": {
    "total_checks": 45,
    "passed_checks": 45,
    "failed_checks": 0,
    "errors": 0
  }
}
```

---

## Monitoring

### CloudWatch Dashboard

Access: `CloudWatch → Dashboards → streamforge-dev-migration-dashboard`

**Widgets:**

1. **DMS Instance - CPU & Memory**
   - CPU utilization
   - Freeable memory
   - Alert threshold: 80% CPU

2. **DMS Instance - Storage**
   - Free storage space
   - Alert threshold: <10 GB

3. **CDC Latency**
   - Source latency
   - Target latency
   - Target: <60 seconds

4. **Full Load Throughput**
   - Rows/second from source
   - Rows/second to target

5. **Validation Metrics**
   - Validation status (1=PASS, 0=FAIL)
   - Total checks
   - Failed checks

6. **Validation Lambda**
   - Execution duration
   - Errors
   - Invocations

7. **Recent DMS Logs**
   - Real-time log streaming

### CloudWatch Alarms

**DMS Alarms:**
- `dms-cpu-high` - CPU > 80%
- `dms-memory-high` - Free memory < 500 MB
- `dms-storage-high` - Free storage < 10 GB

**Validation Alarms:**
- `validation-errors` - Lambda errors > 0
- `validation-duration-high` - Execution > 14 minutes

**All alarms send notifications to SNS topic**

### SNS Notifications

**Migration Events:**
- Task started
- Task stopped
- Task completed
- Task failed
- Validation completed
- Validation failed

---

## Schema Mapping

See [schema-mapping.md](docs/schema-mapping.md) for complete Oracle → PostgreSQL mapping guide.

**Key Mappings:**

| Oracle | PostgreSQL | Notes |
|--------|------------|-------|
| `NUMBER(10)` | `BIGINT` | Integer values |
| `NUMBER(12,2)` | `NUMERIC(12,2)` | Decimal values |
| `VARCHAR2(n)` | `VARCHAR(n)` | Direct mapping |
| `CLOB` | `TEXT` | Large text |
| `DATE` | `TIMESTAMP` | Oracle DATE includes time |
| `SYSDATE` | `CURRENT_TIMESTAMP` | Current timestamp |
| `NVL(a,b)` | `COALESCE(a,b)` | Null handling |
| `SEQUENCE + TRIGGER` | `GENERATED BY DEFAULT AS IDENTITY` | Auto-increment |

---

## Performance Tuning

### DMS Performance

**Replication Instance Sizing:**
```hcl
# For production workloads
replication_instance_class = "dms.r5.xlarge"  # 4 vCPU, 32 GB RAM
allocated_storage = 500  # GB
```

**Task Settings:**
```json
{
  "FullLoadSettings": {
    "MaxFullLoadSubTasks": 8,
    "CommitRate": 10000
  },
  "ChangeProcessingTuning": {
    "BatchApplyMemoryLimit": 500,
    "MemoryLimitTotal": 1024
  }
}
```

### CDC Optimization

**Oracle Source:**
```sql
-- Enable supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER TABLE customers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

**PostgreSQL Target:**
```sql
-- Disable indexes during full load, rebuild after
ALTER TABLE customers SET (autovacuum_enabled = false);
-- Re-enable after load
ALTER TABLE customers SET (autovacuum_enabled = true);
ANALYZE customers;
```

---

## Troubleshooting

### Issue: DMS Task Fails to Start

**Symptoms:** Task status = "failed"

**Diagnosis:**
```bash
# Check task errors
aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=<arn>" \
  --query 'ReplicationTasks[0].ReplicationTaskStats'

# Check CloudWatch logs
aws logs tail /aws/dms/tasks/streamforge-dev-replication-task --follow
```

**Common Causes:**
- Endpoint connectivity issues
- Insufficient permissions
- Invalid table mappings
- Missing Oracle supplemental logging

### Issue: High CDC Latency

**Symptoms:** CDCLatencySource > 300 seconds

**Diagnosis:**
```bash
# Check source load
# Oracle
SELECT * FROM v$archived_log WHERE first_time > SYSDATE - 1;

# Check target throughput
aws cloudwatch get-metric-statistics \
  --namespace AWS/DMS \
  --metric-name CDCThroughputRowsTarget \
  --dimensions Name=ReplicationTaskIdentifier,Value=<task-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average
```

**Solutions:**
- Increase replication instance size
- Enable parallel apply
- Add indexes on target
- Reduce batch transaction size

### Issue: Validation Failures

**Symptoms:** Validation status = "FAIL"

**Diagnosis:**
```bash
# Download validation report
aws s3 cp s3://<bucket>/migration_reports/<id>/validation_*.json .

# Review failed checks
cat validation_*.json | jq '.validation_results | to_entries[] | select(.value.status=="FAIL")'
```

**Common Causes:**
- Row count mismatch (missing or extra rows)
- Foreign key violations
- Data type conversion issues
- NULL constraint violations

---

## Cost Optimization

### DMS Instance

**Development:**
- Instance: `dms.t3.medium` ($0.228/hour)
- Storage: 100 GB ($0.115/GB/month)
- Estimated: ~$180/month

**Production:**
- Instance: `dms.r5.xlarge` ($0.984/hour)
- Storage: 500 GB
- Estimated: ~$780/month

**Recommendation:** Stop instance when not replicating

```bash
aws dms stop-replication-task --replication-task-arn <arn>
```

### Validation Lambda

- Memory: 2048 MB
- Timeout: 15 minutes
- Estimated: <$1/month for daily validation

---

## Security

### Encryption

- **At Rest:** KMS encryption for:
  - DMS replication instance storage
  - CloudWatch logs
  - S3 migration reports

- **In Transit:** TLS/SSL for:
  - Oracle → DMS
  - DMS → Aurora
  - All AWS API calls

### Network

- **Private:** All resources in private subnets
- **No public access** to databases or DMS instance
- **Security groups** restrict traffic to necessary ports

### Credentials

- **Secrets Manager** stores all database credentials
- **IAM roles** with least privilege
- **No hardcoded** credentials in code or configuration

### Compliance

- **CloudTrail** logs all API calls
- **VPC Flow Logs** capture network traffic
- **CloudWatch Logs** retain logs for 30 days
- **Tags** for resource tracking and cost allocation

---

## Cutover Checklist

**Pre-Cutover (T-7 days):**
- [ ] Complete full load migration
- [ ] Verify CDC is operational
- [ ] Run validation checks (all PASS)
- [ ] Test application connectivity to Aurora
- [ ] Document rollback procedure
- [ ] Schedule maintenance window

**Pre-Cutover (T-1 hour):**
- [ ] Stop application writes to Oracle
- [ ] Verify CDC lag < 10 seconds
- [ ] Run final validation
- [ ] Take Oracle backup snapshot
- [ ] Take Aurora snapshot

**Cutover (T-0):**
- [ ] Stop CDC replication
- [ ] Run final validation
- [ ] Update application connection strings to Aurora
- [ ] Restart application
- [ ] Verify application functionality
- [ ] Monitor for errors

**Post-Cutover (T+1 hour):**
- [ ] Verify all application features
- [ ] Check Aurora performance metrics
- [ ] Review CloudWatch alarms
- [ ] Set Oracle to read-only (keep for rollback)
- [ ] Document lessons learned

**Post-Cutover (T+7 days):**
- [ ] Decommission Oracle source (if satisfied)
- [ ] Archive migration reports
- [ ] Update disaster recovery procedures
- [ ] Celebrate successful migration! 🎉

---

## Files Reference

```
migration/
├── README.md                          # This file
├── terraform/
│   ├── dms.tf                        # DMS infrastructure
│   ├── validation.tf                 # Validation Lambda
│   ├── dashboard.tf                  # CloudWatch dashboard
│   └── variables.tf                  # Input variables
├── oracle/
│   ├── schema.sql                    # Oracle DDL
│   ├── seed.sql                      # Sample data
│   └── procedures.sql                # PL/SQL code
├── sct/
│   ├── assessment/                   # SCT reports
│   ├── reports/                      # Conversion reports
│   └── converted_schema/
│       ├── postgresql_schema.sql     # Converted DDL
│       └── postgresql_procedures.sql # Converted PL/pgSQL
├── dms/
│   ├── task_config/
│   │   ├── table_mappings.json      # Table selection rules
│   │   └── task_settings.json       # Task configuration
│   └── endpoint_configs/            # Endpoint settings
├── validation/
│   ├── lambda/
│   │   └── validation_handler.py    # Validation Lambda
│   ├── sql/                          # Validation queries
│   └── reports/                      # Sample reports
├── docs/
│   ├── schema-mapping.md            # Mapping guide
│   ├── migration-guide.md           # Step-by-step guide
│   └── architecture-diagrams/       # Architecture diagrams
└── tests/                            # Integration tests
```

---

## Next Steps

1. **Review Architecture:** Understand the complete migration workflow
2. **Deploy Oracle Source:** Set up sample schema for testing
3. **Run SCT Assessment:** Generate conversion reports
4. **Deploy Infrastructure:** Provision DMS and validation resources with Terraform
5. **Execute Migration:** Run full load and CDC
6. **Validate Results:** Review validation reports
7. **Monitor Performance:** Track metrics in CloudWatch dashboard
8. **Plan Cutover:** Use checklist for production migration

---

## Support

For issues or questions:
- Review [schema-mapping.md](docs/schema-mapping.md) for conversion patterns
- Check CloudWatch logs for error details
- Review validation reports for data issues
- Consult AWS DMS documentation: https://docs.aws.amazon.com/dms/

---

## License

Part of the StreamForge project. See main README for license information.
