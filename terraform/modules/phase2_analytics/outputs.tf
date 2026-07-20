output "glue_database_name" {
  description = "Name of the Glue catalog database."
  value       = aws_glue_catalog_database.this.name
}

output "glue_crawler_name" {
  description = "Name of the Glue crawler."
  value       = aws_glue_crawler.this.name
}

output "glue_crawler_role_name" {
  description = "Name of the Glue crawler IAM role."
  value       = aws_iam_role.crawler.name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup."
  value       = aws_athena_workgroup.this.name
}

output "canonical_table_name" {
  description = "Name of the canonical Glue table for clean customer data."
  value       = aws_glue_catalog_table.canonical_customers.name
}
