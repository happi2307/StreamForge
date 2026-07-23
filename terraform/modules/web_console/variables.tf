variable "project_name" { type = string }
variable "environment" { type = string }
variable "lambda_function_name" { type = string }
variable "lambda_package_path" { type = string }
variable "raw_bucket_name" { type = string }
variable "raw_bucket_arn" { type = string }
variable "metadata_bucket_name" { type = string }
variable "metadata_bucket_arn" { type = string }
variable "clean_bucket_arn" { type = string }
variable "rejected_bucket_arn" { type = string }
variable "metadata_prefix" { type = string }
variable "kms_key_arn" { type = string }
variable "allowed_origins" { type = list(string) }
variable "tags" {
  type    = map(string)
  default = {}
}
