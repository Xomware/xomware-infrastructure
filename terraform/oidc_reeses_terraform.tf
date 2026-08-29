#**********************
# Terraform roles for reeses-playoff-challenge
#**********************
#
# reeses now has its own Terraform stack (`infrastructure/terraform/`) and a
# pipeline to run it, but it could not create the roles that pipeline needs:
# its only credential is the narrowly scoped `reeses-github-actions-deploy`
# role above, which reaches one bucket, one distribution and a lambda prefix,
# and cannot create IAM.
#
# That chicken-and-egg is why reeses had no pipeline for months, and why six of
# its DynamoDB tables sat with deletion protection merged and never applied.
# See Xomware/reeses-playoff-challenge#6.
#
# The roles are created here because this repo can already apply, so the
# bootstrap costs no hand-run apply from anybody's laptop. Everything else in
# the reeses stack stays in the reeses repo; only the two roles that stack
# cannot create for itself live here.
#
# Same split as every other stack: plan is read-only and trusted from any ref
# so pull requests can plan; apply is admin and trusted only from a push to the
# default branch, so no pull request can assume the role that mutates.

locals {
  # Both forms, exactly as the deploy role above lists them. This repository
  # emits the numeric enterprise subject rather than the plain one, so a trust
  # policy carrying only `repo:Xomware/...` is refused with "Not authorized to
  # perform sts:AssumeRoleWithWebIdentity" — which reads like a missing secret
  # rather than a subject mismatch.
  reeses_terraform_subjects = [
    "repo:Xomware/reeses-playoff-challenge",
    "repo:Xomware@263047999/reeses-playoff-challenge@1324383231",
  ]
  reeses_default_branch = "main"
}

data "aws_iam_policy_document" "reeses_terraform_plan_trust" {
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
      values   = [for s in local.reeses_terraform_subjects : "${s}:*"]
    }
  }
}

data "aws_iam_policy_document" "reeses_terraform_apply_trust" {
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

    # Default branch only -- NOT `:*`. The difference between "a push to main
    # can change infrastructure" and "anything that can open a pull request
    # can change infrastructure".
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in local.reeses_terraform_subjects : "${s}:ref:refs/heads/${local.reeses_default_branch}"]
    }
  }
}

resource "aws_iam_role" "reeses_terraform_plan" {
  name               = "reeses-github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.reeses_terraform_plan_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "reeses-github-actions-terraform-plan" }))
}

resource "aws_iam_role" "reeses_terraform_apply" {
  name               = "reeses-github-actions-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.reeses_terraform_apply_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "reeses-github-actions-terraform-apply" }))
}

resource "aws_iam_role_policy_attachment" "reeses_terraform_plan" {
  role       = aws_iam_role.reeses_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "reeses_terraform_apply" {
  role       = aws_iam_role.reeses_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Nothing in any Xomware stack manages IAM users, so denying this costs nothing
# -- and it is precisely how a compromised workflow would turn an hour-long
# token into a permanent credential. Deny beats Allow, so it holds under
# AdministratorAccess.
data "aws_iam_policy_document" "reeses_terraform_apply_guardrails" {
  statement {
    sid    = "NoPersistentCredentials"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateSAMLProvider",
      "iam:UpdateSAMLProvider",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "reeses_terraform_apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.reeses_terraform_apply.id
  policy = data.aws_iam_policy_document.reeses_terraform_apply_guardrails.json
}

# ReadOnlyAccess cannot write DynamoDB, and a plan takes the state lock.
# Locking is not mutating infrastructure -- it is what stops two runs mutating
# it at once.
data "aws_iam_policy_document" "reeses_terraform_plan_state_lock" {
  statement {
    sid    = "StateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${local.web_app_account_id}:table/xomware-terraform-locks"]
  }
}

resource "aws_iam_role_policy" "reeses_terraform_plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.reeses_terraform_plan.id
  policy = data.aws_iam_policy_document.reeses_terraform_plan_state_lock.json
}

output "reeses_terraform_plan_role_arn" {
  description = "Read-only role the reeses Terraform workflow assumes for plans"
  value       = aws_iam_role.reeses_terraform_plan.arn
}

output "reeses_terraform_apply_role_arn" {
  description = "Admin role the reeses Terraform workflow assumes for an apply on main"
  value       = aws_iam_role.reeses_terraform_apply.arn
}
