#**********************
# GitHub Actions OIDC
# Keyless auth for the site deploy workflow
#**********************

# Account-wide, created by whichever stack migrated first.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_trust" {
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

    # Any ref in the repo -- the deploy also runs via workflow_dispatch from
    # other refs, which a ref-pinned subject would break.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for subject in var.github_frontend_subjects : "${subject}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_frontend" {
  name               = "${var.app_name}-github-actions-frontend"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-github-actions-frontend" }))
}

data "aws_iam_policy_document" "github_actions_frontend" {
  statement {
    sid    = "PublishSite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      module.web.s3_bucket_arn,
      "${module.web.s3_bucket_arn}/*",
    ]
  }

  # The deploy resolves its distribution by alias at runtime and
  # ListDistributions has no resource form -- account-wide or nothing.
  # Read-only; the invalidation itself is scoped below.
  statement {
    sid       = "FindDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:ListDistributions"]
    resources = ["*"]
  }

  # Get as well as Create: this deploy waits for the invalidation to finish
  # rather than firing and forgetting, so it polls.
  statement {
    sid    = "InvalidateCache"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
    ]
    resources = [module.web.cloudfront_distribution_arn]
  }

  statement {
    sid       = "ReadSharedConfig"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:parameter/xomware/shared/*"]
  }

  # Decrypt for the SecureString parameters; GenerateDataKey and Encrypt because
  # the site bucket is KMS-encrypted and s3:PutObject alone fails there.
  statement {
    sid    = "UseWebAppKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_alias.web_app.target_key_arn]
  }
}

resource "aws_iam_role_policy" "github_actions_frontend" {
  name   = "deploy"
  role   = aws_iam_role.github_actions_frontend.id
  policy = data.aws_iam_policy_document.github_actions_frontend.json
}

output "github_actions_frontend_role_arn" {
  description = "Role the xomware-frontend deploy workflow assumes via OIDC"
  value       = aws_iam_role.github_actions_frontend.arn
}
