variable "project_name" {
  description = "Project identifier used for naming."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Phase 1 Lambda function."
  type        = string
}

variable "lambda_description" {
  description = "Description of the Phase 1 Lambda function."
  type        = string
  default     = ""
}

variable "lambda_role_name" {
  description = "Name of the IAM role used by the Phase 1 Lambda function."
  type        = string
}

variable "lambda_inline_policy_name" {
  description = "Name of the inline IAM policy attached to the Phase 1 Lambda role."
  type        = string
}

variable "event_rule_name" {
  description = "Name of the EventBridge rule that routes raw-bucket uploads to Lambda."
  type        = string
}

variable "event_rule_description" {
  description = "Description of the EventBridge rule."
  type        = string
  default     = ""
}

variable "event_target_id" {
  description = "Identifier used for the EventBridge target."
  type        = string
  default     = "phase1-lambda"
}

variable "lambda_package_path" {
  description = "Path to the deployment ZIP used when creating or updating the Lambda function."
  type        = string
}

variable "lambda_handler" {
  description = "Lambda handler entry point."
  type        = string
  default     = "handler.lambda_handler"
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 256
}

variable "lambda_reserved_concurrent_executions" {
  description = "Maximum concurrent Phase 1 Lambda executions; limits blast radius during upload spikes."
  type        = number
  default     = 5
}

variable "lambda_dead_letter_queue_message_retention_seconds" {
  description = "How long asynchronous Lambda failures remain available for investigation."
  type        = number
  default     = 1209600
}

variable "lambda_log_retention_days" {
  description = "Retention period for the Phase 1 Lambda CloudWatch log group."
  type        = number
  default     = 30
}

variable "eventbridge_dead_letter_queue_arn" {
  description = "ARN of the SQS queue used when EventBridge cannot deliver a raw-upload event."
  type        = string
}

variable "eventbridge_maximum_event_age_in_seconds" {
  description = "Maximum age of a raw-upload event before EventBridge sends it to the dead-letter queue."
  type        = number
  default     = 3600
}

variable "eventbridge_maximum_retry_attempts" {
  description = "Maximum delivery attempts before EventBridge sends a raw-upload event to the dead-letter queue."
  type        = number
  default     = 24
}

variable "raw_bucket_name" {
  description = "Name of the raw input bucket."
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw input bucket."
  type        = string
}

variable "raw_bucket_id" {
  description = "ID of the raw input bucket."
  type        = string
}

variable "clean_bucket_name" {
  description = "Name of the clean output bucket."
  type        = string
}

variable "clean_bucket_arn" {
  description = "ARN of the clean output bucket."
  type        = string
}

variable "rejected_bucket_name" {
  description = "Name of the rejected output bucket."
  type        = string
}

variable "rejected_bucket_arn" {
  description = "ARN of the rejected output bucket."
  type        = string
}

variable "metadata_bucket_name" {
  description = "Name of the metadata-manifest bucket."
  type        = string
}

variable "metadata_bucket_arn" {
  description = "ARN of the metadata-manifest bucket."
  type        = string
}

variable "metadata_prefix" {
  description = "Prefix used for Phase 1 manifest objects."
  type        = string
  default     = "metadata"
}

variable "phase1_pipeline_version" {
  description = "Version string exposed to the Phase 1 Lambda environment."
  type        = string
  default     = "1.1.0"
}

variable "kms_key_arn" {
  description = "KMS key ARN used by the project buckets."
  type        = string
}

variable "tags" {
  description = "Tags applied to Phase 1 runtime resources."
  type        = map(string)
  default     = {}
}
