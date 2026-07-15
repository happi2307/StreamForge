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
- a `dev` environment root module

Use the `dev` environment first to import and reconcile the currently deployed
resources before creating a `prod` stack.
