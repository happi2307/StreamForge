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

output "operations_alert_topic_arn" {
  description = "ARN of the SNS topic for operational alerts."
  value       = module.phase4_operations.alert_topic_arn
}

output "eventbridge_dead_letter_queue_arn" {
  description = "ARN of the DLQ for undeliverable raw-upload events."
  value       = module.phase4_operations.eventbridge_dead_letter_queue_arn
}

output "operations_dashboard_name" {
  description = "Name of the CloudWatch dashboard for pipeline health."
  value       = module.phase4_operations.dashboard_name
}

output "web_console_api_endpoint" { value = module.web_console.api_endpoint }
output "web_console_user_pool_id" { value = module.web_console.user_pool_id }
output "web_console_user_pool_client_id" { value = module.web_console.user_pool_client_id }
output "web_console_cognito_domain" { value = module.web_console.cognito_domain }
output "web_dashboard_url" { value = module.web_static.dashboard_origin }
output "web_dashboard_bucket_name" { value = module.web_static.bucket_name }
