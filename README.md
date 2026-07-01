# StreamForge

StreamForge is a serverless AWS data pipeline that validates customer CSV files
uploaded to Amazon S3. Phase 1 routes S3 events through EventBridge to Lambda,
then stores valid and rejected rows separately.

## Phase 1 architecture

```text
CSV -> Raw S3 -> EventBridge -> Lambda -> Clean S3 / Rejected S3
```

See [the architecture document](docs/architecture.md) for more detail.

## Services

- Amazon S3
- Amazon EventBridge
- AWS Lambda (Python 3.12)
- Amazon CloudWatch Logs

## Local setup

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pytest
```

## Sample data

Fixtures live in `sample_data/`. The input contains two valid and two rejected
records, with their expected outputs recorded alongside it.

## Deployment

AWS resource creation, Lambda packaging, environment variables, IAM permissions,
and EventBridge configuration will be documented during Phase 1 implementation.

## Future enhancements

Later phases may add Glue, Athena, Parquet partitioning, Terraform, Aurora,
AWS SCT, and AWS DMS. They are intentionally outside Phase 1.
