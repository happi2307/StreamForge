output "deployment_role_arn" {
  description = "ARN for GitHub's AWS_ROLE_TO_ASSUME environment variable."
  value       = aws_iam_role.deployment.arn
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN in this AWS account."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
