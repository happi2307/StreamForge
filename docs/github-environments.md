# GitHub environments and deployment roles

The public repository has a configured `dev` GitHub environment. Its required
reviewer is `ashutoshg-2005`; deployment jobs pause until that reviewer approves
them. Add a separate `prod` environment only when a production AWS account and
its deployment role exist. Production must require a separate approval after
dev integration tests complete.

Set these environment variables in each environment:

| Variable | Purpose |
| --- | --- |
| `AWS_ROLE_TO_ASSUME` | OIDC deployment role ARN for that environment |
| `AWS_REGION` | Target AWS region |
| `TF_STATE_BUCKET` | Remote Terraform state bucket |
| `TF_STATE_KEY` | Environment-specific state key, for example `dev/terraform.tfstate` |
| `TF_LOCK_TABLE` | Terraform lock table name |
| `TF_VAR_OWNER` | Owner tag passed to the dev Terraform root module |
| `TF_VAR_COST_CENTER` | Cost-center tag passed to the dev Terraform root module |
| `TF_VAR_KMS_ALIAS_NAME` | Existing environment KMS alias used when reconciling dev |
| `TF_VAR_KMS_DESCRIPTION` | Existing environment KMS key description used when reconciling dev |
| `TF_VAR_BUCKET_NAME_OVERRIDES` | JSON map of existing dev bucket names used during reconciliation |

GitHub normalizes configuration-variable names to uppercase. The dev Terraform
workflows map these variables into Terraform's case-sensitive lower-case
`TF_VAR_*` process environment variables before running Terraform.

The repository uses GitHub OIDC rather than long-lived AWS secrets. Create a
least-privilege IAM role per environment whose trust policy limits the subject
to `repo:happi2307/StreamForge:environment:dev` or
`repo:happi2307/StreamForge:environment:prod`. Keep the production role in a
separate AWS account where possible.

`terraform-plan.yml` runs a read-only dev plan whenever it is dispatched or a
relevant pull request is opened. `terraform-apply-dev.yml` requires reviewer
approval, a manual dispatch, and the literal
confirmation value `deploy`; GitHub environment approval is the second gate.
`terraform-apply-prod.yml` requires a separate production approval and the
literal confirmation value `deploy-prod`.

## Promotion flow

```text
Feature branch -> CI -> Pull request -> Dev Terraform plan
    -> approved manual dev deployment -> integration tests
    -> approved manual production deployment
```

The CI workflow tests the Python code, verifies Terraform formatting and
configuration, and builds both Lambda archives. The Terraform plan and apply
workflows build the same archives again from the commit they are deploying.
This avoids committing generated ZIP files and produces Linux-compatible,
Python 3.12 x86_64 dependencies for the Phase 1 Lambda.

`terraform-plan.yml` runs for changes to Terraform, Lambda source, dashboard
source, and the package script. It uses the `dev` environment only and never
applies changes. The production workflow remains manually dispatched after dev
verification; it does not run automatically from a branch or pull request.
