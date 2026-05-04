#!/usr/bin/env bash
#
# Write the Google OAuth client credentials to SSM so the Phase 4 Terraform
# (cognito_google_idp.tf) can read them. Run this ONCE, locally, with AWS
# credentials that have ssm:PutParameter on /xomware/shared/google-oauth/*.
#
# Manual prereq:
#   1. Create an OAuth 2.0 Client in Google Cloud Console
#      (APIs & Services -> Credentials -> Create Credentials ->
#      OAuth client ID, Application type "Web").
#   2. Authorized redirect URIs:
#        https://xomware-auth.auth.us-east-1.amazoncognito.com/oauth2/idpresponse
#   3. Authorized JavaScript origins:
#        https://xomware.com
#        https://xn--xomapptit-g4a.xomware.com
#        https://xomappetit.xomware.com
#   4. Run this script and paste the values when prompted.
#
# After this completes, terraform apply will read the params via
# data.aws_ssm_parameter and provision the Google IdP on the pool.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PARAM_ID="/xomware/shared/google-oauth/client-id"
PARAM_SECRET="/xomware/shared/google-oauth/client-secret"

echo "Writing Google OAuth credentials to SSM in region: ${REGION}"
echo

# Sanity-check creds before prompting for secrets.
if ! aws sts get-caller-identity --region "${REGION}" >/dev/null 2>&1; then
  echo "ERROR: aws sts get-caller-identity failed. Check AWS credentials." >&2
  exit 1
fi

read -r -p "Google OAuth client ID: " CLIENT_ID
if [[ -z "${CLIENT_ID}" ]]; then
  echo "ERROR: client ID cannot be empty." >&2
  exit 1
fi

# -s suppresses echo so the secret never lands in scrollback.
read -r -s -p "Google OAuth client secret: " CLIENT_SECRET
echo
if [[ -z "${CLIENT_SECRET}" ]]; then
  echo "ERROR: client secret cannot be empty." >&2
  exit 1
fi

echo
echo "Writing ${PARAM_ID} (String)..."
aws ssm put-parameter \
  --region "${REGION}" \
  --name "${PARAM_ID}" \
  --type "String" \
  --value "${CLIENT_ID}" \
  --overwrite \
  --tags 'Key=app,Value=xomware' 'Key=purpose,Value=google-oauth' \
  >/dev/null

echo "Writing ${PARAM_SECRET} (SecureString)..."
aws ssm put-parameter \
  --region "${REGION}" \
  --name "${PARAM_SECRET}" \
  --type "SecureString" \
  --value "${CLIENT_SECRET}" \
  --overwrite \
  --tags 'Key=app,Value=xomware' 'Key=purpose,Value=google-oauth' \
  >/dev/null

# Tags only apply on first put — silently no-op on update. That's fine.
unset CLIENT_SECRET

echo
echo "Verifying read-back..."
aws ssm get-parameter \
  --region "${REGION}" \
  --name "${PARAM_ID}" \
  --query 'Parameter.Name' \
  --output text
aws ssm get-parameter \
  --region "${REGION}" \
  --name "${PARAM_SECRET}" \
  --with-decryption \
  --query 'Parameter.Name' \
  --output text

echo
echo "Done. You can now run 'terraform apply' on this branch."
echo "Next: merge xomware-infrastructure#33, then xomware-frontend#112,"
echo "      then xomappetit-frontend#13."
