#**********************
# API Gateway account settings — the account-level singleton, owned here
#**********************
#
# `aws_api_gateway_account` is ONE setting per AWS account per region. Seven app
# repos were each declaring it and each pointing `cloudwatch_role_arn` at their
# own `<app>-api_gateway-logs` role, so every apply from any of them flipped the
# account's logging role to that app's — and the next repo to plan saw drift and
# flipped it back. Perpetual churn on every plan, in every repo, forever.
#
# xomtracks and today-in-sports already stopped declaring it and wrote down why,
# naming this repo as the long-term owner: it is the shared bootstrap that
# already owns the Cognito pool and the OIDC roles the other stacks depend on.
# This takes that ownership.
#
# A shared singleton needs a single owner. Everything else defers.
#
# Removing the resource from the other repos is safe: the provider's destroy of
# `aws_api_gateway_account` is a no-op, because there is no AWS API to reset
# account settings. The live pointer is left intact and simply drops out of
# their state. Their own `<app>-api_gateway-logs` roles stay for now — the live
# pointer may still name one until this applies, and deleting a role that is
# still pointed at would break account-wide API Gateway logging.

data "aws_iam_policy_document" "api_gateway_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_gateway_logs" {
  name               = "${var.app_name}-api_gateway-logs"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_logs_assume.json
  tags               = merge(local.standard_tags, tomap({ "name" = "${var.app_name}-api_gateway-logs" }))
}

resource "aws_iam_role_policy_attachment" "api_gateway_logs" {
  role       = aws_iam_role.api_gateway_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# One role for every API in the account. The managed policy grants CloudWatch
# Logs writes and nothing else, so a single role serves every app's gateway —
# which is the whole reason this can have one owner.
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_logs.arn
}
