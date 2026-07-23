# prod environment

Track A starts with the `dev` environment so the existing live stack can be
imported and reconciled safely. This `prod` root module mirrors `dev` and reuses
the same modules (`kms`, `s3`, `phase1_runtime`, `phase2_analytics`,
`phase3_curated`, `monitoring`).

Use it only after the `dev` adoption workflow is stable.

## Workflow

1. Copy `backend.hcl.example` to a real backend config (state key `prod/terraform.tfstate`).
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and set the real prod
   values (owner, cost center, bucket overrides, KMS alias, alert email).
3. `terraform init -backend-config=backend.hcl`
4. Import existing prod resources (see `docs/terraform-import-guide.md`) or
   `terraform plan` to create a fresh prod stack.
5. Reconcile drift until the plan only shows intentional changes, then apply.

Keep `prod` on a separate state key and, ideally, a separate AWS account from
`dev`.
