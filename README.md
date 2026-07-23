# StreamForge

StreamForge is a serverless AWS data pipeline that validates customer CSV files
uploaded to Amazon S3. Phase 1 routes S3 events through EventBridge to Lambda,
then stores valid and rejected rows separately. Phase 1 now also writes a
sidecar processing manifest for each source file so downstream phases can use
stable lineage metadata. Phase 2 adds AWS Glue and Athena so the cleaned data
can be queried with SQL. Phase 4 begins the Terraform adoption of the deployed
AWS footprint so the platform can be recreated and governed as code.

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
- AWS Glue Data Catalog
- AWS Glue Crawler
- Amazon Athena
- AWS Key Management Service (KMS)
- Terraform

## Phase 4 foundation

Track A introduces the initial Terraform adoption layout:

- `terraform/bootstrap/backend`
- `terraform/environments/dev`
- `terraform/modules/kms`
- `terraform/modules/s3`
- `terraform/modules/phase1_runtime`
- `terraform/modules/phase2_analytics`
- `terraform/modules/phase3_curated`
- `terraform/modules/monitoring`

The Track A implementation covers backend bootstrap, KMS/S3 adoption, the
Phase 1 IAM/Lambda/EventBridge runtime layer, the Phase 2 Glue/Athena analytics
layer, the Phase 3 curated Glue/Athena layer, and a monitoring layer (SNS
alerts, CloudWatch Lambda alarms, and Glue job failure notifications). Both a
`dev` and a `prod` environment root module consume these modules. Operational
docs live under `docs/adr`, `docs/diagrams`, and `docs/runbooks`. See the import
guide in `docs/terraform-import-guide.md`.

## Local setup

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pytest
```

## Sample input

`sample_data/customers.csv`:

```text
customer_id,name,email,sales
101,John,john@gmail.com,500
102,,mary@gmail.com,600
103,Sam,samgmail.com,700
104,Raj,raj@gmail.com,1000
```

## Sample output

Clean bucket (`sample_data/expected_clean.csv`):

```text
customer_id,name,email,sales
101,John,john@gmail.com,500
104,Raj,raj@gmail.com,1000
```

Rejected bucket (`sample_data/expected_rejected.csv`) — row 102 has no name and
row 103 has an invalid email:

```text
customer_id,name,email,sales
102,,mary@gmail.com,600
103,Sam,samgmail.com,700
```

The handler returns processing statistics:

```json
{ "total_records": 4, "valid_records": 2, "invalid_records": 2 }
```

Phase 1 also writes a manifest JSON for each processed file. The recommended
layout uses a separate metadata bucket so analytics jobs can enrich rows without
changing the clean CSV schema:

```text
clean/customers.csv
rejected/customers.csv
metadata/customers.csv.json
```

## Run locally (no AWS)

You can exercise the full validation/cleaning flow without deploying anything.
`scripts/run_local.py` uses local folders under `local_buckets/` in place of the
raw, clean, rejected, and metadata buckets.

```powershell
# "Upload" a CSV by dropping it into the raw folder
mkdir local_buckets\raw
copy sample_data\customers.csv local_buckets\raw\

# Run the pipeline (processes every CSV in local_buckets/raw/)
.\.venv\Scripts\python.exe scripts\run_local.py
```

Results appear in `local_buckets\clean\` and `local_buckets\rejected\`, and the
processing statistics are logged to the console. You can also target one file:
`python scripts\run_local.py sample_data\customers.csv`.

## Deployment (AWS Phase 1)

Terraform is out of scope for Phase 1; the steps below use the AWS CLI. Pick
**globally unique** bucket names. Commands are shown in bash — adjust variable
syntax if you run them from PowerShell. The current implementation also uses a
metadata bucket for Phase 1 manifests.

> One-command option: steps 1–5 are bundled in `scripts/deploy.sh` (idempotent).
> Run it, then do step 6 to test:
>
> ```bash
> RAW=dataflow-raw-you CLEAN=dataflow-clean-you REJECTED=dataflow-rejected-you \
>   METADATA=dataflow-metadata-you \
>   REGION=us-east-1 bash scripts/deploy.sh
> ```

### 0. Prerequisites

```bash
aws --version                        # AWS CLI v2
aws configure                        # access key, secret, default region
aws sts get-caller-identity          # confirm you are authenticated

# Reusable variables
REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
RAW=dataflow-raw-you
CLEAN=dataflow-clean-you
REJECTED=dataflow-rejected-you
METADATA=dataflow-metadata-you
```

### 1. Create the buckets

```bash
# us-east-1 takes NO LocationConstraint; every other region requires it.
aws s3api create-bucket --bucket $RAW      --region $REGION
aws s3api create-bucket --bucket $CLEAN    --region $REGION
aws s3api create-bucket --bucket $REJECTED --region $REGION
aws s3api create-bucket --bucket $METADATA --region $REGION
```

Enable EventBridge notifications on the raw bucket (this is what makes uploads
emit events — the most commonly missed step):

```bash
aws s3api put-bucket-notification-configuration --bucket $RAW \
  --notification-configuration '{"EventBridgeConfiguration":{}}'
```

### 2. Package the function

pandas and boto3 exceed the inline editor limit, so ship them in the ZIP:

```bash
rm -rf build function.zip
pip install -r lambda/requirements.txt -t build/
cp lambda/handler.py lambda/validator.py lambda/metadata.py build/
cd build && zip -r ../function.zip . && cd ..
```

`handler.py` and `validator.py` sit at the ZIP root (flat layout), so the handler
entry point is `handler.lambda_handler`.

### 3. Create the IAM role

```bash
# Trust policy so Lambda can assume the role
aws iam create-role --role-name streamforge-lambda-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

# CloudWatch Logs permissions
aws iam attach-role-policy --role-name streamforge-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Read raw, write clean/rejected/metadata
aws iam put-role-policy --role-name streamforge-lambda-role \
  --policy-name streamforge-s3 \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$RAW/*\"},
    {\"Effect\":\"Allow\",\"Action\":\"s3:PutObject\",\"Resource\":[\"arn:aws:s3:::$CLEAN/*\",\"arn:aws:s3:::$REJECTED/*\",\"arn:aws:s3:::$METADATA/*\"]}
  ]}"
```

Wait ~10 seconds for the role to propagate before the next step.

### 4. Deploy the Lambda

```bash
aws lambda create-function \
  --function-name streamforge-processor \
  --runtime python3.12 \
  --handler handler.lambda_handler \
  --role arn:aws:iam::$ACCOUNT_ID:role/streamforge-lambda-role \
  --zip-file fileb://function.zip \
  --timeout 60 --memory-size 256 \
  --environment "Variables={CLEAN_BUCKET=$CLEAN,REJECTED_BUCKET=$REJECTED,METADATA_BUCKET=$METADATA,METADATA_PREFIX=metadata,PHASE1_PIPELINE_VERSION=1.1.0}"
```

Those environment variables tell the handler where to write and which Phase 1
version stamp to place in the manifest. Update later deploys with
`aws lambda update-function-code --function-name streamforge-processor
--zip-file fileb://function.zip`.

### 5. Wire the EventBridge rule

```bash
aws events put-rule --name streamforge-raw-uploads --region $REGION \
  --event-pattern "{\"source\":[\"aws.s3\"],\"detail-type\":[\"Object Created\"],\"detail\":{\"bucket\":{\"name\":[\"$RAW\"]}}}"

aws lambda add-permission --function-name streamforge-processor \
  --statement-id eventbridge-invoke --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:$REGION:$ACCOUNT_ID:rule/streamforge-raw-uploads

aws events put-targets --rule streamforge-raw-uploads --region $REGION \
  --targets "Id=1,Arn=arn:aws:lambda:$REGION:$ACCOUNT_ID:function:streamforge-processor"
```

### 6. Upload a CSV and verify

```bash
aws s3 cp sample_data/customers.csv s3://$RAW/customers.csv

# After a few seconds:
aws s3 ls s3://$CLEAN/           # customers.csv appears
aws s3 ls s3://$REJECTED/        # customers.csv appears
aws s3 ls s3://$METADATA/metadata/   # customers.csv.json appears
aws s3 cp s3://$CLEAN/customers.csv -      # rows 101, 104
aws s3 cp s3://$REJECTED/customers.csv -   # rows 102, 103
aws s3 cp s3://$METADATA/metadata/customers.csv.json -  # manifest metadata

# Processing statistics
aws logs tail /aws/lambda/streamforge-processor --follow
```

You should see `Total Records: 4 / Valid Records: 2 / Invalid Records: 2`.

### Troubleshooting

- **`BucketAlreadyExists`** — bucket names are global; choose something more unique.
- **First upload does nothing** — confirm the EventBridge notification config in
  step 1 was applied to the raw bucket.
- **`AccessDenied` writing outputs** — recheck the inline S3 policy in step 3.
- **Cleanup** — to avoid charges, delete the function, rule, and role, then empty
  and delete the four buckets.

## Deployment (AWS Phase 2)

Phase 2 keeps the Phase 1 clean bucket as the source of truth and adds:

- a KMS-encrypted Athena results bucket
- a Glue database
- a Glue crawler role and crawler
- an Athena workgroup
- a canonical `streamforge_clean_db.customers` table for queries

### Prerequisites

Phase 1 must already be deployed, and the clean bucket must contain at least one
processed CSV file.

The repository includes a PowerShell helper:

```powershell
.\scripts\deploy_phase2.ps1
```

By default it assumes:

- Region: `us-east-1`
- KMS key: `alias/streamforge-phase1`
- Clean bucket: `streamforge-clean-<account-id>-<region>`
- Athena results bucket: `streamforge-athena-results-<account-id>-<region>`
- Glue database: `streamforge_clean_db`
- Athena workgroup: `streamforge-phase2`

You can override any of those values:

```powershell
.\scripts\deploy_phase2.ps1 `
  -Region us-east-1 `
  -KmsKeyId alias/streamforge-phase1 `
  -GlueDatabase streamforge_clean_db `
  -AthenaWorkgroup streamforge-phase2
```

### What the script does

1. Creates and hardens the Athena results bucket with `SSE-KMS`.
2. Creates the Glue database.
3. Creates the Glue crawler role with read access to the clean bucket and KMS
   decrypt access to the project key.
4. Creates or updates the Glue crawler.
5. Creates or updates the Athena workgroup with enforced output location and
   `SSE-KMS` query result encryption.
6. Runs the crawler.
7. Creates the canonical `streamforge_clean_db.customers` table.
8. Verifies the sample Athena queries.

The Phase 2 crawler excludes the Phase 1 `metadata/` prefix so only clean CSV
objects are cataloged.

## Deployment (AWS Phase 3)

Phase 3 turns the clean CSV layer into a curated analytics layer. It reads clean
CSV files plus Phase 1 manifests, applies business transformations, writes
Parquet to a curated bucket, and quarantines malformed transformed rows without
failing the whole job unless a configured threshold is exceeded.

The repository includes a PowerShell helper:

```powershell
.\scripts\deploy_phase3.ps1
```

By default it assumes:

- Region: `us-east-1`
- KMS key: `alias/streamforge-phase1`
- Clean bucket: `streamforge-clean-<account-id>-<region>`
- Metadata bucket: `streamforge-metadata-<account-id>-<region>`
- Curated bucket: `streamforge-curated-<account-id>-<region>`
- Quarantine bucket: `streamforge-quarantine-<account-id>-<region>`
- Glue database: `streamforge_clean_db`
- Glue job: `streamforge-transform-customers`
- Curated table: `customers_curated`
- Athena workgroup: `streamforge-phase3`

### What the script does

1. Creates and hardens the curated and quarantine buckets with `SSE-KMS`.
2. Creates the Phase 3 Glue transform role.
3. Uploads the Glue script and helper package to S3.
4. Creates or updates the Phase 3 Glue job.
5. Runs the job against the current clean data and manifests.
6. Creates the curated Athena table.
7. Repairs partitions and verifies the curated output with Athena.

### Phase 3 outputs

Curated output:

```text
s3://streamforge-curated-<account-id>-<region>/customers/year=YYYY/month=MM/day=DD/
```

Quarantine output:

```text
s3://streamforge-quarantine-<account-id>-<region>/reason=<reason>/year=YYYY/month=MM/day=DD/
```

### Business transformations

Phase 3 currently implements:

- whitespace trimming for string values
- customer-name normalization
- email lowercasing
- sales parsing and categorical bucketing
- lineage enrichment from the Phase 1 manifest
- partition derivation from the manifest event timestamp

If you later add a business date field to the clean schema, the Glue job can
also standardize it by passing `-DateColumn <column-name>`.

### Phase 3 sample Athena queries

See [scripts/phase3_queries.sql](scripts/phase3_queries.sql) for example queries
over `streamforge_clean_db.customers_curated`.

### Phase 2 sample Athena queries

See [scripts/phase2_queries.sql](scripts/phase2_queries.sql) for the DDL and
query examples used for verification.

Expected ordered query result:

```text
customer_id,name,email,sales
101,John,john@gmail.com,500
104,Raj,raj@gmail.com,1000
```

Expected aggregate query result:

```text
total_customers,total_sales,average_sales
2,1500,750.0
```

## Future enhancements

Later phases may add Terraform, Aurora, AWS SCT, and AWS DMS. They are
intentionally outside the current implementation.
