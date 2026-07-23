data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_data_plane" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${var.raw_bucket_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${var.clean_bucket_arn}/*",
      "${var.rejected_bucket_arn}/*",
      "${var.metadata_bucket_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [
      var.kms_key_arn,
    ]
  }
}

data "aws_iam_policy_document" "eventbridge_invoke_lambda" {
  statement {
    sid    = "AllowEventBridgeInvoke"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [
      aws_lambda_function.this.arn,
    ]
    condition {
      test     = "ArnEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudwatch_event_rule.raw_uploads.arn]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_write" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "data_plane" {
  name   = var.lambda_inline_policy_name
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_data_plane.json
}

resource "aws_sqs_queue" "lambda_async_dlq" {
  name                              = "${var.lambda_function_name}-async-dlq"
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300
  message_retention_seconds         = var.lambda_dead_letter_queue_message_retention_seconds
  receive_wait_time_seconds         = 20
  tags                              = var.tags
}

data "aws_iam_policy_document" "lambda_async_dlq" {
  statement {
    sid    = "AllowLambdaFailureDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_async_dlq.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_lambda_function.this.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "lambda_async_dlq" {
  queue_url = aws_sqs_queue.lambda_async_dlq.id
  policy    = data.aws_iam_policy_document.lambda_async_dlq.json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_117: This ingestion Lambda accesses only managed AWS services; a VPC would add NAT/endpoints without reducing data-plane exposure.
  #checkov:skip=CKV_AWS_272: Code signing is deferred until CI signs release artifacts; CI builds packages from tracked source and the deployment role is restricted.
  function_name                  = var.lambda_function_name
  description                    = var.lambda_description
  role                           = aws_iam_role.lambda.arn
  runtime                        = var.lambda_runtime
  handler                        = var.lambda_handler
  filename                       = var.lambda_package_path
  source_code_hash               = filebase64sha256(var.lambda_package_path)
  publish                        = false
  timeout                        = var.lambda_timeout
  memory_size                    = var.lambda_memory_size
  kms_key_arn                    = var.kms_key_arn
  reserved_concurrent_executions = var.lambda_reserved_concurrent_executions

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_async_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      CLEAN_BUCKET            = var.clean_bucket_name
      REJECTED_BUCKET         = var.rejected_bucket_name
      METADATA_BUCKET         = var.metadata_bucket_name
      METADATA_PREFIX         = var.metadata_prefix
      PHASE1_PIPELINE_VERSION = var.phase1_pipeline_version
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy_attachment.xray_write,
    aws_iam_role_policy.data_plane,
  ]

  lifecycle {
    ignore_changes = [
      filename,
    ]
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.lambda_log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_cloudwatch_event_rule" "raw_uploads" {
  name        = var.event_rule_name
  description = var.event_rule_description
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.raw_bucket_name]
      }
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.raw_uploads.name
  target_id = var.event_target_id
  arn       = aws_lambda_function.this.arn

  dead_letter_config {
    arn = var.eventbridge_dead_letter_queue_arn
  }

  retry_policy {
    maximum_event_age_in_seconds = var.eventbridge_maximum_event_age_in_seconds
    maximum_retry_attempts       = var.eventbridge_maximum_retry_attempts
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "eventbridge-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.raw_uploads.arn
}

resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket = var.raw_bucket_id

  eventbridge = true

  depends_on = [aws_cloudwatch_event_target.lambda]
}
