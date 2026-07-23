output "api_endpoint" { value = aws_apigatewayv2_stage.default.invoke_url }
output "user_pool_id" { value = aws_cognito_user_pool.this.id }
output "user_pool_client_id" { value = aws_cognito_user_pool_client.dashboard.id }
output "cognito_domain" { value = aws_cognito_user_pool_domain.dashboard.domain }
output "lambda_log_group_arn" { value = aws_cloudwatch_log_group.lambda.arn }
