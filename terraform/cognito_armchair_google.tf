# Google sign-in for armchair-users and the DWTS app client.
#
# Armchair has its own Google OAuth client, in its own Google Cloud project, so
# the consent screen carries Armchair's name and logo rather than Xomware's.
# Manual prereq (Dom): that client (Web) with redirect URI
#   https://armchair-auth.auth.us-east-1.amazoncognito.com/oauth2/idpresponse
# and its credentials in SSM:
#   /armchair/shared/google-oauth/client-id     (String)
#   /armchair/shared/google-oauth/client-secret (SecureString)
# Plan and apply fail until both exist, same as cognito_google_idp.tf.

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

resource "aws_ssm_parameter" "armchair_cognito_client_dwts_id" {
  name        = "/armchair/shared/cognito/clients/dwts-id"
  description = "Cognito App Client ID for the DWTS companion (dwts.xomware.com)"
  type        = "String"
  value       = aws_cognito_user_pool_client.armchair_dwts.id
  tags        = local.armchair_tags
}
