#**********************
# Terraform roles for uncle-mikes-pickem
#**********************
#
# Same bootstrap as oidc_reeses_terraform.tf, which carries the full reasoning:
# a new app stack cannot create the IAM roles its own pipeline assumes, so they
# live here. Plan is read-only from any ref; apply is admin from main only.

locals {
  # Both subject forms are required -- this org emits the numeric enterprise
  # subject, and the plain form alone fails AssumeRoleWithWebIdentity.
  pickem_terraform_subjects = [
    "repo:Xomware/uncle-mikes-pickem",
    "repo:Xomware@263047999/uncle-mikes-pickem@1455587180",
  ]
  pickem_default_branch = "main"
}

data "aws_iam_policy_document" "pickem_terraform_plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in local.pickem_terraform_subjects : "${s}:*"]
    }
  }
}

data "aws_iam_policy_document" "pickem_terraform_apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in local.pickem_terraform_subjects : "${s}:ref:refs/heads/${local.pickem_default_branch}"]
    }
  }
}

resource "aws_iam_role" "pickem_terraform_plan" {
  name               = "pickem-github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.pickem_terraform_plan_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "pickem-github-actions-terraform-plan" }))
}

resource "aws_iam_role" "pickem_terraform_apply" {
  name               = "pickem-github-actions-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.pickem_terraform_apply_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "pickem-github-actions-terraform-apply" }))
}

resource "aws_iam_role_policy_attachment" "pickem_terraform_plan" {
  role       = aws_iam_role.pickem_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "pickem_terraform_apply" {
  role       = aws_iam_role.pickem_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Reuses the reeses guardrail document: the deny list is identical, and a second
# copy would drift.
resource "aws_iam_role_policy" "pickem_terraform_apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.pickem_terraform_apply.id
  policy = data.aws_iam_policy_document.reeses_terraform_apply_guardrails.json
}

resource "aws_iam_role_policy" "pickem_terraform_plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.pickem_terraform_plan.id
  policy = data.aws_iam_policy_document.reeses_terraform_plan_state_lock.json
}

# ReadOnlyAccess can read an SSM SecureString but not decrypt it, so a plan
# refreshing pickem's SecureStrings (GOW link and unsubscribe secrets) fails. Decrypt is limited to SSM and
# to that app's parameters.
data "aws_iam_policy_document" "pickem_terraform_plan_decrypt" {
  statement {
    sid       = "DecryptOwnSecureStrings"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = ["arn:aws:ssm:${var.aws_region}:${local.web_app_account_id}:parameter/pickem/*"]
    }
  }
}

resource "aws_iam_role_policy" "pickem_terraform_plan_decrypt" {
  name   = "decrypt-pickem-secure-strings"
  role   = aws_iam_role.pickem_terraform_plan.id
  policy = data.aws_iam_policy_document.pickem_terraform_plan_decrypt.json
}

output "pickem_terraform_plan_role_arn" {
  description = "Read-only role the uncle-mikes-pickem Terraform workflow assumes for plans"
  value       = aws_iam_role.pickem_terraform_plan.arn
}

output "pickem_terraform_apply_role_arn" {
  description = "Admin role the uncle-mikes-pickem Terraform workflow assumes for an apply on main"
  value       = aws_iam_role.pickem_terraform_apply.arn
}
