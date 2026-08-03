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

output "cognito_client_xomcron_id" {
  description = "Cognito App Client ID for xomcron (crons.xomware.com)"
  value       = aws_cognito_user_pool_client.xomcron.id
}

# Phase 3 - users service + avatars + file-editor migration

output "users_api_url" {
  description = "Shared Xomware users service base URL"
  value       = "https://api.${local.domain_name}"
}

output "avatars_bucket_name" {
  description = "S3 bucket name for shared user avatars"
  value       = aws_s3_bucket.avatars.id
}

output "avatars_cdn_url" {
  description = "CloudFront CDN base URL for shared user avatars"
  value       = "https://cdn.${local.domain_name}"
}

output "file_editor_api_url_export" {
  description = "File Editor API base URL (Command Center backend)"
  value       = "https://editor-api.${local.domain_name}"
}

output "users_dynamodb_table" {
  description = "DynamoDB table for the users service"
  value       = aws_dynamodb_table.users.id
}
