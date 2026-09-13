data "aws_region" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_access" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${var.raw_bucket_arn}/uploads/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.metadata_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.metadata_prefix}/uploads/*"]
    }
  }
  statement {
    actions = ["s3:GetObject"]
    resources = [
      "${var.metadata_bucket_arn}/${var.metadata_prefix}/*",
      "${var.clean_bucket_arn}/uploads/*",
      "${var.rejected_bucket_arn}/uploads/*",
    ]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }

  # -- Read-only access for the portal pages --------------------------------

  statement {
    sid       = "PortalListLakeZones"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [for bucket in var.lake_buckets : bucket.arn]
  }

  statement {
    sid       = "PortalReadManifests"
    actions   = ["s3:GetObject"]
    resources = ["${var.metadata_bucket_arn}/*"]
  }

  statement {
    sid       = "PortalBucketConfiguration"
    actions   = ["s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration"]
    resources = [for bucket in var.lake_buckets : bucket.arn]
  }

  statement {
    sid       = "PortalCatalogRead"
    actions   = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartitions", "glue:GetJobRuns", "glue:GetJobRun"]
    resources = ["*"]
  }

  statement {
    sid = "PortalAthenaQueries"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
    ]
    resources = ["*"]
  }

  # Athena writes results to its workgroup bucket and reads the curated data.
  statement {
    sid       = "PortalAthenaResults"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload"]
    resources = [for key, bucket in var.lake_buckets : "${bucket.arn}/*" if contains(["curated", "athena_results"], key)]
  }

  statement {
    sid       = "PortalCloudWatchRead"
    actions   = ["cloudwatch:GetMetricData", "cloudwatch:DescribeAlarms", "cloudwatch:ListMetrics"]
    resources = ["*"]
  }
}

# Aurora access is only granted when Phase 5 is deployed, so the portal role
# stays minimal in environments without a serving layer.
data "aws_iam_policy_document" "aurora_access" {
  count = var.enable_warehouse ? 1 : 0

  statement {
    sid       = "PortalWarehouseRead"
    actions   = ["rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement"]
    resources = [var.aurora_cluster_arn]
  }

  statement {
    sid       = "PortalWarehouseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.aurora_secret_arn]
  }
}

resource "aws_iam_role_policy" "aurora_access" {
  count = var.enable_warehouse ? 1 : 0

  name_prefix = "portal-warehouse-"
  role        = aws_iam_role.lambda.id
  policy      = data.aws_iam_policy_document.aurora_access[0].json
}

resource "aws_iam_role" "lambda" {
  name               = "${var.lambda_function_name}-role"
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

resource "aws_iam_role_policy" "storage_access" {
  name   = "${var.lambda_function_name}-storage"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_access.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}-dashboard-api"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_lambda_function" "api" {
  #checkov:skip=CKV_AWS_116: API Gateway invokes this function synchronously; there is no asynchronous payload for a Lambda DLQ to retain.
  #checkov:skip=CKV_AWS_117: The API only accesses managed AWS services and does not need private network resources.
  #checkov:skip=CKV_AWS_272: Code signing is deferred until CI signs release artifacts; CI builds packages from tracked source and the deployment role is restricted.
  function_name                  = var.lambda_function_name
  role                           = aws_iam_role.lambda.arn
  runtime                        = "python3.12"
  handler                        = "dashboard_api.lambda_handler"
  filename                       = var.lambda_package_path
  source_code_hash               = filebase64sha256(var.lambda_package_path)
  timeout                        = 15
  memory_size                    = 256
  kms_key_arn                    = var.kms_key_arn
  reserved_concurrent_executions = 5

  tracing_config {
    mode = "Active"
  }

  environment {
    # Portal values are merged in so an environment without Phase 5, Glue or
    # Athena simply omits them and the affected pages report "not configured".
    variables = merge(
      {
        RAW_BUCKET      = var.raw_bucket_name
        METADATA_BUCKET = var.metadata_bucket_name
        METADATA_PREFIX = var.metadata_prefix
      },
      { for zone, bucket in var.lake_buckets : "${upper(replace(zone, "-", "_"))}_BUCKET" => bucket.name },
      { for key, value in {
        GLUE_DATABASE           = var.glue_database
        ATHENA_WORKGROUP        = var.athena_workgroup
        CURATED_TABLE           = var.curated_table
        GLUE_JOB_NAME           = var.glue_job_name
        PROCESSOR_FUNCTION_NAME = var.processor_function_name
        DASHBOARD_FUNCTION_NAME = var.lambda_function_name
        AURORA_CLUSTER_ARN      = var.aurora_cluster_arn
        AURORA_SECRET_ARN       = var.aurora_secret_arn
        AURORA_DATABASE         = var.aurora_database
      } : key => value if value != "" },
    )
  }

  tags = var.tags
  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy_attachment.xray_write,
    aws_iam_role_policy.storage_access,
  ]
}

resource "aws_cognito_user_pool" "this" {
  name                     = "${var.project_name}-${var.environment}-dashboard-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  tags = var.tags
}

resource "aws_cognito_user_pool_client" "dashboard" {
  name                                 = "${var.project_name}-${var.environment}-dashboard"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid"]
  callback_urls                        = var.allowed_origins
  logout_urls                          = var.allowed_origins
  supported_identity_providers         = ["COGNITO"]
  prevent_user_existence_errors        = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "dashboard" {
  domain       = "${var.project_name}-${var.environment}-dashboard-${data.aws_region.current.name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project_name}-${var.environment}-dashboard-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 300
  }
  tags = var.tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.dashboard.id]
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "uploads" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /uploads"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "status" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /status"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Read-only portal endpoints, served by portal_api.py. Same JWT authorizer as
# the upload routes -- none of these are public.
resource "aws_apigatewayv2_route" "portal" {
  for_each = toset([
    "dashboard",
    "storage",
    "metadata",
    "lineage",
    "metrics",
    "pipeline",
    "analytics",
    "warehouse",
    "etl",
  ])

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /api/${each.value}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      request_id        = "$context.requestId"
      source_ip         = "$context.identity.sourceIp"
      request_time      = "$context.requestTime"
      http_method       = "$context.httpMethod"
      route_key         = "$context.routeKey"
      status            = "$context.status"
      protocol          = "$context.protocol"
      response_length   = "$context.responseLength"
      integration_error = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "api-gateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
