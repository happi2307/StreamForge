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

resource "aws_iam_role_policy" "data_plane" {
  name   = var.lambda_inline_policy_name
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_data_plane.json
}

resource "aws_lambda_function" "this" {
  function_name = var.lambda_function_name
  description   = var.lambda_description
  role          = aws_iam_role.lambda.arn
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler
  filename      = var.lambda_package_path
  publish       = false
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

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
    aws_iam_role_policy.data_plane,
  ]

  lifecycle {
    ignore_changes = [
      filename,
    ]
  }
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
