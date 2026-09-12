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

# -- Portal (Phase 6) ---------------------------------------------------------

variable "lake_buckets" {
  description = "Lake zone name -> bucket name and ARN, read by the portal pages."
  type = map(object({
    name = string
    arn  = string
  }))
  default = {}
}

variable "glue_database" {
  description = "Glue Data Catalog database backing the Analytics page."
  type        = string
  default     = ""
}

variable "athena_workgroup" {
  description = "Athena workgroup used for portal analytics queries."
  type        = string
  default     = ""
}

variable "curated_table" {
  description = "Curated table name queried by the Analytics page."
  type        = string
  default     = "customers_curated"
}

variable "glue_job_name" {
  description = "Glue ETL job name shown on the Pipeline page."
  type        = string
  default     = ""
}

variable "processor_function_name" {
  description = "Phase 1 Lambda name, for the Monitoring page's metric queries."
  type        = string
  default     = ""
}

variable "aurora_cluster_arn" {
  description = "Aurora cluster ARN for the Warehouse page. Empty disables the page and its IAM grant."
  type        = string
  default     = ""
}

variable "aurora_secret_arn" {
  description = "Secrets Manager ARN holding the Aurora credentials."
  type        = string
  default     = ""
}

variable "aurora_database" {
  description = "Database name queried through the RDS Data API."
  type        = string
  default     = "streamforge"
}
