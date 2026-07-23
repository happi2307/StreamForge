data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  event_rule_arn = "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${var.event_rule_name}"
}

resource "aws_sns_topic" "alerts" {
  name              = var.alert_topic_name
  display_name      = var.alert_topic_display_name
  kms_master_key_id = var.kms_key_arn
  tags              = var.tags
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AllowAccountAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "SNS:AddPermission",
      "SNS:DeleteTopic",
      "SNS:GetTopicAttributes",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:RemovePermission",
      "SNS:SetTopicAttributes",
      "SNS:Subscribe",
    ]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAlarms"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowEventBridgePipelineAlerts"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values = [
        aws_cloudwatch_event_rule.glue_job_failures.arn,
        aws_cloudwatch_event_rule.athena_query_failures.arn,
      ]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sqs_queue" "eventbridge_dlq" {
  name                              = var.eventbridge_dlq_name
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300
  message_retention_seconds         = var.eventbridge_dlq_message_retention_seconds
  receive_wait_time_seconds         = 20
  tags                              = var.tags
}

data "aws_iam_policy_document" "eventbridge_dlq" {
  statement {
    sid    = "AllowEventBridgeDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.eventbridge_dlq.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.event_rule_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "eventbridge_dlq" {
  queue_url = aws_sqs_queue.eventbridge_dlq.id
  policy    = data.aws_iam_policy_document.eventbridge_dlq.json
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  alarm_description   = "Phase 1 Lambda reported one or more errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.name_prefix}-lambda-throttles"
  alarm_description   = "Phase 1 Lambda was throttled."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eventbridge_failed_invocations" {
  alarm_name          = "${var.name_prefix}-eventbridge-failed-invocations"
  alarm_description   = "EventBridge could not deliver a raw-upload event to the Phase 1 Lambda."
  namespace           = "AWS/Events"
  metric_name         = "FailedInvocations"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    RuleName = var.event_rule_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eventbridge_dlq_messages" {
  alarm_name          = "${var.name_prefix}-eventbridge-dlq-messages"
  alarm_description   = "The EventBridge dead-letter queue contains an undeliverable raw-upload event."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.eventbridge_dlq.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "high_quarantine_rate" {
  alarm_name          = "${var.name_prefix}-high-quarantine-rate"
  alarm_description   = "Phase 3 quarantined more records than the configured percentage threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.max_invalid_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "quarantined"
    return_data = false

    metric {
      namespace   = var.pipeline_metric_namespace
      metric_name = "RowsQuarantined"
      stat        = "Sum"
      period      = var.alarm_period_seconds
      dimensions = {
        Environment = var.environment
        JobName     = var.glue_job_name
      }
    }
  }

  metric_query {
    id          = "read"
    return_data = false

    metric {
      namespace   = var.pipeline_metric_namespace
      metric_name = "RowsRead"
      stat        = "Sum"
      period      = var.alarm_period_seconds
      dimensions = {
        Environment = var.environment
        JobName     = var.glue_job_name
      }
    }
  }

  metric_query {
    id          = "quarantine_rate"
    expression  = "IF(read > 0, 100 * quarantined / read, 0)"
    label       = "Quarantine rate (%)"
    return_data = true
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "glue_job_failures" {
  name        = "${var.name_prefix}-glue-job-failures"
  description = "Alert when the Phase 3 Glue job fails, times out, or is stopped."
  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Job Run Status"]
    detail = {
      jobName = [var.glue_job_name]
      state   = ["FAILED", "TIMEOUT", "STOPPED"]
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "glue_job_failures" {
  rule      = aws_cloudwatch_event_rule.glue_job_failures.name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn

  depends_on = [aws_sns_topic_policy.alerts]
}

resource "aws_cloudwatch_event_rule" "athena_query_failures" {
  name        = "${var.name_prefix}-athena-query-failures"
  description = "Alert when a StreamForge Athena query fails or is cancelled."
  event_pattern = jsonencode({
    source      = ["aws.athena"]
    detail-type = ["Athena Query State Change"]
    detail = {
      currentState = ["FAILED", "CANCELLED"]
      workgroupName = [
        var.phase2_athena_workgroup_name,
        var.phase3_athena_workgroup_name,
      ]
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "athena_query_failures" {
  rule      = aws_cloudwatch_event_rule.athena_query_failures.name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn

  depends_on = [aws_sns_topic_policy.alerts]
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.name_prefix}-pipeline"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Phase 1 Lambda health"
          region = data.aws_region.current.name
          stat   = "Sum"
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name],
            [".", "Throttles", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EventBridge delivery failures"
          region = data.aws_region.current.name
          stat   = "Sum"
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/Events", "FailedInvocations", "RuleName", var.event_rule_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title  = "Phase 3 data quality"
          region = data.aws_region.current.name
          stat   = "Sum"
          period = var.alarm_period_seconds
          metrics = [
            [var.pipeline_metric_namespace, "RowsRead", "Environment", var.environment, "JobName", var.glue_job_name],
            [".", "RowsWritten", ".", ".", ".", "."],
            [".", "RowsQuarantined", ".", ".", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "EventBridge dead-letter queue"
          region = data.aws_region.current.name
          stat   = "Maximum"
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.eventbridge_dlq.name],
          ]
        }
      },
    ]
  })
}
