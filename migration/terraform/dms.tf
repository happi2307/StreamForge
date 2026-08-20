# =====================================================
# StreamForge Phase 6 - DMS Migration Infrastructure
# Terraform Module for Database Migration Service
# =====================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# =====================================================
# Variables
# =====================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "streamforge"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for DMS resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for DMS replication instance"
  type        = list(string)
}

variable "oracle_source_secret_arn" {
  description = "Secrets Manager ARN for Oracle source credentials"
  type        = string
}

variable "aurora_target_secret_arn" {
  description = "Secrets Manager ARN for Aurora PostgreSQL target credentials"
  type        = string
}

variable "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "replication_instance_class" {
  description = "DMS replication instance class"
  type        = string
  default     = "dms.t3.medium"
}

variable "allocated_storage" {
  description = "Storage allocated to replication instance (GB)"
  type        = number
  default     = 100
}

variable "migration_type" {
  description = "Migration type: full-load, cdc, or full-load-and-cdc"
  type        = string
  default     = "full-load-and-cdc"
}

variable "s3_reports_bucket" {
  description = "S3 bucket for migration reports"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# =====================================================
# Local Variables
# =====================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      Phase       = "phase6-migration"
      ManagedBy   = "terraform"
    }
  )
}

# =====================================================
# Data Sources
# =====================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_secretsmanager_secret_version" "oracle_source" {
  secret_id = var.oracle_source_secret_arn
}

data "aws_secretsmanager_secret_version" "aurora_target" {
  secret_id = var.aurora_target_secret_arn
}

# =====================================================
# Security Group for DMS
# =====================================================

resource "aws_security_group" "dms_replication" {
  name_prefix = "${local.name_prefix}-dms-replication-"
  description = "Security group for DMS replication instance"
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
      Name = "${local.name_prefix}-dms-replication-sg"
    }
  )
}

# =====================================================
# DMS Subnet Group
# =====================================================

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${local.name_prefix}-dms-subnet-group"
  replication_subnet_group_description = "DMS replication subnet group for ${var.environment}"
  subnet_ids                           = var.private_subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-dms-subnet-group"
    }
  )
}

# =====================================================
# DMS Replication Instance
# =====================================================

resource "aws_dms_replication_instance" "main" {
  replication_instance_id      = "${local.name_prefix}-dms-instance"
  replication_instance_class   = var.replication_instance_class
  allocated_storage            = var.allocated_storage
  engine_version               = "3.5.2"
  multi_az                     = false
  publicly_accessible          = false
  replication_subnet_group_id  = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids       = [aws_security_group.dms_replication.id]
  kms_key_arn                  = var.kms_key_arn
  auto_minor_version_upgrade   = true
  allow_major_version_upgrade  = false
  apply_immediately            = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-dms-replication-instance"
    }
  )
}

# =====================================================
# IAM Role for DMS
# =====================================================

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dms_access" {
  name_prefix        = "${local.name_prefix}-dms-access-"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "dms_permissions" {
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
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/dms/*"]
  }

  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${var.s3_reports_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "dms_permissions" {
  name_prefix = "dms-permissions-"
  role        = aws_iam_role.dms_access.id
  policy      = data.aws_iam_policy_document.dms_permissions.json
}

# =====================================================
# DMS Source Endpoint (Oracle)
# =====================================================

resource "aws_dms_endpoint" "oracle_source" {
  endpoint_id   = "${local.name_prefix}-oracle-source"
  endpoint_type = "source"
  engine_name   = "oracle"

  secrets_manager_arn              = var.oracle_source_secret_arn
  secrets_manager_access_role_arn  = aws_iam_role.dms_access.arn

  ssl_mode = "none"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-oracle-source-endpoint"
      Type = "source"
    }
  )

  depends_on = [aws_iam_role_policy.dms_permissions]
}

# =====================================================
# DMS Target Endpoint (Aurora PostgreSQL)
# =====================================================

resource "aws_dms_endpoint" "aurora_target" {
  endpoint_id   = "${local.name_prefix}-aurora-target"
  endpoint_type = "target"
  engine_name   = "aurora-postgresql"

  secrets_manager_arn              = var.aurora_target_secret_arn
  secrets_manager_access_role_arn  = aws_iam_role.dms_access.arn

  ssl_mode = "require"

  postgres_settings {
    max_file_size          = 512000
    execute_timeout        = 0
    fail_tasks_on_lob_truncation = false
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-aurora-target-endpoint"
      Type = "target"
    }
  )

  depends_on = [aws_iam_role_policy.dms_permissions]
}

# =====================================================
# DMS Replication Task
# =====================================================

resource "aws_dms_replication_task" "main" {
  replication_task_id      = "${local.name_prefix}-replication-task"
  migration_type           = var.migration_type
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.oracle_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.aurora_target.endpoint_arn

  table_mappings            = file("${path.module}/../dms/task_config/table_mappings.json")
  replication_task_settings = file("${path.module}/../dms/task_config/task_settings.json")

  start_replication_task = false

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-replication-task"
    }
  )

  depends_on = [
    aws_dms_endpoint.oracle_source,
    aws_dms_endpoint.aurora_target
  ]
}

# =====================================================
# CloudWatch Log Group for DMS
# =====================================================

resource "aws_cloudwatch_log_group" "dms_task" {
  name              = "/aws/dms/tasks/${local.name_prefix}-replication-task"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
}

# =====================================================
# EventBridge Rule for DMS Events
# =====================================================

resource "aws_cloudwatch_event_rule" "dms_task_state_change" {
  name_prefix = "${local.name_prefix}-dms-state-change-"
  description = "Capture DMS task state changes"

  event_pattern = jsonencode({
    source      = ["aws.dms"]
    detail-type = ["DMS Replication Task State Change"]
    detail = {
      eventName = [
        "DMS-EVENT-0079", # Task started
        "DMS-EVENT-0078", # Task stopped
        "DMS-EVENT-0077", # Task stopped with errors
        "DMS-EVENT-0049"  # Task completed
      ]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "dms_sns" {
  rule      = aws_cloudwatch_event_rule.dms_task_state_change.name
  target_id = "SendToSNS"
  arn       = var.sns_topic_arn
}

# =====================================================
# CloudWatch Alarms
# =====================================================

resource "aws_cloudwatch_metric_alarm" "dms_cpu_high" {
  alarm_name          = "${local.name_prefix}-dms-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "DMS replication instance CPU utilization is too high"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dms_memory_high" {
  alarm_name          = "${local.name_prefix}-dms-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "500000000" # 500 MB
  alarm_description   = "DMS replication instance freeable memory is too low"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dms_storage_high" {
  alarm_name          = "${local.name_prefix}-dms-storage-high"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000000000" # 10 GB
  alarm_description   = "DMS replication instance free storage is too low"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }

  tags = local.common_tags
}

# =====================================================
# Outputs
# =====================================================

output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_id
}

output "source_endpoint_arn" {
  description = "ARN of the Oracle source endpoint"
  value       = aws_dms_endpoint.oracle_source.endpoint_arn
}

output "target_endpoint_arn" {
  description = "ARN of the Aurora target endpoint"
  value       = aws_dms_endpoint.aurora_target.endpoint_arn
}

output "replication_task_arn" {
  description = "ARN of the DMS replication task"
  value       = aws_dms_replication_task.main.replication_task_arn
}

output "replication_task_id" {
  description = "ID of the DMS replication task"
  value       = aws_dms_replication_task.main.replication_task_id
}

output "dms_security_group_id" {
  description = "Security group ID for DMS replication instance"
  value       = aws_security_group.dms_replication.id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for DMS task"
  value       = aws_cloudwatch_log_group.dms_task.name
}
