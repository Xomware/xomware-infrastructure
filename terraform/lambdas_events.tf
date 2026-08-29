#**********************
# Public activity ingest — `events-track`
#
#   - POST /events/track       (authorization = NONE, anonymous visitors)
#   - POST /events/track-user  (Cognito, signed-in visitors)
#
# Both routes invoke the same function; see the handler for why identity is
# split across two routes rather than decoded in the lambda.
#
# Reuses the admin lambda IAM role: it already grants PutItem on
# xomware-events plus the KMS grants for the table's CMK, which is exactly
# and only what this needs. BatchWriteItem is added there for this function.
#**********************

data "archive_file" "events_track" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/events/events-track"
  output_path = "${path.module}/../lambda/events/events-track.zip"
}

resource "aws_lambda_function" "events_track" {
  function_name    = "${var.app_name}-events-track"
  description      = "Public: record pageview/outbound/error activity events"
  role             = aws_iam_role.admin_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 10
  memory_size      = 256
  filename         = data.archive_file.events_track.output_path
  source_code_hash = data.archive_file.events_track.output_base64sha256

  environment {
    variables = merge(local.admin_lambda_env, {
      ALLOW_ORIGINS = local.users_allow_origins
    })
  }

  tracing_config {
    mode = "PassThrough"
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-events-track"
    "environment" = "shared"
    "owner"       = "xomware"
    "lambda_type" = "events"
  })
}
