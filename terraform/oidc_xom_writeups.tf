#**********************
# GitHub Actions OIDC — xom-writeups
#**********************
#
# The weekly write-ups are drafted by Claude routines, which have no AWS access.
# domgiordano/xom-writeups runs the Actions on either side: export inputs before
# a routine, load its outputs after. Loads run on pushes to the routine's
# claude/** branches, so the trust allows any ref.
#
# The tables and the Lambda belong to stacks with their own repos (xomper,
# armchair), so they are referenced by name, not by resource.

locals {
  # Both subject forms are required: see oidc_smirnoff_terraform.tf.
  xom_writeups_subjects = [
    "repo:domgiordano/xom-writeups",
    "repo:domgiordano@44783934/xom-writeups@1407265746",
  ]
  xom_writeups_table_arn = "arn:aws:dynamodb:${var.aws_region}:${local.web_app_account_id}:table"
}

# Both xomper tables are encrypted with this CMK, so reads and writes through
# DynamoDB need it too.
data "aws_kms_alias" "xomper_dynamodb" {
  name = "alias/xomper-dynamodb"
}

data "aws_iam_policy_document" "xom_writeups_trust" {
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
      values   = [for s in local.xom_writeups_subjects : "${s}:*"]
    }
  }
}

data "aws_iam_policy_document" "xom_writeups" {
  statement {
    sid       = "InvokeWriteupsLambda"
    actions   = ["lambda:InvokeFunction"]
    resources = ["arn:aws:lambda:${var.aws_region}:${local.web_app_account_id}:function:armchair-cron-writeups"]
  }

  statement {
    sid     = "XomperReports"
    actions = ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:GetItem"]
    resources = [
      "${local.xom_writeups_table_arn}/xomper-ai-reports",
      "${local.xom_writeups_table_arn}/xomper-ai-reports/index/*",
    ]
  }

  statement {
    sid       = "XomperWhitelistScan"
    actions   = ["dynamodb:Scan"]
    resources = ["${local.xom_writeups_table_arn}/xomper-whitelisted-users"]
  }

  statement {
    sid       = "XomperTableKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [data.aws_kms_alias.xomper_dynamodb.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${var.aws_region}.amazonaws.com"]
    }
  }

  # The prepare mode parks payloads too large for an invoke response here.
  statement {
    sid       = "ReadPreparedRecaps"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::armchair-avatars-${local.web_app_account_id}/recaps/prepare/*"]
  }
}

resource "aws_iam_role" "xom_writeups" {
  name               = "xom-writeups-github-actions"
  assume_role_policy = data.aws_iam_policy_document.xom_writeups_trust.json
  tags               = merge(local.standard_tags, tomap({ "name" = "xom-writeups-github-actions" }))
}

resource "aws_iam_role_policy" "xom_writeups" {
  name   = "writeups-io"
  role   = aws_iam_role.xom_writeups.id
  policy = data.aws_iam_policy_document.xom_writeups.json
}

output "xom_writeups_role_arn" {
  description = "Role the xom-writeups export and load workflows assume"
  value       = aws_iam_role.xom_writeups.arn
}
