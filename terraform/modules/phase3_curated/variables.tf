variable "project_name" {
  description = "Project identifier used for naming."
  type        = string
}

variable "environment" {
  description = "Environment label."
  type        = string
}

variable "glue_database_name" {
  description = "Name of the shared Glue catalog database."
  type        = string
}

variable "glue_job_role_name" {
  description = "Name of the IAM role used by the Phase 3 Glue job."
  type        = string
}

variable "glue_job_inline_policy_name" {
  description = "Name of the inline IAM policy attached to the Phase 3 Glue role."
  type        = string
}

variable "glue_job_name" {
  description = "Name of the Phase 3 Glue job."
  type        = string
}

variable "glue_job_description" {
  description = "Description of the Phase 3 Glue job."
  type        = string
  default     = ""
}

variable "glue_job_timeout" {
  description = "Glue job timeout in minutes."
  type        = number
  default     = 2880
}

variable "glue_job_glue_version" {
  description = "Glue version for the Phase 3 job."
  type        = string
  default     = "4.0"
}

variable "glue_job_worker_type" {
  description = "Worker type for the Phase 3 job."
  type        = string
  default     = "G.1X"
}

variable "glue_job_number_of_workers" {
  description = "Number of workers for the Phase 3 job."
  type        = number
  default     = 2
}

variable "glue_job_max_concurrent_runs" {
  description = "Maximum concurrent job runs."
  type        = number
  default     = 1
}

variable "glue_job_script_location" {
  description = "S3 URI of the deployed Glue job script."
  type        = string
}

variable "glue_job_extra_py_files" {
  description = "S3 URI of the extra Python package ZIP used by the Glue job."
  type        = string
}

variable "athena_workgroup_name" {
  description = "Name of the Phase 3 Athena workgroup."
  type        = string
}

variable "athena_workgroup_description" {
  description = "Description of the Phase 3 Athena workgroup."
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

variable "curated_table_name" {
  description = "Name of the curated Glue catalog table."
  type        = string
  default     = "customers_curated"
}

variable "curated_table_location" {
  description = "S3 location of the curated dataset root."
  type        = string
}

variable "clean_bucket_name" {
  description = "Name of the clean CSV bucket."
  type        = string
}

variable "clean_bucket_arn" {
  description = "ARN of the clean CSV bucket."
  type        = string
}

variable "metadata_bucket_name" {
  description = "Name of the metadata bucket."
  type        = string
}

variable "metadata_bucket_arn" {
  description = "ARN of the metadata bucket."
  type        = string
}

variable "curated_bucket_name" {
  description = "Name of the curated bucket."
  type        = string
}

variable "curated_bucket_arn" {
  description = "ARN of the curated bucket."
  type        = string
}

variable "quarantine_bucket_name" {
  description = "Name of the quarantine bucket."
  type        = string
}

variable "quarantine_bucket_arn" {
  description = "ARN of the quarantine bucket."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used by the Phase 3 job and Athena workgroup."
  type        = string
}

variable "metadata_prefix" {
  description = "Metadata prefix consumed by the Phase 3 Glue job."
  type        = string
  default     = "metadata"
}

variable "curated_prefix" {
  description = "Curated prefix used by the Phase 3 Glue job."
  type        = string
  default     = "customers"
}

variable "pipeline_version" {
  description = "Pipeline version exposed to the Phase 3 Glue job."
  type        = string
  default     = "3.0.0"
}

variable "max_invalid_percent" {
  description = "Maximum invalid-row percentage threshold passed to the Phase 3 Glue job."
  type        = string
  default     = "10"
}

variable "pipeline_metric_namespace" {
  description = "CloudWatch namespace used by the Glue job for pipeline-quality metrics."
  type        = string
  default     = "StreamForge/Pipeline"
}

variable "tags" {
  description = "Tags applied to taggable Phase 3 resources."
  type        = map(string)
  default     = {}
}
