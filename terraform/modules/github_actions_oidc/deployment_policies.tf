# IAM roles have a 10,240-character aggregate limit for inline policies. These
# customer-managed policies keep each concern independently reviewable and can
# be attached without exceeding that role-level constraint.
data "aws_iam_policy_document" "state_and_storage" {
  statement {
    sid    = "ReadTerraformState"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = [
      local.state_bucket_arn,
      local.state_bucket_object_arn,
    ]
  }

  statement {
    sid       = "ListBucketsForTerraform"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageStreamForgeBuckets"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteBucketCors",
      "s3:DeleteBucketEncryption",
      "s3:DeleteBucketLifecycle",
      "s3:DeleteBucketLogging",
      "s3:DeleteBucketOwnershipControls",
      "s3:DeleteBucketPolicy",
      "s3:DeleteBucketPublicAccessBlock",
      "s3:DeleteBucketTagging",
      "s3:DeleteBucketWebsite",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketLocation",
      "s3:GetBucketLogging",
      "s3:GetBucketNotification",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPolicyStatus",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketRequestPayment",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketWebsite",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions",
      "s3:ListMultipartUploadParts",
      "s3:PutBucketAcl",
      "s3:PutBucketCors",
      "s3:PutBucketEncryption",
      "s3:PutBucketLifecycleConfiguration",
      "s3:PutBucketLogging",
      "s3:PutBucketNotification",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:PutObjectTagging",
    ]
    resources = concat(var.project_bucket_arns, local.project_bucket_object_arns)
  }

  statement {
    sid    = "LockTerraformState"
    effect = "Allow"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
    ]
    resources = [var.lock_table_arn]
  }
}

data "aws_iam_policy_document" "keys_and_iam" {
  statement {
    sid    = "UseProjectAndStateKeys"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:DisableKeyRotation",
      "kms:EnableKeyRotation",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListGrants",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:RevokeGrant",
      "kms:TagResource",
      "kms:UntagResource",
    ]
    resources = [
      var.project_kms_key_arn,
      var.state_kms_key_arn,
    ]
  }

  statement {
    sid       = "ListKmsConfiguration"
    effect    = "Allow"
    actions   = ["kms:ListAliases", "kms:ListKeyPolicies"]
    resources = ["*"]
  }

  statement {
    sid       = "ManageProjectKeyAlias"
    effect    = "Allow"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/streamforge-*"]
  }

  statement {
    sid    = "ReadStreamForgeIamConfiguration"
    effect = "Allow"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
    ]
    resources = concat(
      local.worker_role_arns,
      [local.deployment_role_arn],
      ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"],
      ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"],
      ["arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"],
    )
  }

  statement {
    sid    = "ManageWorkerIamRoles"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = local.worker_role_arns
  }

  statement {
    sid       = "PassOnlyWorkerRolesToAwsServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.worker_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["glue.amazonaws.com", "lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "ReadAccountConfigurationForTerraform"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
      "iam:ListRoles",
      "iam:SimulatePrincipalPolicy",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "runtime_and_observability" {
  statement {
    sid    = "ManageStreamForgeLambdas"
    effect = "Allow"
    actions = [
      "lambda:AddPermission",
      "lambda:DeleteFunctionConcurrency",
      "lambda:DeleteFunctionUrlConfig",
      "lambda:DeleteProvisionedConcurrencyConfig",
      "lambda:GetAlias",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetFunctionConcurrency",
      "lambda:GetFunctionConfiguration",
      "lambda:GetPolicy",
      "lambda:GetProvisionedConcurrencyConfig",
      "lambda:ListAliases",
      "lambda:ListProvisionedConcurrencyConfigs",
      "lambda:ListTags",
      "lambda:PutFunctionConcurrency",
      "lambda:PutFunctionCodeSigningConfig",
      "lambda:PutProvisionedConcurrencyConfig",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:streamforge-*"]
  }

  statement {
    sid    = "ManageStreamForgeLogGroups"
    effect = "Allow"
    actions = [
      "logs:AssociateKmsKey",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:ListTagsForResource",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/streamforge-*",
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/streamforge-*",
      "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:aws-waf-logs-streamforge-*",
    ]
  }

  statement {
    sid       = "ReadLogGroupConfiguration"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageStreamForgeEventing"
    effect = "Allow"
    actions = [
      "events:DeleteRule",
      "events:DescribeRule",
      "events:ListRuleNamesByTarget",
      "events:ListRules",
      "events:ListTagsForResource",
      "events:ListTargetsByRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/streamforge-*"]
  }

  statement {
    sid    = "ManageStreamForgeQueuesAndAlerts"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTagsForResource",
      "sns:Publish",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:TagResource",
      "sns:Unsubscribe",
      "sns:UntagResource",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ListQueueTags",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:streamforge-*",
      "arn:${data.aws_partition.current.partition}:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:streamforge-*",
    ]
  }

  statement {
    sid    = "ManageCloudWatchAlarmsAndDashboards"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetDashboard",
      "cloudwatch:GetMetricData",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:PutDashboard",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "analytics_and_dashboard" {
  statement {
    sid    = "ManageStreamForgeGlueAndAthena"
    effect = "Allow"
    actions = [
      "athena:GetWorkGroup",
      "athena:ListTagsForResource",
      "athena:UpdateWorkGroup",
      "glue:GetCatalogImportStatus",
      "glue:GetCrawler",
      "glue:GetDatabase",
      "glue:GetJob",
      "glue:GetTable",
      "glue:GetTags",
      "glue:TagResource",
      "glue:UntagResource",
      "glue:UpdateCrawler",
      "glue:UpdateJob",
      "glue:UpdateSecurityConfiguration",
      "glue:UpdateTable",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/streamforge-*",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/streamforge_*",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/streamforge_*/*",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/streamforge-*",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/streamforge-*",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:securityConfiguration/streamforge-*",
    ]
  }

  statement {
    sid       = "ReadGlueSecurityConfigurations"
    effect    = "Allow"
    actions   = ["glue:GetSecurityConfiguration"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageDashboardIdentityAndApi"
    effect = "Allow"
    actions = [
      "apigateway:DELETE",
      "apigateway:GET",
      "apigateway:HEAD",
      "apigateway:PATCH",
      "apigateway:POST",
      "apigateway:PUT",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:GetUserPoolMfaConfig",
      "cognito-idp:ListTagsForResource",
      "cognito-idp:UpdateUserPool",
      "cognito-idp:UpdateUserPoolClient",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:apigateway:${data.aws_region.current.name}::/apis/*",
      "arn:${data.aws_partition.current.partition}:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/*",
    ]
  }

  statement {
    sid       = "ReadCognitoUserPoolDomains"
    effect    = "Allow"
    actions   = ["cognito-idp:DescribeUserPoolDomain"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageDashboardEdgeResources"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:ListTagsForResource",
      "cloudfront:TagResource",
      "cloudfront:UpdateDistribution",
      "wafv2:AssociateWebACL",
      "wafv2:CreateWebACL",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:DisassociateWebACL",
      "wafv2:GetLoggingConfiguration",
      "wafv2:GetWebACL",
      "wafv2:ListTagsForResource",
      "wafv2:PutLoggingConfiguration",
      "wafv2:TagResource",
      "wafv2:UpdateWebACL",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*",
      "arn:${data.aws_partition.current.partition}:cloudfront::${data.aws_caller_identity.current.account_id}:origin-access-control/*",
      "arn:${data.aws_partition.current.partition}:cloudfront::${data.aws_caller_identity.current.account_id}:response-headers-policy/*",
      "arn:${data.aws_partition.current.partition}:wafv2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:global/webacl/streamforge-*/*",
    ]
  }
}

locals {
  deployment_policy_documents = {
    state-and-storage         = data.aws_iam_policy_document.state_and_storage.json
    keys-and-iam              = data.aws_iam_policy_document.keys_and_iam.json
    runtime-and-observability = data.aws_iam_policy_document.runtime_and_observability.json
    analytics-and-dashboard   = data.aws_iam_policy_document.analytics_and_dashboard.json
  }
}

resource "aws_iam_policy" "deployment" {
  for_each = local.deployment_policy_documents

  name        = "${var.role_name}-${each.key}"
  description = "${each.key} permissions for the StreamForge GitHub Actions deployment role."
  policy      = each.value
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "deployment" {
  for_each = aws_iam_policy.deployment

  role       = aws_iam_role.deployment.name
  policy_arn = each.value.arn
}
