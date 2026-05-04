#**********************
# Users service - Lambda functions
# 5 Node.js 20.x handlers + bundled IAM role.
# Source: ../lambda/users/<function-name>/index.js
# Bundled via archive_file (no CI build step).
#**********************

locals {
  users_lambdas = {
    create = {
      name        = "users-create"
      description = "Cognito PostConfirmation: write user row"
      source_dir  = "${path.module}/../lambda/users/users-create"
      timeout     = 10
      memory      = 256
    }
    me = {
      name        = "users-me"
      description = "GET /users/me - return authed user row"
      source_dir  = "${path.module}/../lambda/users/users-me"
      timeout     = 10
      memory      = 256
    }
    get_by_handle = {
      name        = "users-get-by-handle"
      description = "POST /users/get-by-handle - GSI lookup"
      source_dir  = "${path.module}/../lambda/users/users-get-by-handle"
      timeout     = 10
      memory      = 256
    }
    edit = {
      name        = "users-edit"
      description = "POST /users/edit - update displayName/avatarUrl/visibility"
      source_dir  = "${path.module}/../lambda/users/users-edit"
      timeout     = 10
      memory      = 256
    }
    presign_avatar = {
      name        = "users-presign-avatar"
      description = "POST /users/presign-avatar - issue PUT presigned URL"
      source_dir  = "${path.module}/../lambda/users/users-presign-avatar"
      timeout     = 10
      memory      = 256
    }
  }

  users_lambda_env = {
    USERS_TABLE_NAME       = aws_dynamodb_table.users.id
    AVATARS_BUCKET_NAME    = aws_s3_bucket.avatars.id
    AVATARS_CDN_URL        = "https://cdn.${local.domain_name}"
    AVATARS_KMS_KEY_ARN    = aws_kms_alias.web_app.target_key_arn
    EVENTS_TABLE_NAME      = aws_dynamodb_table.events.id
    EVENTS_RETENTION_DAYS  = tostring(var.events_retention_days)
  }
}

# --- IAM role ---

data "aws_iam_policy_document" "users_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "users_lambda" {
  name               = "${var.app_name}-users-lambdas"
  assume_role_policy = data.aws_iam_policy_document.users_lambda_assume.json
  tags               = merge(local.standard_tags, { "name" = "${var.app_name}-users-lambdas" })
}

resource "aws_iam_role_policy_attachment" "users_lambda_basic" {
  role       = aws_iam_role.users_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "users_lambda" {
  # DynamoDB on users table + GSI
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.users.arn,
      "${aws_dynamodb_table.users.arn}/index/*",
    ]
  }

  # users-create writes signup events on PostConfirmation.
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.events.arn]
  }

  # S3 - presigned PUT signing requires the signer's role to have PutObject
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = ["${aws_s3_bucket.avatars.arn}/avatars/*"]
  }

  # KMS - encrypt/decrypt for avatars bucket + DynamoDB encryption
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_alias.web_app.target_key_arn]
  }
}

resource "aws_iam_role_policy" "users_lambda" {
  name   = "${var.app_name}-users-lambdas-policy"
  role   = aws_iam_role.users_lambda.id
  policy = data.aws_iam_policy_document.users_lambda.json
}

# --- Lambda packaging ---

data "archive_file" "users" {
  for_each    = local.users_lambdas
  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/../lambda/users/${each.value.name}.zip"
}

resource "aws_lambda_function" "users" {
  for_each = local.users_lambdas

  function_name    = "${var.app_name}-${each.value.name}"
  description      = each.value.description
  role             = aws_iam_role.users_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = each.value.timeout
  memory_size      = each.value.memory
  filename         = data.archive_file.users[each.key].output_path
  source_code_hash = data.archive_file.users[each.key].output_base64sha256

  environment {
    variables = local.users_lambda_env
  }

  tracing_config {
    mode = "PassThrough"
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-${each.value.name}"
    "environment" = "shared"
    "owner"       = "xomware"
    "lambda_type" = "users"
  })
}

# Convenience aliases for resources referenced elsewhere
resource "aws_lambda_function_event_invoke_config" "users_create" {
  function_name                = aws_lambda_function.users["create"].function_name
  maximum_event_age_in_seconds = 60
  maximum_retry_attempts       = 0
}
