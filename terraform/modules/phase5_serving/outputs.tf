output "vpc_id" {
  description = "ID of the private Phase 5 VPC."
  value       = aws_vpc.this.id
}

output "cluster_endpoint" {
  description = "Writer endpoint of the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_identifier" {
  description = "Identifier of the Aurora cluster."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "database_secret_arn" {
  description = "ARN of the RDS-managed master credentials secret."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "aurora_security_group_id" {
  description = "Security group protecting the Aurora cluster."
  value       = aws_security_group.aurora.id
}

output "loader_function_name" {
  description = "Name of the database loader Lambda."
  value       = aws_lambda_function.loader.function_name
}

output "loader_role_name" {
  description = "Name of the loader Lambda IAM role."
  value       = aws_iam_role.lambda.name
}

output "loader_dead_letter_queue_arn" {
  description = "ARN of the loader dead-letter queue."
  value       = aws_sqs_queue.loader_dlq.arn
}

output "dashboard_name" {
  description = "Name of the Phase 5 CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.phase5.dashboard_name
}
