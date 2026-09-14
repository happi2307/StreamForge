# Legacy manual deployment reference

Superseded. Terraform is the supported provisioning path for StreamForge; see
the README's Deploying section. These AWS CLI and PowerShell transcripts are
kept for reference only and record how Phases 1 to 3 were first stood up by
hand. Do not use them against the Terraform-managed environment -- they will
create resources Terraform does not know about, and the next apply will fight
them.

## Legacy manual deployment reference (AWS Phase 1)

Terraform is the supported provisioning path for StreamForge. The CLI steps
below are retained as a learning reference for the original Phase 1 build; do
not use them to change the Terraform-managed development environment.

The original Phase 1 build used the AWS CLI. Pick **globally unique** bucket
names if following these historical instructions. Commands are shown in bash â€”
adjust variable syntax if you run them from PowerShell. The current
implementation also uses a metadata bucket for Phase 1 manifests.

> One-command option: steps 1â€“5 are bundled in `scripts/deploy.sh` (idempotent).
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
emit events â€” the most commonly missed step):

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

- **`BucketAlreadyExists`** â€” bucket names are global; choose something more unique.
- **First upload does nothing** â€” confirm the EventBridge notification config in
  step 1 was applied to the raw bucket.
- **`AccessDenied` writing outputs** â€” recheck the inline S3 policy in step 3.
- **Cleanup** â€” to avoid charges, delete the function, rule, and role, then empty
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

