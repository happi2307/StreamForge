output "backend_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = module.state_bucket.bucket_name
}

output "lock_table_name" {
  description = "Name of the DynamoDB state lock table."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "kms_key_arn" {
  description = "KMS key ARN used by backend resources."
  value       = module.kms.key_arn
}
