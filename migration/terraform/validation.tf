# =====================================================
# StreamForge Phase 6 - Validation Lambda Infrastructure
# Terraform Module for Migration Validation
# =====================================================

# =====================================================
# IAM Role for Validation Lambda
# =====================================================

data "aws_iam_policy_document" "validation_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "validation_lambda" {
  name_prefix        = "${local.name_prefix}-validation-lambda-"
  assume_role_policy = data.aws_iam_policy_document.validation_lambda_assume.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "validation_lambda_permissions" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-validation*"]
  }

  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      var.oracle_source_secret_arn,
      var.aurora_target_secret_arn
    ]
  }

  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [var.kms_key_arn]
  }

  statement {
    sid    = "S3ReportsAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = ["arn:aws:s3:::${var.s3_reports_bucket}/migration_reports/*"]
  }

  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["StreamForge/Migration"]
    }
  }

  statement {
    sid    = "VPCAccess"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "validation_lambda_permissions" {
  name_prefix = "validation-lambda-permissions-"
  role        = aws_iam_role.validation_lambda.id
  policy      = data.aws_iam_policy_document.validation_lambda_permissions.json
}

# =====================================================
# Security Group for Validation Lambda
# =====================================================

resource "aws_security_group" "validation_lambda" {
  name_prefix = "${local.name_prefix}-validation-lambda-"
  description = "Security group for migration validation Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-validation-lambda-sg"
    }
  )
}

# =====================================================
# Lambda Function Package (placeholder)
# =====================================================

data "archive_file" "validation_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../validation/lambda"
  output_path = "${path.module}/validation_lambda.zip"
}

# =====================================================
# Validation Lambda Function
# =====================================================

resource "aws_lambda_function" "validation" {
  function_name    = "${local.name_prefix}-migration-validation"
  description      = "Validates data integrity after Oracle to PostgreSQL migration"
  role             = aws_iam_role.validation_lambda.arn
  handler          = "validation_handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 900 # 15 minutes
  memory_size      = 2048
  filename         = data.archive_file.validation_lambda.output_path
  source_code_hash = data.archive_file.validation_lambda.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.validation_lambda.id]
  }

  environment {
    variables = {
      AURORA_SECRET_ARN     = var.aurora_target_secret_arn
      ORACLE_SECRET_ARN     = var.oracle_source_secret_arn
      S3_REPORTS_BUCKET     = var.s3_reports_bucket
      ENVIRONMENT           = var.environment
      LOG_LEVEL             = "INFO"
    }
  }

  reserved_concurrent_executions = 2

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-migration-validation"
    }
  )

  depends_on = [
    aws_iam_role_policy.validation_lambda_permissions,
    aws_cloudwatch_log_group.validation_lambda
  ]
}

# =====================================================
# CloudWatch Log Group for Validation Lambda
# =====================================================

resource "aws_cloudwatch_log_group" "validation_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-migration-validation"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
}

# =====================================================
# EventBridge Rule for Migration Complete
# =====================================================

resource "aws_cloudwatch_event_rule" "migration_complete" {
  name_prefix = "${local.name_prefix}-migration-complete-"
  description = "Trigger validation when migration completes"

  event_pattern = jsonencode({
    source      = ["aws.dms"]
    detail-type = ["DMS Replication Task State Change"]
    detail = {
      eventName = ["DMS-EVENT-0049"] # Task completed
      replicationTaskArn = [aws_dms_replication_task.main.replication_task_arn]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "validation_lambda" {
  rule      = aws_cloudwatch_event_rule.migration_complete.name
  target_id = "ValidationLambda"
  arn       = aws_lambda_function.validation.arn
}

resource "aws_lambda_permission" "eventbridge_validation" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.migration_complete.arn
}

# =====================================================
# CloudWatch Alarms for Validation
# =====================================================

resource "aws_cloudwatch_metric_alarm" "validation_errors" {
  alarm_name          = "${local.name_prefix}-validation-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Migration validation Lambda errors"
  alarm_actions       = [var.sns_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.validation.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "validation_duration" {
  alarm_name          = "${local.name_prefix}-validation-duration-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "840000" # 14 minutes (90% of timeout)
  alarm_description   = "Migration validation taking too long"
  alarm_actions       = [var.sns_topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.validation.function_name
  }

  tags = local.common_tags
}

# =====================================================
# Outputs
# =====================================================

output "validation_lambda_arn" {
  description = "ARN of the validation Lambda function"
  value       = aws_lambda_function.validation.arn
}

output "validation_lambda_name" {
  description = "Name of the validation Lambda function"
  value       = aws_lambda_function.validation.function_name
}

output "validation_security_group_id" {
  description = "Security group ID for validation Lambda"
  value       = aws_security_group.validation_lambda.id
}
