output "glue_job_role_name" {
  description = "Name of the IAM role used by the Phase 3 Glue job."
  value       = aws_iam_role.job.name
}

output "glue_job_name" {
  description = "Name of the Phase 3 Glue job."
  value       = aws_glue_job.this.name
}

output "athena_workgroup_name" {
  description = "Name of the Phase 3 Athena workgroup."
  value       = aws_athena_workgroup.this.name
}

output "curated_table_name" {
  description = "Name of the curated Glue table."
  value       = aws_glue_catalog_table.curated.name
}
