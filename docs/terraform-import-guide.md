# Terraform import guide (Track A)

Track A adopts the current AWS footprint into Terraform without tearing down the
working pipeline.

## Recommended order

1. KMS key and alias
2. S3 buckets
3. IAM roles and policies
4. Lambda and EventBridge
5. Glue and Athena

## Initial Track A scope in this repo

The first Terraform environment models:

- the environment KMS key
- raw bucket
- clean bucket
- rejected bucket
- metadata bucket
- curated bucket
- quarantine bucket
- Athena results bucket

## Workflow

1. Bootstrap the backend in `terraform/bootstrap/backend`.
2. Copy `terraform/environments/dev/backend.hcl.example` to a real backend
   config or pass the values directly at init time.
3. Copy `terraform/environments/dev/terraform.tfvars.example` and replace the
   placeholder names with the currently deployed AWS resource names.
4. Run `terraform init`.
5. Import resources one by one.
6. Run `terraform plan`.
7. Reconcile drift until the plan only shows intentional changes.

## Example import commands

```powershell
cd terraform\environments\dev
terraform init -backend-config=backend.hcl

terraform import module.kms.aws_kms_key.this <kms-key-id-or-arn>
terraform import module.kms.aws_kms_alias.this alias/streamforge-phase1

terraform import 'module.buckets["raw"].aws_s3_bucket.this' streamforge-raw-ACCOUNTID-us-east-1
terraform import 'module.buckets["clean"].aws_s3_bucket.this' streamforge-clean-ACCOUNTID-us-east-1
terraform import 'module.buckets["rejected"].aws_s3_bucket.this' streamforge-rejected-ACCOUNTID-us-east-1
terraform import 'module.buckets["metadata"].aws_s3_bucket.this' streamforge-metadata-ACCOUNTID-us-east-1
terraform import 'module.buckets["curated"].aws_s3_bucket.this' streamforge-curated-ACCOUNTID-us-east-1
terraform import 'module.buckets["quarantine"].aws_s3_bucket.this' streamforge-quarantine-ACCOUNTID-us-east-1
terraform import 'module.buckets["athena_results"].aws_s3_bucket.this' streamforge-athena-results-ACCOUNTID-us-east-1
```

Import the related bucket sub-resources after the base bucket resources:

- `aws_s3_bucket_versioning`
- `aws_s3_bucket_public_access_block`
- `aws_s3_bucket_ownership_controls`
- `aws_s3_bucket_server_side_encryption_configuration`
- `aws_s3_bucket_policy`

Track A intentionally stops after storage and encryption adoption. Lambda,
EventBridge, Glue, and Athena should be brought in after this layer is stable.
