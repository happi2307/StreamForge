# Aurora PostgreSQL Data Validation

Automated data-integrity validation for the StreamForge Aurora PostgreSQL
database: a Lambda that runs a suite of checks, writes a JSON report to S3,
and publishes pass/fail metrics to CloudWatch.

> This component began life as the target-side half of an Oracle to Aurora
> PostgreSQL migration. The Oracle source, AWS SCT conversion artifacts, and
> the DMS replication stack have been decommissioned; the validation suite was
> kept because it stands on its own against Aurora.

## Layout

| Path | Contents |
|------|----------|
| `validation/lambda/validation_handler.py` | The validation Lambda |
| `validation/sql/validation_queries.sql` | The same checks as ad-hoc SQL |
| `terraform/` | Lambda, IAM, security group, alarms, CloudWatch dashboard |
| `tests/test_migration.py` | Unit tests for the pure validation logic |

## Checks

| Check | What it asserts |
|-------|-----------------|
| `validate_row_counts` | Every expected table is queryable, and records its count |
| `validate_primary_keys` | No duplicate primary keys |
| `validate_foreign_keys` | No orphaned child rows |
| `validate_null_constraints` | No NULLs in NOT NULL columns |
| `validate_data_consistency` | Business-rule invariants (order totals, stock levels) |
| `calculate_checksums` | Aggregate checksums per table |

A single `FAIL` or `ERROR` in any check makes the overall report `FAIL`.

## Running it

The Lambda is invoked on demand — there is no automatic trigger now that the
DMS task that used to fire it is gone.

```bash
aws lambda invoke \
  --function-name streamforge-dev-migration-validation \
  --payload '{"migration_id": "manual-001"}' \
  response.json
```

The report lands in `s3://$S3_REPORTS_BUCKET/migration_reports/` and the
summary metrics appear in the `StreamForge/Migration` CloudWatch namespace.

## Tests

```bash
python migration/tests/test_migration.py
```

`boto3` and `pg8000` are stubbed, so the tests need no dependencies and no AWS
account.

## Deploying

```bash
cd migration/terraform
cp dev.tfvars.example dev.tfvars   # fill in your ARNs
terraform init
terraform apply -var-file=dev.tfvars
```
