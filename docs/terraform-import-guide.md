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
- Phase 1 Lambda IAM role and inline policy
- Phase 1 Lambda function
- raw-upload EventBridge rule and target
- EventBridge invoke permission on the Lambda
- raw-bucket EventBridge notification toggle
- Phase 2 Glue crawler IAM role and policy
- Phase 2 Glue database
- Phase 2 Glue crawler
- Phase 2 Athena workgroup
- Phase 2 canonical Glue table
- Phase 3 Glue transform IAM role and policy
- Phase 3 Glue job
- Phase 3 Athena workgroup
- Phase 3 curated Glue table

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

Track A now also includes the Phase 1 runtime layer. Import those resources
after the storage layer is stable:

```powershell
terraform import module.phase1_runtime.aws_iam_role.lambda streamforge-lambda-role
terraform import module.phase1_runtime.aws_iam_role_policy_attachment.basic_execution streamforge-lambda-role/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
terraform import module.phase1_runtime.aws_iam_role_policy.data_plane streamforge-lambda-role:streamforge-s3-kms
terraform import module.phase1_runtime.aws_lambda_function.this streamforge-processor
terraform import module.phase1_runtime.aws_cloudwatch_event_rule.raw_uploads streamforge-raw-uploads
terraform import module.phase1_runtime.aws_cloudwatch_event_target.lambda streamforge-raw-uploads/1
terraform import module.phase1_runtime.aws_lambda_permission.allow_eventbridge streamforge-processor/eventbridge-invoke
terraform import module.phase1_runtime.aws_s3_bucket_notification.raw_eventbridge streamforge-raw-ACCOUNTID-us-east-1
```

Before planning or applying the runtime layer, make sure `lambda_package_path`
points to a real ZIP package for the Phase 1 Lambda. A simple way to rebuild it
is the existing Phase 1 packaging flow:

```powershell
pip install -r lambda/requirements.txt -t build
Copy-Item lambda/handler.py,lambda/validator.py,lambda/metadata.py build
Compress-Archive -Path build\* -DestinationPath function.zip -Force
```

After the runtime layer is stable, import the Phase 2 analytics resources:

```powershell
terraform import module.phase2_analytics.aws_iam_role.crawler streamforge-glue-crawler-role
terraform import module.phase2_analytics.aws_iam_role_policy_attachment.glue_service_role streamforge-glue-crawler-role/arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
terraform import module.phase2_analytics.aws_iam_role_policy.crawler_data_access streamforge-glue-crawler-role:streamforge-glue-clean-read
terraform import module.phase2_analytics.aws_glue_catalog_database.this 108379846489:streamforge_clean_db
terraform import module.phase2_analytics.aws_glue_crawler.this streamforge-clean-crawler
terraform import module.phase2_analytics.aws_athena_workgroup.this streamforge-phase2
terraform import module.phase2_analytics.aws_glue_catalog_table.canonical_customers 108379846489:streamforge_clean_db:customers
```

The crawler-created helper table (for example
`streamforge_clean_108379846489_us_east_1`) can remain unmanaged if you only
want Terraform to own the canonical analytics interface.

After the Phase 2 analytics layer is stable, import the Phase 3 curated
resources:

```powershell
terraform import module.phase3_curated.aws_iam_role.job streamforge-glue-transform-role
terraform import module.phase3_curated.aws_iam_role_policy_attachment.glue_service_role streamforge-glue-transform-role/arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
terraform import module.phase3_curated.aws_iam_role_policy.job_data_access streamforge-glue-transform-role:streamforge-phase3-data-access
terraform import module.phase3_curated.aws_glue_job.this streamforge-transform-customers
terraform import module.phase3_curated.aws_athena_workgroup.this streamforge-phase3
terraform import module.phase3_curated.aws_glue_catalog_table.curated 108379846489:streamforge_clean_db:customers_curated
```

## Phase 4 monitoring resources

The `monitoring` module creates new resources (an SNS topic, three CloudWatch
alarms, and a Glue-failure EventBridge rule) that did not exist in the pre-import
footprint. Those are created by `terraform apply`, not imported. Set
`alerts_notification_email` before applying and confirm the subscription from the
email inbox; until it is confirmed, alerts are not delivered.

If any of these already exist in the account, import them before applying:

```powershell
terraform import module.monitoring.aws_sns_topic.alerts arn:aws:sns:us-east-1:108379846489:streamforge-dev-alerts
terraform import module.monitoring.aws_cloudwatch_metric_alarm.lambda_errors streamforge-processor-errors
terraform import module.monitoring.aws_cloudwatch_metric_alarm.lambda_throttles streamforge-processor-throttles
terraform import module.monitoring.aws_cloudwatch_metric_alarm.lambda_duration streamforge-processor-duration
terraform import module.monitoring.aws_cloudwatch_event_rule.glue_job_failed streamforge-glue-job-failed
```

## prod environment

`terraform/environments/prod` mirrors `dev` and reuses the same modules. Bring it
up only after the `dev` adoption is stable. Use a separate state key
(`prod/terraform.tfstate`) and preferably a separate AWS account. Repeat the
import steps above against the prod resources, or run a clean `plan`/`apply` to
create prod from scratch.
