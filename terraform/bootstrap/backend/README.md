# Backend bootstrap

This stack creates the one-time Terraform backend resources:

- S3 state bucket
- DynamoDB lock table
- backend KMS key

Run it locally before initializing the main environment stacks.

## Example

```powershell
cd terraform\bootstrap\backend
terraform init
terraform apply -var "owner=Akshat" -var "cost_center=portfolio"
```

After apply, configure `terraform/environments/dev/backend.hcl` (or pass
`-backend-config` values directly) using the output bucket and table names.
