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

output "phase1_lambda_function_name" {
  description = "Name of the Phase 1 Lambda function in the dev environment."
  value       = module.phase1_runtime.lambda_function_name
}

output "phase1_lambda_role_name" {
  description = "Name of the Phase 1 Lambda IAM role in the dev environment."
  value       = module.phase1_runtime.lambda_role_name
}

output "phase1_event_rule_name" {
  description = "Name of the EventBridge rule for raw uploads."
  value       = module.phase1_runtime.event_rule_name
}

output "phase2_glue_database_name" {
  description = "Name of the Glue database for clean customer analytics."
  value       = module.phase2_analytics.glue_database_name
}

output "phase2_glue_crawler_name" {
  description = "Name of the Glue crawler for clean customer analytics."
  value       = module.phase2_analytics.glue_crawler_name
}

output "phase2_glue_crawler_role_name" {
  description = "Name of the Glue crawler IAM role."
  value       = module.phase2_analytics.glue_crawler_role_name
}

output "phase2_athena_workgroup_name" {
  description = "Name of the Athena workgroup for clean CSV queries."
  value       = module.phase2_analytics.athena_workgroup_name
}

output "phase2_canonical_table_name" {
  description = "Name of the canonical Glue table for clean customer data."
  value       = module.phase2_analytics.canonical_table_name
}

output "phase3_glue_job_role_name" {
  description = "Name of the IAM role used by the Phase 3 Glue job."
  value       = module.phase3_curated.glue_job_role_name
}

output "phase3_glue_job_name" {
  description = "Name of the Phase 3 Glue job."
  value       = module.phase3_curated.glue_job_name
}

output "phase3_athena_workgroup_name" {
  description = "Name of the Phase 3 Athena workgroup."
  value       = module.phase3_curated.athena_workgroup_name
}

output "phase3_curated_table_name" {
  description = "Name of the Phase 3 curated Glue table."
  value       = module.phase3_curated.curated_table_name
}
