data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.subnet_cidrs))
}

# ---------------------------------------------------------------------------
# Networking — a private-only VPC for Aurora + the loader Lambda.
# No internet gateway or NAT: the Lambda reaches AWS APIs through VPC endpoints.
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.name_prefix}-phase5-vpc" })
}

resource "aws_subnet" "private" {
  count             = length(var.subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-phase5-private-${count.index + 1}"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-phase5-private" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -- Security groups --------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-phase5-loader"
  description = "Phase 5 loader Lambda egress to Aurora and VPC endpoints."
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-phase5-loader" })
}

resource "aws_security_group" "aurora" {
  name        = "${var.name_prefix}-phase5-aurora"
  description = "Aurora PostgreSQL cluster; accepts 5432 from the loader only."
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-phase5-aurora" })
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-phase5-endpoints"
  description = "Interface VPC endpoints; accept 443 from the loader."
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-phase5-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_lambda" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "PostgreSQL from the loader Lambda."
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_lambda" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from the loader Lambda to interface endpoints."
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_aurora" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "PostgreSQL to the Aurora cluster."
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.aurora.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_endpoints" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "HTTPS to interface VPC endpoints."
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_s3_prefix" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to S3 via the gateway endpoint prefix list."
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

# -- VPC endpoints (avoid NAT/internet) -------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = merge(var.tags, { Name = "${var.name_prefix}-phase5-s3" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(["secretsmanager", "kms", "logs", "sts", "monitoring"])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name_prefix}-phase5-${each.value}" })
}

# ---------------------------------------------------------------------------
# Aurora PostgreSQL Serverless v2
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-phase5-aurora"
  subnet_ids = aws_subnet.private[*].id
  tags       = var.tags
}

resource "aws_rds_cluster" "this" {
  #checkov:skip=CKV2_AWS_27:Query logging via Performance Insights/pgaudit is a follow-up hardening item tracked in docs; postgresql logs are already exported.
  cluster_identifier                  = "${var.name_prefix}-phase5"
  engine                              = "aurora-postgresql"
  engine_version                      = var.db_engine_version
  database_name                       = var.db_name
  master_username                     = var.db_master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.aurora.name
  vpc_security_group_ids              = [aws_security_group.aurora.id]
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  backup_retention_period             = var.db_backup_retention_days
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.db_deletion_protection
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  skip_final_snapshot                 = var.db_skip_final_snapshot
  final_snapshot_identifier           = var.db_skip_final_snapshot ? null : "${var.name_prefix}-phase5-final"

  serverlessv2_scaling_configuration {
    min_capacity = var.serverless_min_acu
    max_capacity = var.serverless_max_acu
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-phase5" })
}

resource "aws_rds_cluster_instance" "this" {
  identifier                      = "${var.name_prefix}-phase5-1"
  cluster_identifier              = aws_rds_cluster.this.id
  instance_class                  = "db.serverless"
  engine                          = aws_rds_cluster.this.engine
  engine_version                  = aws_rds_cluster.this.engine_version
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  publicly_accessible             = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  tags                            = var.tags
}

# ---------------------------------------------------------------------------
# Loader Lambda (in-VPC) + least-privilege IAM
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_data_plane" {
  statement {
    sid       = "ReadCuratedAndMetadata"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.curated_bucket_arn}/*", "${var.metadata_bucket_arn}/*"]
  }

  statement {
    sid       = "ReadDatabaseSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_rds_cluster.this.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "UseCustomerManagedKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "PublishAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.alert_topic_arn]
  }

  statement {
    sid       = "DeadLetterDelivery"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.loader_dlq.arn]
  }
}

resource "aws_iam_role" "lambda" {
  name               = var.loader_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_write" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "data_plane" {
  name   = var.loader_inline_policy_name
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_data_plane.json
}

resource "aws_sqs_queue" "loader_dlq" {
  name                              = "${var.loader_function_name}-async-dlq"
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300
  message_retention_seconds         = var.dlq_message_retention_seconds
  receive_wait_time_seconds         = 20
  tags                              = var.tags
}

data "aws_iam_policy_document" "loader_dlq" {
  statement {
    sid       = "AllowLambdaFailureDelivery"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.loader_dlq.arn]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.loader_function_name}"]
    }
  }
}

resource "aws_sqs_queue_policy" "loader_dlq" {
  queue_url = aws_sqs_queue.loader_dlq.id
  policy    = data.aws_iam_policy_document.loader_dlq.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.loader_function_name}"
  retention_in_days = var.loader_log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_lambda_function" "loader" {
  #checkov:skip=CKV_AWS_272:Code signing is deferred until CI signs release artifacts; CI builds packages from tracked source and the deployment role is restricted.
  function_name                  = var.loader_function_name
  description                    = var.loader_description
  role                           = aws_iam_role.lambda.arn
  runtime                        = var.loader_runtime
  handler                        = var.loader_handler
  filename                       = var.loader_package_path
  source_code_hash               = filebase64sha256(var.loader_package_path)
  publish                        = false
  timeout                        = var.loader_timeout
  memory_size                    = var.loader_memory_size
  kms_key_arn                    = var.kms_key_arn
  reserved_concurrent_executions = var.loader_reserved_concurrency

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.loader_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DB_SECRET_NAME   = aws_rds_cluster.this.master_user_secret[0].secret_arn
      DB_HOST          = aws_rds_cluster.this.endpoint
      DB_NAME          = var.db_name
      DB_SCHEMA        = var.db_schema
      SNS_TOPIC        = var.alert_topic_arn
      PIPELINE_VERSION = var.pipeline_version
      LOG_LEVEL        = var.log_level
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.vpc_access,
    aws_iam_role_policy_attachment.xray_write,
    aws_iam_role_policy.data_plane,
    aws_cloudwatch_log_group.lambda,
  ]

  lifecycle {
    ignore_changes = [filename]
  }
}

# ---------------------------------------------------------------------------
# Trigger — curated Parquet object created -> loader
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "curated_eventbridge" {
  bucket      = var.curated_bucket_id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "curated_objects" {
  name        = var.event_rule_name
  description = "Trigger the Phase 5 loader when curated Parquet is written."
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [var.curated_bucket_name] }
      object = { key = [{ suffix = ".parquet" }] }
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "loader" {
  rule      = aws_cloudwatch_event_rule.curated_objects.name
  target_id = var.event_target_id
  arn       = aws_lambda_function.loader.arn

  dead_letter_config {
    arn = aws_sqs_queue.loader_dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = var.eventbridge_maximum_event_age_in_seconds
    maximum_retry_attempts       = var.eventbridge_maximum_retry_attempts
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "eventbridge-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.loader.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.curated_objects.arn
}

# ---------------------------------------------------------------------------
# Monitoring — log-based metrics, alarms (reuse Phase 4 SNS topic), dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "records_failed" {
  name           = "${var.name_prefix}-phase5-records-failed"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "{ $.status = \"SUCCESS\" }"

  metric_transformation {
    name          = "RecordsFailed"
    namespace     = var.pipeline_metric_namespace
    value         = "$.records_failed"
    default_value = "0"
    dimensions = {
      Environment = "$.stage"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "records_inserted" {
  name           = "${var.name_prefix}-phase5-records-inserted"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "{ $.status = \"SUCCESS\" }"

  metric_transformation {
    name          = "RecordsInserted"
    namespace     = var.pipeline_metric_namespace
    value         = "$.records_inserted"
    default_value = "0"
    dimensions = {
      Environment = "$.stage"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "loader_errors" {
  alarm_name          = "${var.name_prefix}-phase5-loader-errors"
  alarm_description   = "The Phase 5 database loader reported one or more errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  dimensions          = { FunctionName = var.loader_function_name }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "loader_duration" {
  alarm_name          = "${var.name_prefix}-phase5-loader-duration"
  alarm_description   = "The Phase 5 loader exceeded its expected run duration."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  statistic           = "Maximum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = var.loader_duration_alarm_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  dimensions          = { FunctionName = var.loader_function_name }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "loader_dlq_messages" {
  alarm_name          = "${var.name_prefix}-phase5-loader-dlq-messages"
  alarm_description   = "An undeliverable curated-load event landed in the loader DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  dimensions          = { QueueName = aws_sqs_queue.loader_dlq.name }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "excessive_failed_records" {
  alarm_name          = "${var.name_prefix}-phase5-failed-records"
  alarm_description   = "The loader rejected more records than the configured threshold."
  namespace           = var.pipeline_metric_namespace
  metric_name         = "RecordsFailed"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  evaluation_periods  = 1
  threshold           = var.failed_records_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  dimensions          = { Environment = "database_loader" }
  tags                = var.tags
}

resource "aws_cloudwatch_dashboard" "phase5" {
  dashboard_name = "${var.name_prefix}-phase5-serving"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Loader health"
          region = data.aws_region.current.name
          stat   = "Sum"
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.loader_function_name],
            [".", "Errors", ".", "."],
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
          title  = "Loader duration (ms)"
          region = data.aws_region.current.name
          stat   = "Maximum"
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.loader_function_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Records loaded vs rejected"
          region = data.aws_region.current.name
          stat   = "Sum"
          period = var.alarm_period_seconds
          metrics = [
            [var.pipeline_metric_namespace, "RecordsInserted", "Environment", "database_loader"],
            [".", "RecordsFailed", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Aurora capacity & connections"
          region = data.aws_region.current.name
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/RDS", "ServerlessDatabaseCapacity", "DBClusterIdentifier", aws_rds_cluster.this.cluster_identifier, { stat = "Average" }],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.this.cluster_identifier, { stat = "Maximum" }],
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
          title  = "Loader dead-letter queue"
          region = data.aws_region.current.name
          stat   = "Maximum"
          period = var.alarm_period_seconds
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.loader_dlq.name],
          ]
        }
      },
    ]
  })
}
