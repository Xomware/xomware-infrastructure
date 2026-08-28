#**********************
# GitHub Actions OIDC — apps with no infrastructure repo of their own
#**********************
#
# derby, reeses and clt-dynasty deploy into this account but have NO Terraform
# anywhere: their buckets, distributions and lambdas were created by hand.
# Their roles live here because this is the account's shared-infrastructure
# repo and the alternative is IAM created by hand as well.
#
# Consequence: the resources below are referenced by ARN rather than by
# resource, because Terraform does not manage them. The CloudFront ids are
# hardcoded for the same reason and were resolved with
#   aws cloudfront list-distributions --query "...Aliases..."
# If one of these apps ever gets a real infrastructure repo, its role should
# move there and reference its own resources.

locals {
  unmanaged_app_roles = {
    derby = {
      subjects      = ["repo:Xomware/derby"]
      bucket        = "derby.xomware.com"
      distribution  = "E1SVWFQOE6RU2X"
      lambda_prefix = "derby-"
      kms_alias     = "alias/derby-web-app"
      ssm_prefix    = null
    }
    reeses = {
      subjects = [
        "repo:Xomware/reeses-playoff-challenge",
        "repo:Xomware@263047999/reeses-playoff-challenge@1324383231",
      ]
      bucket        = "playoffs.xomware.com"
      distribution  = "EAXGENZJR8L3Q"
      lambda_prefix = "reeses-"
      kms_alias     = "alias/kms-for-reeses"
      # The SHARED Cognito prefix, not this app's own: the user pool is shared
      # across Xomware and the build reads the hosted-UI domain from it. Scoping
      # to /reeses/* produced a bundle with no domain, and the repo's own
      # "Google sign-in is wired" check caught it.
      ssm_prefix = "xomware/shared"
    }
    clt_dynasty = {
      subjects = [
        "repo:Xomware/clt-dynasty-league",
        "repo:Xomware@263047999/clt-dynasty-league-frontend@1345457954",
      ]
      bucket        = "clt.dynasty.xomware.com"
      distribution  = "E2C3YYJUEV78O7"
      lambda_prefix = null
      ssm_prefix    = "clt-dynasty"
      # clt.dynasty.xomware.com is SSE-S3, not KMS, so there is no key to grant.
      kms_alias = null
    }
  }
}

data "aws_iam_policy_document" "unmanaged_app_trust" {
  for_each = local.unmanaged_app_roles

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
      values   = [for subject in each.value.subjects : "${subject}:*"]
    }
  }
}

resource "aws_iam_role" "unmanaged_app" {
  for_each = local.unmanaged_app_roles

  name               = "${each.key}-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.unmanaged_app_trust[each.key].json

  tags = merge(local.standard_tags, tomap({ "name" = "${each.key}-github-actions-deploy" }))
}

data "aws_kms_alias" "unmanaged_app" {
  for_each = { for name, cfg in local.unmanaged_app_roles : name => cfg if cfg.kms_alias != null }
  name     = each.value.kms_alias
}

data "aws_iam_policy_document" "unmanaged_app" {
  for_each = local.unmanaged_app_roles

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
      "arn:aws:s3:::${each.value.bucket}",
      "arn:aws:s3:::${each.value.bucket}/*",
    ]
  }

  # ListDistributions has no resource form -- account-wide or nothing. The
  # invalidation itself is scoped to the one distribution.
  statement {
    sid       = "FindDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:ListDistributions"]
    resources = ["*"]
  }

  statement {
    sid    = "InvalidateCache"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
    ]
    resources = ["arn:aws:cloudfront::${data.aws_caller_identity.web_app_account.account_id}:distribution/${each.value.distribution}"]
  }

  dynamic "statement" {
    for_each = each.value.ssm_prefix == null ? [] : [each.value.ssm_prefix]
    content {
      sid       = "ReadBuildConfig"
      effect    = "Allow"
      actions   = ["ssm:GetParameter", "ssm:GetParameters"]
      resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:parameter/${statement.value}/*"]
    }
  }

  # These apps' backends ship lambda zips and publish their own shared layer.
  dynamic "statement" {
    for_each = each.value.lambda_prefix == null ? [] : [each.value.lambda_prefix]
    content {
      sid    = "DeployFunctions"
      effect = "Allow"
      actions = [
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:PublishLayerVersion",
        "lambda:ListLayerVersions",
        "lambda:GetLayerVersion",
      ]
      resources = [
        "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:function:${statement.value}*",
        "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.web_app_account.account_id}:layer:${statement.value}*",
      ]
    }
  }

  # A KMS-encrypted bucket needs the key as well as the bucket: s3:PutObject
  # alone fails with AccessDenied on kms:GenerateDataKey. Each of these apps has
  # its own key, resolved from its alias so a key rotation does not need an edit
  # here. clt-dynasty's bucket is SSE-S3 and has no key at all.
  dynamic "statement" {
    for_each = each.value.kms_alias == null ? [] : [each.key]
    content {
      sid    = "UseSiteKey"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
      ]
      resources = [data.aws_kms_alias.unmanaged_app[statement.value].target_key_arn]
    }
  }

  # list-functions and list-layers are unscopable; the deploys enumerate before
  # updating.
  dynamic "statement" {
    for_each = each.value.lambda_prefix == null ? [] : [1]
    content {
      sid       = "EnumerateLambdas"
      effect    = "Allow"
      actions   = ["lambda:ListFunctions", "lambda:ListLayers"]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "unmanaged_app" {
  for_each = local.unmanaged_app_roles

  name   = "deploy"
  role   = aws_iam_role.unmanaged_app[each.key].id
  policy = data.aws_iam_policy_document.unmanaged_app[each.key].json
}

output "unmanaged_app_role_arns" {
  description = "Deploy roles for the apps with no infrastructure repo of their own"
  value       = { for k, r in aws_iam_role.unmanaged_app : k => r.arn }
}
