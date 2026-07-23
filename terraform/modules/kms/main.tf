data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "key_policy" {
  policy_id = var.policy_id

  statement {
    sid    = var.root_permissions_sid
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.service_key_access

    content {
      sid    = statement.value.sid
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = statement.value.principals
      }

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [statement.value.via_service]
      }
    }
  }

  dynamic "statement" {
    for_each = var.direct_service_key_access

    content {
      sid    = statement.value.sid
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = statement.value.principals
      }

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudwatch_logs_encryption_context_arns) > 0 ? [1] : []

    content {
      sid    = "AllowCloudWatchLogsEncryption"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
      }

      actions = [
        "kms:Decrypt*",
        "kms:Describe*",
        "kms:Encrypt*",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = ["*"]

      condition {
        test     = "ArnEquals"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = var.cloudwatch_logs_encryption_context_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV_AWS_109: A KMS key policy must use Resource "*" for the key it governs; access is constrained by principals and scoped IAM policies.
  #checkov:skip=CKV_AWS_111: KMS key policies require Resource "*" and cannot scope kms:* to this key ARN within the policy document.
  #checkov:skip=CKV_AWS_356: KMS requires Resource "*" in its key policy; the account-root principal delegates use only through scoped IAM policies.
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  policy                  = data.aws_iam_policy_document.key_policy.json
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = var.alias_name
  target_key_id = aws_kms_key.this.key_id
}
