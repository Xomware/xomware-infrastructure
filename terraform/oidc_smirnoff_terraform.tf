#**********************
# Terraform roles for smirnoff-league
#**********************
#
# Same bootstrap as oidc_reeses_terraform.tf, which carries the full reasoning:
# a new app stack cannot create the IAM roles its own pipeline assumes, so they
# live here. Plan is read-only from any ref; apply is admin from main only.

locals {
  # Both subject forms are required -- this org emits the numeric enterprise
  # subject, and the plain form alone fails AssumeRoleWithWebIdentity.
  smirnoff_terraform_subjects = [
    "repo:Xomware/smirnoff-league",
    "repo:Xomware@263047999/smirnoff-league@1382285884",
  ]
  smirnoff_default_branch = "main"
}

data "aws_iam_policy_document" "smirnoff_terraform_plan_trust" {
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
      values   = [for s in local.smirnoff_terraform_subjects : "${s}:*"]
    }
  }
}

data "aws_iam_policy_document" "smirnoff_terraform_apply_trust" {
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
      values   = [for s in local.smirnoff_terraform_subjects : "${s}:ref:refs/heads/${local.smirnoff_default_branch}"]
    }
  }
}

resource "aws_iam_role" "smirnoff_terraform_plan" {
  name               = "smirnoff-github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.smirnoff_terraform_plan_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "smirnoff-github-actions-terraform-plan" }))
}

resource "aws_iam_role" "smirnoff_terraform_apply" {
  name               = "smirnoff-github-actions-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.smirnoff_terraform_apply_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "smirnoff-github-actions-terraform-apply" }))
}

resource "aws_iam_role_policy_attachment" "smirnoff_terraform_plan" {
  role       = aws_iam_role.smirnoff_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "smirnoff_terraform_apply" {
  role       = aws_iam_role.smirnoff_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Reuses the reeses guardrail document: the deny list is identical, and a second
# copy would drift.
resource "aws_iam_role_policy" "smirnoff_terraform_apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.smirnoff_terraform_apply.id
  policy = data.aws_iam_policy_document.reeses_terraform_apply_guardrails.json
}

resource "aws_iam_role_policy" "smirnoff_terraform_plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.smirnoff_terraform_plan.id
  policy = data.aws_iam_policy_document.reeses_terraform_plan_state_lock.json
}

output "smirnoff_terraform_plan_role_arn" {
  description = "Read-only role the smirnoff-league Terraform workflow assumes for plans"
  value       = aws_iam_role.smirnoff_terraform_plan.arn
}

output "smirnoff_terraform_apply_role_arn" {
  description = "Admin role the smirnoff-league Terraform workflow assumes for an apply on main"
  value       = aws_iam_role.smirnoff_terraform_apply.arn
}
