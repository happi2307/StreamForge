output "lambda_function_name" {
  description = "Name of the Phase 1 Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Phase 1 Lambda function."
  value       = aws_lambda_function.this.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role used by the Phase 1 Lambda function."
  value       = aws_iam_role.lambda.name
}

output "event_rule_name" {
  description = "Name of the EventBridge rule for raw uploads."
  value       = aws_cloudwatch_event_rule.raw_uploads.name
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule for raw uploads."
  value       = aws_cloudwatch_event_rule.raw_uploads.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group used by the Phase 1 Lambda function."
  value       = aws_cloudwatch_log_group.lambda.name
}
