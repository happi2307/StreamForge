output "kms_key_arn" {
  description = "KMS key ARN for the dev environment."
  value       = module.kms.key_arn
}

output "bucket_names" {
  description = "Bucket names keyed by logical bucket purpose."
  value = {
    for key, bucket in module.buckets :
    key => bucket.bucket_name
  }
}
