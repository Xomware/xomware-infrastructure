# Outputs mirror the SSM parameter exports for visibility in
# `terraform output` and the GitHub Actions plan logs.

output "cognito_user_pool_arn" {
  description = "Shared Xomware Cognito User Pool ARN"
  value       = aws_cognito_user_pool.xomware_users.arn
}

output "cognito_user_pool_id" {
  description = "Shared Xomware Cognito User Pool ID"
  value       = aws_cognito_user_pool.xomware_users.id
}

output "cognito_user_pool_jwks_url" {
  description = "Shared Xomware Cognito User Pool JWKS URL"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.xomware_users.id}/.well-known/jwks.json"
}

output "cognito_hosted_ui_domain" {
  description = "Shared Xomware Cognito Hosted UI domain (FQDN)"
  value       = "${aws_cognito_user_pool_domain.xomware_auth.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_client_xomware_com_id" {
  description = "Cognito App Client ID for xomware.com"
  value       = aws_cognito_user_pool_client.xomware_com.id
}

output "cognito_client_xomappetit_id" {
  description = "Cognito App Client ID for xomappetit"
  value       = aws_cognito_user_pool_client.xomappetit.id
}
