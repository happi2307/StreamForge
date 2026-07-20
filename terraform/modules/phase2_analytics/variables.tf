variable "project_name" {
  description = "Project identifier used for naming."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "glue_database_name" {
  description = "Name of the Glue catalog database."
  type        = string
}

variable "glue_database_description" {
  description = "Description of the Glue catalog database."
  type        = string
  default     = ""
}

variable "glue_crawler_role_name" {
  description = "Name of the IAM role used by the Glue crawler."
  type        = string
}

variable "glue_crawler_inline_policy_name" {
  description = "Name of the inline IAM policy attached to the Glue crawler role."
  type        = string
}

variable "glue_crawler_name" {
  description = "Name of the Glue crawler."
  type        = string
}

variable "glue_crawler_description" {
  description = "Description of the Glue crawler."
  type        = string
  default     = ""
}

variable "crawler_exclusions" {
  description = "Optional S3 crawler exclusions."
  type        = list(string)
  default     = []
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup."
  type        = string
}

variable "athena_workgroup_description" {
  description = "Description of the Athena workgroup."
  type        = string
  default     = ""
}

variable "athena_results_bucket_name" {
  description = "Name of the S3 bucket used for Athena query results."
  type        = string
}

variable "athena_results_prefix" {
  description = "Prefix used for Athena query results."
  type        = string
  default     = "results/"
}

variable "clean_bucket_name" {
  description = "Name of the clean CSV bucket."
  type        = string
}

variable "clean_bucket_arn" {
  description = "ARN of the clean CSV bucket."
  type        = string
}

variable "clean_bucket_prefix" {
  description = "Optional prefix within the clean bucket for the canonical table."
  type        = string
  default     = ""
}

variable "canonical_table_name" {
  description = "Name of the canonical Glue table for clean customer data."
  type        = string
  default     = "customers"
}

variable "kms_key_arn" {
  description = "KMS key ARN used for Athena output and crawler read access."
  type        = string
}

variable "tags" {
  description = "Tags applied to taggable analytics resources."
  type        = map(string)
  default     = {}
}
