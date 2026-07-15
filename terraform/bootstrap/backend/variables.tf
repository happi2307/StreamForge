variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
  default     = "streamforge"
}

variable "environment" {
  description = "Environment label for backend resources."
  type        = string
  default     = "shared"
}

variable "aws_region" {
  description = "AWS region for backend resources."
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

variable "backend_bucket_name" {
  description = "Optional explicit backend bucket name override."
  type        = string
  default     = ""
}

variable "lock_table_name" {
  description = "Optional explicit DynamoDB lock table name override."
  type        = string
  default     = ""
}

variable "kms_alias_name" {
  description = "Optional explicit backend KMS alias override."
  type        = string
  default     = ""
}
