#**********************
# Terraform roles for clt-dynasty (CLT Dynasty League)
#**********************
#
# Same bootstrap as oidc_reeses_terraform.tf, which carries the full reasoning:
# a new app stack cannot create the IAM roles its own pipeline assumes, so they
# live here. Plan is read-only from any ref; apply is admin from main only.

locals {
  # Both subject forms are required -- this org emits the numeric enterprise
  # subject, and the plain form alone fails AssumeRoleWithWebIdentity.
  clt_terraform_subjects = [
    "repo:Xomware/clt-dynasty",
    "repo:Xomware@263047999/clt-dynasty@1406404342",
  ]
  clt_default_branch = "main"
}

data "aws_iam_policy_document" "clt_terraform_plan_trust" {
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
      values   = [for s in local.clt_terraform_subjects : "${s}:*"]
    }
  }
}

data "aws_iam_policy_document" "clt_terraform_apply_trust" {
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
      values   = [for s in local.clt_terraform_subjects : "${s}:ref:refs/heads/${local.clt_default_branch}"]
    }
  }
}

# Both names were created by the archived clt-dynasty-league-infrastructure
# stack. Adopting them rewrites their trust to this repo's subjects; drop the
# imports once applied.
import {
  to = aws_iam_role.clt_terraform_plan
  id = "clt-dynasty-github-actions-terraform-plan"
}

import {
  to = aws_iam_role.clt_terraform_apply
  id = "clt-dynasty-github-actions-terraform-apply"
}

resource "aws_iam_role" "clt_terraform_plan" {
  name               = "clt-dynasty-github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.clt_terraform_plan_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "clt-dynasty-github-actions-terraform-plan" }))
}

resource "aws_iam_role" "clt_terraform_apply" {
  name               = "clt-dynasty-github-actions-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.clt_terraform_apply_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "clt-dynasty-github-actions-terraform-apply" }))
}

resource "aws_iam_role_policy_attachment" "clt_terraform_plan" {
  role       = aws_iam_role.clt_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "clt_terraform_apply" {
  role       = aws_iam_role.clt_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Reuses the reeses guardrail document: the deny list is identical, and a second
# copy would drift.
resource "aws_iam_role_policy" "clt_terraform_apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.clt_terraform_apply.id
  policy = data.aws_iam_policy_document.reeses_terraform_apply_guardrails.json
}

resource "aws_iam_role_policy" "clt_terraform_plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.clt_terraform_plan.id
  policy = data.aws_iam_policy_document.reeses_terraform_plan_state_lock.json
}

output "clt_terraform_plan_role_arn" {
  description = "Read-only role the clt-dynasty Terraform workflow assumes for plans"
  value       = aws_iam_role.clt_terraform_plan.arn
}

output "clt_terraform_apply_role_arn" {
  description = "Admin role the clt-dynasty Terraform workflow assumes for an apply on main"
  value       = aws_iam_role.clt_terraform_apply.arn
}
