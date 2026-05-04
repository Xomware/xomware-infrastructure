# -------------------------------------------------------------------
# Google Identity Provider for the shared Xomware Cognito User Pool.
#
# Phase 4 of the auth epic. Federates Google sign-in for all Xomware
# apps. The PreSignUp Lambda trigger (see lambdas_users.tf
# `presignup_link`) auto-links a federating Google identity to an
# existing local Cognito user when emails match — preventing
# duplicate accounts.
#
# Manual prereq (Dom):
#   1. Create an OAuth 2.0 Client in Google Cloud Console
#      (APIs & Services -> Credentials -> Create Credentials ->
#      OAuth client ID, Application type "Web").
#   2. Authorized redirect URIs:
#        https://xomware-auth.auth.us-east-1.amazoncognito.com/oauth2/idpresponse
#   3. Authorized JavaScript origins:
#        https://xomware.com
#        https://xn--xomapptit-g4a.xomware.com
#        https://xomappetit.xomware.com
#   4. Save, then write the credentials to SSM. Easiest path:
#        ./scripts/setup-google-oauth-ssm.sh
#      Or by hand:
#        /xomware/shared/google-oauth/client-id     (String)
#        /xomware/shared/google-oauth/client-secret (SecureString)
#
# Terraform reads those SSM params via the data sources below — apply
# will FAIL until both params exist. That's intentional: it stops a
# half-configured IdP from being attached to the live pool.
# -------------------------------------------------------------------

data "aws_ssm_parameter" "google_oauth_client_id" {
  name            = "/xomware/shared/google-oauth/client-id"
  with_decryption = true
}

data "aws_ssm_parameter" "google_oauth_client_secret" {
  name            = "/xomware/shared/google-oauth/client-secret"
  with_decryption = true
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.xomware_users.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = data.aws_ssm_parameter.google_oauth_client_id.value
    client_secret    = data.aws_ssm_parameter.google_oauth_client_secret.value
    authorize_scopes = "profile email openid"
  }

  # Map Google claims -> Cognito user pool attributes.
  # `email` is the critical one: the PreSignUp link trigger uses it
  # to find a matching local user before federation creates a new row.
  attribute_mapping = {
    email       = "email"
    name        = "name"
    given_name  = "given_name"
    family_name = "family_name"
    picture     = "picture"
    username    = "sub"
  }
}
