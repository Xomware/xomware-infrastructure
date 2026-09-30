# armchair-users: the Armchair app family's own pool, separate from xomware-users
# so it gets its own provider-type Google IdP slot and custom-domain slot. Same
# ownership model as the shared pool: clients live here, apps read SSM.
#
# Manual prereq (Dom): a Google Cloud OAuth client (Web) with redirect URI
#   https://armchair-auth.auth.us-east-1.amazoncognito.com/oauth2/idpresponse
# and its credentials in SSM:
#   /armchair/shared/google-oauth/client-id     (String)
#   /armchair/shared/google-oauth/client-secret (SecureString)
# Plan and apply fail until both exist, same as cognito_google_idp.tf.

locals {
  armchair_tags = merge(local.standard_tags, {
    "environment" = "shared"
    "project"     = "armchair"
    "owner"       = "xomware"
  })
}

resource "aws_cognito_user_pool" "armchair_users" {
  name = "armchair-users"

  # Cognito has no undelete; losing the pool loses every account.
  deletion_protection = "ACTIVE"

  user_pool_tier    = "ESSENTIALS"
  mfa_configuration = "OFF"

  # Google-only sign-in: there are no native passwords to recover.
  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = local.armchair_tags

  lifecycle {
    ignore_changes = [tags_all]
  }
}

resource "aws_cognito_user_pool_domain" "armchair_auth" {
  domain       = "armchair-auth"
  user_pool_id = aws_cognito_user_pool.armchair_users.id
}

data "aws_ssm_parameter" "armchair_google_oauth_client_id" {
  name            = "/armchair/shared/google-oauth/client-id"
  with_decryption = true
}

data "aws_ssm_parameter" "armchair_google_oauth_client_secret" {
  name            = "/armchair/shared/google-oauth/client-secret"
  with_decryption = true
}

resource "aws_cognito_identity_provider" "armchair_google" {
  user_pool_id  = aws_cognito_user_pool.armchair_users.id
  provider_name = "Google"
  provider_type = "Google"

  # The keys after authorize_scopes are what Cognito fills in server-side for
  # provider_type Google; pinned so plans don't propose dropping them.
  provider_details = {
    client_id        = data.aws_ssm_parameter.armchair_google_oauth_client_id.value
    client_secret    = data.aws_ssm_parameter.armchair_google_oauth_client_secret.value
    authorize_scopes = "profile email openid"

    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    given_name     = "given_name"
    family_name    = "family_name"
    picture        = "picture"
    username       = "sub"
  }
}

resource "aws_cognito_user_pool_client" "armchair_dwts" {
  name         = "armchair-dwts-client"
  user_pool_id = aws_cognito_user_pool.armchair_users.id

  generate_secret = false

  # No SRP: Google is the only way in, so there is no password flow to allow.
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = [
    "https://dwts.xomware.com/auth/callback",
    "http://localhost:3000/auth/callback",
    "http://127.0.0.1:3000/auth/callback",
  ]

  logout_urls = [
    "https://dwts.xomware.com",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
  ]

  supported_identity_providers = ["Google"]

  depends_on = [aws_cognito_identity_provider.armchair_google]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 30

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

# Public-by-design values (they ship in the bundle), so String, as in cognito_ssm.tf.
resource "aws_ssm_parameter" "armchair_cognito_user_pool_arn" {
  name        = "/armchair/shared/cognito/user-pool-arn"
  description = "Armchair Cognito User Pool ARN"
  type        = "String"
  value       = aws_cognito_user_pool.armchair_users.arn
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_user_pool_id" {
  name        = "/armchair/shared/cognito/user-pool-id"
  description = "Armchair Cognito User Pool ID"
  type        = "String"
  value       = aws_cognito_user_pool.armchair_users.id
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_user_pool_jwks_url" {
  name        = "/armchair/shared/cognito/user-pool-jwks-url"
  description = "Armchair Cognito User Pool JWKS URL"
  type        = "String"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.armchair_users.id}/.well-known/jwks.json"
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_hosted_ui_domain" {
  name        = "/armchair/shared/cognito/hosted-ui-domain"
  description = "Armchair Cognito Hosted UI domain (FQDN)"
  type        = "String"
  value       = "${aws_cognito_user_pool_domain.armchair_auth.domain}.auth.${var.aws_region}.amazoncognito.com"
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_client_dwts_id" {
  name        = "/armchair/shared/cognito/clients/dwts-id"
  description = "Cognito App Client ID for the DWTS companion (dwts.xomware.com)"
  type        = "String"
  value       = aws_cognito_user_pool_client.armchair_dwts.id
  tags        = local.armchair_tags
}
