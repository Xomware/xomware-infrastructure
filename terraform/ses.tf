# SES Email Identity Verification
# After terraform apply, AWS sends a verification email to noreply@xomware.com.
# Someone must click the verification link in that email to complete verification.

resource "aws_ses_email_identity" "noreply" {
  email = "noreply@xomware.com"
}
