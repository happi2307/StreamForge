variable "name_prefix" {
  description = "Prefix used for operations resources and alarms."
  type        = string
}

variable "environment" {
  description = "Environment dimension written with pipeline-quality metrics."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer managed KMS key ARN used to encrypt SNS and SQS resources."
  type        = string
}

variable "alert_topic_name" {
  description = "Name of the SNS topic used for operational alerts."
  type        = string
}

variable "alert_topic_display_name" {
  description = "Display name for alert messages delivered through SNS."
  type        = string
}

variable "alert_email" {
  description = "Optional email address subscribed to operational alerts. AWS requires recipient confirmation."
  type        = string
  default     = null
  nullable    = true
}

variable "eventbridge_dlq_name" {
  description = "Name of the encrypted SQS dead-letter queue for failed EventBridge deliveries."
  type        = string
}

variable "eventbridge_dlq_message_retention_seconds" {
  description = "How long failed EventBridge events remain available for investigation."
  type        = number
  default     = 1209600
}

variable "event_rule_name" {
  description = "Name of the Phase 1 EventBridge rule that delivers raw-upload events."
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Phase 1 Lambda function monitored by alarms."
  type        = string
}

variable "glue_job_name" {
  description = "Name of the Phase 3 Glue job monitored by event rules and data-quality alarms."
  type        = string
}

variable "phase2_athena_workgroup_name" {
  description = "Phase 2 Athena workgroup whose failed queries should raise an alert."
  type        = string
}

variable "phase3_athena_workgroup_name" {
  description = "Phase 3 Athena workgroup whose failed queries should raise an alert."
  type        = string
}

variable "pipeline_metric_namespace" {
  description = "CloudWatch namespace used by the Glue job for pipeline-quality metrics."
  type        = string
  default     = "StreamForge/Pipeline"
}

variable "max_invalid_percent" {
  description = "Quarantine-rate percentage that triggers an operational alarm."
  type        = number
  default     = 10
}

variable "alarm_period_seconds" {
  description = "CloudWatch evaluation and dashboard period in seconds."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags applied to taggable operations resources."
  type        = map(string)
  default     = {}
}
