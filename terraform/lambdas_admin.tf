#**********************
# Admin / audit Lambdas
#
#   - auth-track          Cognito PostAuthentication trigger -> events
#   - admin-events-list   POST /admin/events/list (admin-group)
#   - admin-cost-summary  POST /admin/cost/summary (admin-group)
#
# All three share the admin IAM role:
#   * dynamodb read+write on xomware-events
#   * ce:GetCostAndUsage  (admin-cost-summary only — kept on shared role
#     because the read is harmless and a separate role doubles infra)
#**********************

locals {
  admin_lambdas = {
    events_list = {
      name        = "admin-events-list"
      description = "Admin: list audit events by day"
      source_dir  = "${path.module}/../lambda/admin/admin-events-list"
    }
    cost_summary = {
      name        = "admin-cost-summary"
      description = "Admin: month-to-date cost from Cost Explorer"
      source_dir  = "${path.module}/../lambda/admin/admin-cost-summary"
      timeout     = 30
    }
  }

  admin_lambda_env = {
    EVENTS_TABLE_NAME     = aws_dynamodb_table.events.id
    EVENTS_RETENTION_DAYS = tostring(var.events_retention_days)
  }
}

# --- IAM: shared role for all 3 admin/auth lambdas ---

data "aws_iam_policy_document" "admin_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "admin_lambda" {
  name               = "${var.app_name}-admin-lambdas"
  assume_role_policy = data.aws_iam_policy_document.admin_lambda_assume.json
  tags               = merge(local.standard_tags, { "name" = "${var.app_name}-admin-lambdas" })
}

resource "aws_iam_role_policy_attachment" "admin_lambda_basic" {
  role       = aws_iam_role.admin_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "admin_lambda" {
  # Events table — write (auth-track) + query GSIs (events-list).
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.events.arn,
      "${aws_dynamodb_table.events.arn}/index/*",
    ]
  }

  # Events table is KMS-encrypted under the web_app key.
  statement {
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_alias.web_app.target_key_arn]
  }

  # Cost Explorer — read-only.
  statement {
    effect    = "Allow"
    actions   = ["ce:GetCostAndUsage", "ce:GetCostForecast"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "admin_lambda" {
  name   = "${var.app_name}-admin-lambdas-policy"
  role   = aws_iam_role.admin_lambda.id
  policy = data.aws_iam_policy_document.admin_lambda.json
}

# --- auth-track (PostAuthentication trigger) ---

data "archive_file" "auth_track" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/auth/auth-track"
  output_path = "${path.module}/../lambda/auth/auth-track.zip"
}

resource "aws_lambda_function" "auth_track" {
  function_name    = "${var.app_name}-auth-track"
  description      = "Cognito PostAuthentication: write signin event"
  role             = aws_iam_role.admin_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.auth_track.output_path
  source_code_hash = data.archive_file.auth_track.output_base64sha256

  environment {
    variables = local.admin_lambda_env
  }

  tracing_config {
    mode = "PassThrough"
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-auth-track"
    "environment" = "shared"
    "owner"       = "xomware"
    "lambda_type" = "auth"
  })
}

# --- admin/* API lambdas ---

data "archive_file" "admin" {
  for_each    = local.admin_lambdas
  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/../lambda/admin/${each.value.name}.zip"
}

resource "aws_lambda_function" "admin" {
  for_each = local.admin_lambdas

  function_name    = "${var.app_name}-${each.value.name}"
  description      = each.value.description
  role             = aws_iam_role.admin_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = lookup(each.value, "timeout", 10)
  memory_size      = 256
  filename         = data.archive_file.admin[each.key].output_path
  source_code_hash = data.archive_file.admin[each.key].output_base64sha256

  environment {
    variables = local.admin_lambda_env
  }

  tracing_config {
    mode = "PassThrough"
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-${each.value.name}"
    "environment" = "shared"
    "owner"       = "xomware"
    "lambda_type" = "admin"
  })
}
