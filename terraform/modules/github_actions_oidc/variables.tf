variable "project_name" {
  description = "Project identifier used in resource names and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment represented by this role."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in owner/name form allowed to assume the role."
  type        = string
}

variable "github_environment" {
  description = "Protected GitHub environment required in the OIDC subject claim."
  type        = string
}

variable "role_name" {
  description = "Name of the GitHub Actions deployment role."
  type        = string
}

variable "state_bucket_name" {
  description = "Terraform remote-state bucket available to the deployment role."
  type        = string
}

variable "state_kms_key_arn" {
  description = "KMS key ARN that encrypts the Terraform remote-state bucket."
  type        = string
}

variable "lock_table_arn" {
  description = "Terraform state lock table ARN available to the deployment role."
  type        = string
}

variable "project_kms_key_arn" {
  description = "KMS key ARN used by the StreamForge environment."
  type        = string
}

variable "project_bucket_arns" {
  description = "S3 bucket ARNs the deployment role may manage."
  type        = list(string)
}

variable "worker_role_names" {
  description = "Runtime IAM roles the deployment role may configure and pass to Lambda or Glue."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to IAM resources."
  type        = map(string)
  default     = {}
}
