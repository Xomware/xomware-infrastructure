# SSM Parameter Store exports for the shared Cognito User Pool.
# Consumer apps (xomappetit-infrastructure, future apps) read these
# via `data "aws_ssm_parameter"` rather than crossing repo boundaries.
#
# These values are public-by-design (frontend bundles ship the client
# IDs and pool ID), so type = "String" is appropriate. No SecureString.

resource "aws_ssm_parameter" "cognito_user_pool_arn" {
  name        = "/xomware/shared/cognito/user-pool-arn"
  description = "Shared Xomware Cognito User Pool ARN"
  type        = "String"
  value       = aws_cognito_user_pool.xomware_users.arn

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "cognito_user_pool_id" {
  name        = "/xomware/shared/cognito/user-pool-id"
  description = "Shared Xomware Cognito User Pool ID"
  type        = "String"
  value       = aws_cognito_user_pool.xomware_users.id

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "cognito_user_pool_jwks_url" {
  name        = "/xomware/shared/cognito/user-pool-jwks-url"
  description = "Shared Xomware Cognito User Pool JWKS URL"
  type        = "String"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.xomware_users.id}/.well-known/jwks.json"

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "cognito_hosted_ui_domain" {
  name        = "/xomware/shared/cognito/hosted-ui-domain"
  description = "Shared Xomware Cognito Hosted UI domain (FQDN)"
  type        = "String"
  value       = "${aws_cognito_user_pool_domain.xomware_auth.domain}.auth.${var.aws_region}.amazoncognito.com"

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "cognito_client_xomware_com_id" {
  name        = "/xomware/shared/cognito/clients/xomware-com-id"
  description = "Cognito App Client ID for xomware.com"
  type        = "String"
  value       = aws_cognito_user_pool_client.xomware_com.id

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "cognito_client_xomappetit_id" {
  name        = "/xomware/shared/cognito/clients/xomappetit-id"
  description = "Cognito App Client ID for xomappetit"
  type        = "String"
  value       = aws_cognito_user_pool_client.xomappetit.id

  lifecycle { ignore_changes = [tags, tags_all] }
}
