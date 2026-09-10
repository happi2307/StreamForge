# =====================================================
# StreamForge Phase 6 - Terraform Variables
# Configuration for migration validation infrastructure
# =====================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "streamforge"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID for validation Lambda resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the validation Lambda"
  type        = list(string)
}

variable "aurora_target_secret_arn" {
  description = "Secrets Manager ARN for Aurora PostgreSQL target credentials"
  type        = string
}

variable "aurora_cluster_endpoint" {
  description = "Aurora PostgreSQL cluster writer endpoint"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "s3_reports_bucket" {
  description = "S3 bucket name for migration reports"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
}

variable "validation_lambda_memory" {
  description = "Memory allocation for validation Lambda (MB)"
  type        = number
  default     = 2048
  validation {
    condition     = var.validation_lambda_memory >= 128 && var.validation_lambda_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "validation_lambda_timeout" {
  description = "Timeout for validation Lambda (seconds)"
  type        = number
  default     = 900
  validation {
    condition     = var.validation_lambda_timeout >= 60 && var.validation_lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period (days)"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Invalid log retention period."
  }
}

variable "enable_monitoring_dashboard" {
  description = "Enable CloudWatch dashboard for migration monitoring"
  type        = bool
  default     = true
}

variable "enable_validation" {
  description = "Enable automatic validation after migration"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Phase     = "Phase6"
  }
}
