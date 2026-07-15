variable "alias_name" {
  description = "KMS alias name, for example alias/streamforge-dev."
  type        = string
}

variable "description" {
  description = "Description for the customer managed KMS key."
  type        = string
}

variable "policy_id" {
  description = "Policy Id for the KMS key policy document."
  type        = string
  default     = "key-default-1"
}

variable "root_permissions_sid" {
  description = "SID for the root-permissions statement in the KMS key policy."
  type        = string
  default     = "Enable IAM User Permissions"
}

variable "deletion_window_in_days" {
  description = "Number of days before a scheduled KMS key deletion is executed."
  type        = number
  default     = 30
}

variable "enable_key_rotation" {
  description = "Whether automatic annual key rotation is enabled."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the KMS key."
  type        = map(string)
  default     = {}
}
