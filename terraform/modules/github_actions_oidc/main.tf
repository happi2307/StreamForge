data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  github_oidc_url     = "https://token.actions.githubusercontent.com"
  github_oidc_host    = "token.actions.githubusercontent.com"
  deployment_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.role_name}"
  worker_role_arns = [
    for role_name in var.worker_role_names :
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${role_name}"
  ]
  project_bucket_object_arns = [
    for bucket_arn in var.project_bucket_arns :
    "${bucket_arn}/*"
  ]
  state_bucket_arn        = "arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket_name}"
  state_bucket_object_arn = "${local.state_bucket_arn}/*"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "AllowGitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${var.github_repository}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = local.github_oidc_url

  client_id_list = ["sts.amazonaws.com"]

  # GitHub Actions' documented OIDC certificate thumbprint. Keep this explicit
  # so the trust anchor is reviewable with the Terraform configuration.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, {
    Name    = "${var.project_name}-${var.environment}-github-actions-oidc"
    Service = "github-actions-oidc"
  })
}

resource "aws_iam_role" "deployment" {
  name                 = var.role_name
  description          = "GitHub Actions OIDC deployment role for ${var.github_repository} ${var.github_environment}."
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600
  tags = merge(var.tags, {
    Name    = var.role_name
    Service = "github-actions-deployment"
  })
}
