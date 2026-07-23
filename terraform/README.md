# Terraform Layout

Track A adopts the existing AWS footprint into Terraform in a low-risk order:

1. backend bootstrap
2. KMS + S3
3. IAM + Lambda + EventBridge
4. Glue + Athena
5. monitoring and notifications

The initial implementation in this repository focuses on:

- backend bootstrap scaffolding
- reusable KMS and S3 modules
- a reusable Phase 1 runtime module for IAM, Lambda, and EventBridge
- a reusable Phase 2 analytics module for Glue and Athena
- a reusable Phase 3 curated analytics module for Glue ETL and Athena
- a reusable Phase 4 operations module for CloudWatch, SNS, and SQS resilience
- a private CloudFront + S3 dashboard delivery module with Origin Access Control
- a `dev` environment root module

Use the `dev` environment first to import and reconcile the currently deployed
resources before creating a `prod` stack.

## Track B operations

The `phase4_operations` module creates a KMS-encrypted SNS topic, a
KMS-encrypted SQS dead-letter queue for undeliverable EventBridge events,
Lambda/EventBridge/quarantine-rate alarms, Glue and Athena failure event rules,
and a CloudWatch dashboard. Set `operations_alert_email` in the ignored
`terraform.tfvars` file before applying, then confirm the subscription email.

The Phase 1 Lambda log group is explicitly managed with KMS encryption and a
30-day default retention period. Import that pre-existing log group before the
first Track B apply when adopting the live environment.

## Dashboard delivery

The `web_static` module publishes `web/index.html`, `web/styles.css`, and
`web/app.js` to a versioned, SSE-KMS encrypted private bucket. CloudFront is
the only S3 reader through Origin Access Control. Terraform renders the runtime
browser configuration from `web/config.template.js`, and adds the resulting
CloudFront HTTPS origin to Cognito callback URLs, API Gateway CORS, and raw S3
upload CORS while retaining `http://localhost:8000` for local development.
