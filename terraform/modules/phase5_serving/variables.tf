variable "name_prefix" {
  description = "Prefix for resource names, e.g. streamforge-dev."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for Aurora, secrets, and logs."
  type        = string
}

# -- Networking -------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the private Phase 5 VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidrs" {
  description = "CIDR blocks for the private subnets (one per AZ, minimum two)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]

  validation {
    condition     = length(var.subnet_cidrs) >= 2
    error_message = "Aurora requires at least two subnets across availability zones."
  }
}

# -- Aurora -----------------------------------------------------------------
variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "streamforge"
}

variable "db_schema" {
  description = "Primary schema passed to the loader (documentation/config only)."
  type        = string
  default     = "analytics"
}

variable "db_master_username" {
  description = "Aurora master username (password is managed in Secrets Manager)."
  type        = string
  default     = "streamforge_admin"
}

variable "db_engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "serverless_min_acu" {
  description = "Minimum Aurora Serverless v2 capacity units."
  type        = number
  default     = 0.5
}

variable "serverless_max_acu" {
  description = "Maximum Aurora Serverless v2 capacity units."
  type        = number
  default     = 4
}

variable "db_backup_retention_days" {
  description = "Automated backup retention period in days."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Enable deletion protection on the cluster."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on cluster destroy (dev convenience)."
  type        = bool
  default     = true
}

# -- Source data ------------------------------------------------------------
variable "curated_bucket_name" {
  description = "Name of the Phase 3 curated bucket."
  type        = string
}

variable "curated_bucket_arn" {
  description = "ARN of the Phase 3 curated bucket."
  type        = string
}

variable "curated_bucket_id" {
  description = "ID of the curated bucket (for the EventBridge notification)."
  type        = string
}

variable "metadata_bucket_arn" {
  description = "ARN of the Phase 1 metadata bucket the loader may read."
  type        = string
}

# -- Alerting / metrics -----------------------------------------------------
variable "alert_topic_arn" {
  description = "ARN of the existing Phase 4 SNS alert topic."
  type        = string
}

variable "pipeline_metric_namespace" {
  description = "CloudWatch namespace for custom pipeline metrics."
  type        = string
}

variable "pipeline_version" {
  description = "Pipeline version stamped onto loaded records."
  type        = string
  default     = "5.0.0"
}

variable "log_level" {
  description = "Loader log level."
  type        = string
  default     = "INFO"
}

# -- Loader Lambda ----------------------------------------------------------
variable "loader_function_name" {
  description = "Name of the database loader Lambda function."
  type        = string
}

variable "loader_description" {
  description = "Description of the loader Lambda."
  type        = string
  default     = "StreamForge Phase 5 curated-to-Aurora database loader."
}

variable "loader_role_name" {
  description = "Name of the loader Lambda IAM role."
  type        = string
}

variable "loader_inline_policy_name" {
  description = "Name of the loader inline IAM policy."
  type        = string
}

variable "loader_package_path" {
  description = "Path to the loader deployment archive (database-loader.zip)."
  type        = string
}

variable "loader_handler" {
  description = "Loader Lambda handler entry point."
  type        = string
  default     = "handler.lambda_handler"
}

variable "loader_runtime" {
  description = "Loader Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "loader_timeout" {
  description = "Loader Lambda timeout in seconds."
  type        = number
  default     = 120
}

variable "loader_memory_size" {
  description = "Loader Lambda memory size in MB."
  type        = number
  default     = 512
}

variable "loader_reserved_concurrency" {
  description = "Reserved concurrency; 1 serialises a batch's part-file events."
  type        = number
  default     = 1
}

variable "loader_log_retention_days" {
  description = "Loader log-group retention in days."
  type        = number
  default     = 30
}

# -- EventBridge ------------------------------------------------------------
variable "event_rule_name" {
  description = "Name of the EventBridge rule for curated object creation."
  type        = string
}

variable "event_target_id" {
  description = "Target ID for the loader EventBridge target."
  type        = string
  default     = "phase5-database-loader"
}

variable "dlq_message_retention_seconds" {
  description = "Retention for the loader dead-letter queue."
  type        = number
  default     = 1209600
}

variable "eventbridge_maximum_event_age_in_seconds" {
  description = "Maximum event age before EventBridge stops retrying."
  type        = number
  default     = 3600
}

variable "eventbridge_maximum_retry_attempts" {
  description = "Maximum EventBridge retry attempts before DLQ."
  type        = number
  default     = 3
}

# -- Alarms -----------------------------------------------------------------
variable "alarm_period_seconds" {
  description = "Evaluation period for CloudWatch alarms/widgets."
  type        = number
  default     = 300
}

variable "loader_duration_alarm_ms" {
  description = "Loader duration alarm threshold in milliseconds."
  type        = number
  default     = 60000
}

variable "failed_records_threshold" {
  description = "Failed-record count above which the alarm fires."
  type        = number
  default     = 10
}
