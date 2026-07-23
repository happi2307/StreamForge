output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives operational alerts."
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS alerts topic."
  value       = aws_sns_topic.alerts.name
}

output "lambda_alarm_names" {
  description = "Names of the CloudWatch alarms watching the Phase 1 Lambda."
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_throttles.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_duration.alarm_name,
  ]
}

output "glue_failure_rule_name" {
  description = "Name of the EventBridge rule capturing Glue job failures."
  value       = aws_cloudwatch_event_rule.glue_job_failed.name
}
