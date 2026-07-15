variable "project_name" {
  description = "Project identifier used in names and tags."
  type        = string
  default     = "streamforge"
}

variable "environment" {
  description = "Environment label."
  type        = string
  default     = "dev"
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
  default     = "alias/streamforge-dev"
}

variable "kms_description" {
  description = "Description for the environment KMS key."
  type        = string
  default     = "KMS key for StreamForge dev data plane resources."
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
