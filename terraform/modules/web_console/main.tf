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
    variables = {
      RAW_BUCKET      = var.raw_bucket_name
      METADATA_BUCKET = var.metadata_bucket_name
      METADATA_PREFIX = var.metadata_prefix
    }
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

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "api-gateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
