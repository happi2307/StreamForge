variable "bucket_name" {
  description = "Name of the bucket."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used for default server-side encryption."
  type        = string
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Whether Terraform may delete non-empty buckets."
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Whether bucket versioning is enabled."
  type        = bool
  default     = true
}

variable "attach_tls_only_policy" {
  description = "Whether to attach a deny-insecure-transport bucket policy."
  type        = bool
  default     = true
}

variable "lifecycle_rule_enabled" {
  description = "Whether to create the default lifecycle rule."
  type        = bool
  default     = true
}

variable "current_version_expiration_days" {
  description = "Optional expiration period for current object versions."
  type        = number
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Optional expiration period for noncurrent object versions."
  type        = number
  default     = 90
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which incomplete multipart uploads are aborted."
  type        = number
  default     = 7
}
