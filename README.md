# StreamForge

StreamForge is a serverless AWS data pipeline that validates customer CSV files
uploaded to Amazon S3. Phase 1 routes S3 events through EventBridge to Lambda,
then stores valid and rejected rows separately. Phase 2 adds AWS Glue and
Athena so the cleaned data can be queried with SQL.

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

## Run locally (no AWS)

You can exercise the full validation/cleaning flow without deploying anything.
`scripts/run_local.py` uses local folders under `local_buckets/` in place of the
three S3 buckets.

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
syntax if you run them from PowerShell.

> One-command option: steps 1–5 are bundled in `scripts/deploy.sh` (idempotent).
> Run it, then do step 6 to test:
>
> ```bash
> RAW=dataflow-raw-you CLEAN=dataflow-clean-you REJECTED=dataflow-rejected-you \
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
```

### 1. Create the buckets

```bash
# us-east-1 takes NO LocationConstraint; every other region requires it.
aws s3api create-bucket --bucket $RAW      --region $REGION
aws s3api create-bucket --bucket $CLEAN    --region $REGION
aws s3api create-bucket --bucket $REJECTED --region $REGION
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
cp lambda/handler.py lambda/validator.py build/
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

# Read raw, write clean/rejected
aws iam put-role-policy --role-name streamforge-lambda-role \
  --policy-name streamforge-s3 \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$RAW/*\"},
    {\"Effect\":\"Allow\",\"Action\":\"s3:PutObject\",\"Resource\":[\"arn:aws:s3:::$CLEAN/*\",\"arn:aws:s3:::$REJECTED/*\"]}
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
  --environment "Variables={CLEAN_BUCKET=$CLEAN,REJECTED_BUCKET=$REJECTED}"
```

The two env vars tell the handler where to write. Update later deploys with
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
aws s3 cp s3://$CLEAN/customers.csv -      # rows 101, 104
aws s3 cp s3://$REJECTED/customers.csv -   # rows 102, 103

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
  and delete the three buckets.

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

### Sample Athena queries

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

Later phases may add Parquet partitioning, Terraform, Aurora, AWS SCT, and AWS
DMS. They are intentionally outside Phases 1 and 2.
