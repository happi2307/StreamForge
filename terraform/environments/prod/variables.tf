variable "project_name" {
  description = "Project identifier used in names and tags."
  type        = string
  default     = "streamforge"
}

variable "environment" {
  description = "Environment label."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for the environment."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
}

variable "cost_center" {
  description = "Cost center tag value."
  type        = string
}

variable "created_by" {
  description = "CreatedBy tag value."
  type        = string
  default     = "terraform"
}

variable "repository" {
  description = "Repository tag value."
  type        = string
  default     = "StreamForge"
}

variable "kms_alias_name" {
  description = "Alias for the environment KMS key."
  type        = string
  default     = "alias/streamforge-prod"
}

variable "kms_description" {
  description = "Description for the environment KMS key."
  type        = string
  default     = "KMS key for StreamForge production data plane resources."
}

variable "lambda_function_name" {
  description = "Name of the Phase 1 Lambda function."
  type        = string
  default     = "streamforge-prod-processor"
}

variable "lambda_description" {
  description = "Description of the Phase 1 Lambda function."
  type        = string
  default     = ""
}

variable "lambda_role_name" {
  description = "Name of the IAM role used by the Phase 1 Lambda function."
  type        = string
  default     = "streamforge-prod-lambda-role"
}

variable "lambda_inline_policy_name" {
  description = "Name of the inline IAM policy attached to the Phase 1 Lambda role."
  type        = string
  default     = "streamforge-prod-s3-kms"
}

variable "event_rule_name" {
  description = "Name of the EventBridge rule for raw-bucket uploads."
  type        = string
  default     = "streamforge-prod-raw-uploads"
}

variable "event_rule_description" {
  description = "Description of the EventBridge rule."
  type        = string
  default     = ""
}

variable "event_target_id" {
  description = "Identifier used for the EventBridge target."
  type        = string
  default     = "1"
}

variable "lambda_package_path" {
  description = "Path to the Phase 1 Lambda deployment ZIP."
  type        = string
  default     = "function.zip"
}

variable "lambda_handler" {
  description = "Handler entry point for the Phase 1 Lambda."
  type        = string
  default     = "handler.lambda_handler"
}

variable "lambda_runtime" {
  description = "Runtime for the Phase 1 Lambda."
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Timeout in seconds for the Phase 1 Lambda."
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Memory size in MB for the Phase 1 Lambda."
  type        = number
  default     = 512
}

variable "lambda_log_retention_days" {
  description = "Retention period for the Phase 1 Lambda CloudWatch log group."
  type        = number
  default     = 365
}

variable "eventbridge_maximum_event_age_in_seconds" {
  description = "Maximum event age before a failed delivery moves to the dead-letter queue."
  type        = number
  default     = 3600
}

variable "eventbridge_maximum_retry_attempts" {
  description = "Maximum EventBridge retry attempts before delivery moves to the dead-letter queue."
  type        = number
  default     = 24
}

variable "metadata_prefix" {
  description = "Prefix used for Phase 1 processing manifests."
  type        = string
  default     = "metadata"
}

variable "phase1_pipeline_version" {
  description = "Version string exposed to the Phase 1 Lambda environment."
  type        = string
  default     = "1.1.0"
}

variable "glue_database_name" {
  description = "Name of the Glue catalog database."
  type        = string
  default     = "streamforge_prod_clean_db"
}

variable "glue_database_description" {
  description = "Description of the Glue catalog database."
  type        = string
  default     = "Phase 2 Glue catalog for StreamForge clean customer data"
}

variable "glue_crawler_role_name" {
  description = "Name of the IAM role used by the Glue crawler."
  type        = string
  default     = "streamforge-prod-glue-crawler-role"
}

variable "glue_crawler_inline_policy_name" {
  description = "Name of the inline policy attached to the Glue crawler role."
  type        = string
  default     = "streamforge-prod-glue-clean-read"
}

variable "glue_crawler_name" {
  description = "Name of the Glue crawler."
  type        = string
  default     = "streamforge-prod-clean-crawler"
}

variable "glue_crawler_description" {
  description = "Description of the Glue crawler."
  type        = string
  default     = "Phase 2 crawler for StreamForge clean customer data"
}

variable "crawler_exclusions" {
  description = "Optional exclusions for the clean-data crawler."
  type        = list(string)
  default     = []
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup for clean CSV queries."
  type        = string
  default     = "streamforge-prod-phase2"
}

variable "athena_workgroup_description" {
  description = "Description of the Athena workgroup."
  type        = string
  default     = "Phase 2 Athena workgroup for StreamForge"
}

variable "athena_results_prefix" {
  description = "Prefix within the Athena results bucket."
  type        = string
  default     = "results/"
}

variable "clean_bucket_prefix" {
  description = "Optional prefix inside the clean bucket for the canonical table."
  type        = string
  default     = ""
}

variable "phase2_canonical_table_name" {
  description = "Name of the canonical Glue table for clean customer data."
  type        = string
  default     = "customers"
}

variable "phase3_glue_job_role_name" {
  description = "Name of the IAM role used by the Phase 3 Glue job."
  type        = string
  default     = "streamforge-prod-glue-transform-role"
}

variable "phase3_glue_job_inline_policy_name" {
  description = "Name of the inline IAM policy attached to the Phase 3 Glue job role."
  type        = string
  default     = "streamforge-prod-phase3-data-access"
}

variable "phase3_glue_job_name" {
  description = "Name of the Phase 3 Glue job."
  type        = string
  default     = "streamforge-prod-transform-customers"
}

variable "phase3_glue_job_description" {
  description = "Description of the Phase 3 Glue job."
  type        = string
  default     = ""
}

variable "phase3_glue_job_script_location" {
  description = "S3 URI of the deployed Phase 3 Glue job script."
  type        = string
  default     = "s3://streamforge-prod-metadata-ACCOUNTID-us-east-1/glue-assets/phase3/transform_job.py"
}

variable "phase3_glue_job_extra_py_files" {
  description = "S3 URI of the extra Python package ZIP used by the Phase 3 Glue job."
  type        = string
  default     = "s3://streamforge-prod-metadata-ACCOUNTID-us-east-1/glue-assets/phase3/jobs_package.zip"
}

variable "phase3_athena_workgroup_name" {
  description = "Name of the Phase 3 Athena workgroup."
  type        = string
  default     = "streamforge-prod-phase3"
}

variable "phase3_athena_workgroup_description" {
  description = "Description of the Phase 3 Athena workgroup."
  type        = string
  default     = "Phase 3 Athena workgroup for StreamForge"
}

variable "phase3_curated_table_name" {
  description = "Name of the Phase 3 curated Glue table."
  type        = string
  default     = "customers_curated"
}

variable "phase3_curated_prefix" {
  description = "Curated prefix used by the Phase 3 dataset and Glue job."
  type        = string
  default     = "customers"
}

variable "phase3_pipeline_version" {
  description = "Pipeline version exposed to the Phase 3 Glue job."
  type        = string
  default     = "3.0.0"
}

variable "phase3_max_invalid_percent" {
  description = "Maximum invalid-row percentage threshold passed to the Phase 3 Glue job."
  type        = string
  default     = "10"
}

variable "pipeline_metric_namespace" {
  description = "CloudWatch namespace used by the Phase 3 Glue job for quality metrics."
  type        = string
  default     = "StreamForge/Pipeline"
}

variable "operations_alert_topic_name" {
  description = "Name of the KMS-encrypted SNS topic for operational alerts."
  type        = string
  default     = "streamforge-prod-alerts"
}

variable "operations_alert_topic_display_name" {
  description = "Display name used in operational alert notifications."
  type        = string
  default     = "StreamForge Prod Alerts"
}

variable "operations_alert_email" {
  description = "Optional email recipient for operational alerts. AWS requires the recipient to confirm the subscription."
  type        = string
  default     = null
  nullable    = true
}

variable "eventbridge_dlq_name" {
  description = "Name of the KMS-encrypted SQS DLQ for failed raw-upload deliveries."
  type        = string
  default     = "streamforge-prod-eventbridge-dlq"
}

variable "eventbridge_dlq_message_retention_seconds" {
  description = "Retention period for undeliverable raw-upload events."
  type        = number
  default     = 1209600
}

variable "operations_alarm_period_seconds" {
  description = "CloudWatch alarm evaluation period in seconds."
  type        = number
  default     = 300
}

variable "bucket_name_overrides" {
  description = "Optional explicit bucket names keyed by raw, clean, rejected, metadata, curated, quarantine, athena_results."
  type        = map(string)
  default     = {}
}

variable "bucket_current_version_expiration_days_overrides" {
  description = "Optional current-version expiration overrides keyed by bucket logical name."
  type        = map(number)
  default     = {}
}

variable "bucket_noncurrent_version_expiration_days_overrides" {
  description = "Optional noncurrent-version expiration overrides keyed by bucket logical name."
  type        = map(number)
  default     = {}
}
