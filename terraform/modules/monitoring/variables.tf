variable "project_name" {
  description = "Project identifier used in names and tags."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "sns_topic_name" {
  description = "Name of the SNS topic that receives operational alerts."
  type        = string
}

variable "sns_topic_display_name" {
  description = "Human-friendly display name for the SNS alerts topic."
  type        = string
  default     = "StreamForge Alerts"
}

variable "notification_email" {
  description = "Email address subscribed to the alerts topic. Leave empty to skip creating a subscription."
  type        = string
  default     = ""
}

variable "sns_kms_master_key_id" {
  description = "KMS key id or alias used to encrypt the SNS topic. Null leaves the topic unencrypted. The key policy must allow cloudwatch.amazonaws.com and events.amazonaws.com to use it."
  type        = string
  default     = null
}

variable "lambda_function_name" {
  description = "Name of the Phase 1 Lambda function the alarms observe."
  type        = string
}

variable "lambda_error_threshold" {
  description = "Number of Lambda errors in a period that triggers the errors alarm."
  type        = number
  default     = 1
}

variable "lambda_throttle_threshold" {
  description = "Number of Lambda throttles in a period that triggers the throttles alarm."
  type        = number
  default     = 1
}

variable "lambda_duration_threshold_ms" {
  description = "Maximum Lambda duration in milliseconds that triggers the duration alarm."
  type        = number
  default     = 45000
}

variable "alarm_period_seconds" {
  description = "Evaluation period in seconds for the Lambda alarms."
  type        = number
  default     = 300
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which the Lambda alarms are evaluated."
  type        = number
  default     = 1
}

variable "glue_job_name" {
  description = "Name of the Phase 3 Glue job monitored for failure states."
  type        = string
}

variable "glue_failure_rule_name" {
  description = "Name of the EventBridge rule that captures Glue job failures."
  type        = string
}

variable "glue_failure_states" {
  description = "Glue job states that are treated as failures for alerting."
  type        = list(string)
  default     = ["FAILED", "TIMEOUT", "ERROR"]
}

variable "tags" {
  description = "Tags applied to the monitoring resources."
  type        = map(string)
  default     = {}
}
