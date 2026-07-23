# Production environment

This is an independent Terraform root for production. It uses `prod` defaults
for resource names, KMS alias, Glue database, Athena workgroups, alert topic,
and EventBridge DLQ. It is deliberately not connected to the current dev AWS
account or backend.

Use a separate AWS account when possible. First deploy the Phase 3 Glue assets
to the production metadata bucket, create an ignored `backend.hcl` from the
example, and set ownership, cost-center, and alert-email values in an ignored
`terraform.tfvars`. Run a reviewed plan through the GitHub `prod` environment;
do not apply this root directly from a developer workstation.
