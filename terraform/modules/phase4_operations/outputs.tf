output "alert_topic_arn" {
  description = "ARN of the encrypted SNS topic used for operational alerts."
  value       = aws_sns_topic.alerts.arn
}

output "eventbridge_dead_letter_queue_arn" {
  description = "ARN of the encrypted SQS queue holding undeliverable raw-upload events."
  value       = aws_sqs_queue.eventbridge_dlq.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for pipeline operations."
  value       = aws_cloudwatch_dashboard.pipeline.dashboard_name
}
