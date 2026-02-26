#**********************
# File Editor API
# S3 bucket for workspace config files
# Lambda functions for CRUD
# API Gateway for REST endpoints
#**********************

# --- S3 Bucket ---

resource "aws_s3_bucket" "workspace_config" {
  bucket = "${var.app_name}-workspace-config"
  tags   = local.standard_tags
}

resource "aws_s3_bucket_versioning" "workspace_config" {
  bucket = aws_s3_bucket.workspace_config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "workspace_config" {
  bucket = aws_s3_bucket.workspace_config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_alias.web_app.target_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "workspace_config" {
  bucket                  = aws_s3_bucket.workspace_config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "workspace_config" {
  bucket = aws_s3_bucket.workspace_config.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT"]
    allowed_origins = ["https://${local.domain_name}"]
    max_age_seconds = 3600
  }
}

# --- IAM Role for Lambda ---

resource "aws_iam_role" "file_editor_lambda" {
  name = "${var.app_name}-file-editor-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.standard_tags
}

resource "aws_iam_role_policy_attachment" "file_editor_lambda_basic" {
  role       = aws_iam_role.file_editor_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "file_editor_s3" {
  name = "${var.app_name}-file-editor-s3"
  role = aws_iam_role.file_editor_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.workspace_config.arn,
          "${aws_s3_bucket.workspace_config.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:HeadObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.terraform_state_bucket}",
          "arn:aws:s3:::${var.terraform_state_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_alias.web_app.target_key_arn]
      }
    ]
  })
}

# --- Lambda Functions ---

data "archive_file" "file_editor_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/file-editor"
  output_path = "${path.module}/../lambda/file-editor.zip"
}

resource "aws_lambda_function" "file_editor" {
  function_name    = "${var.app_name}-file-editor"
  role             = aws_iam_role.file_editor_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.file_editor_lambda.output_path
  source_code_hash = data.archive_file.file_editor_lambda.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME       = aws_s3_bucket.workspace_config.id
      STATE_BUCKET_NAME = var.terraform_state_bucket
      PASSPHRASE_HASH   = var.command_center_passphrase_hash
      ALLOWED_ORIGIN    = "https://${local.domain_name}"
    }
  }

  tags = local.standard_tags
}

# --- API Gateway ---

resource "aws_apigatewayv2_api" "file_editor" {
  name          = "${var.app_name}-file-editor"
  protocol_type = "HTTP"
  description   = "File Editor API for Command Center"

  cors_configuration {
    allow_origins = ["https://${local.domain_name}"]
    allow_methods = ["GET", "PUT", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Auth-Hash"]
    max_age       = 3600
  }

  tags = local.standard_tags
}

resource "aws_apigatewayv2_stage" "file_editor" {
  api_id      = aws_apigatewayv2_api.file_editor.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.file_editor_api.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.standard_tags
}

resource "aws_cloudwatch_log_group" "file_editor_api" {
  name              = "/aws/apigateway/${var.app_name}-file-editor"
  retention_in_days = 14
  tags              = local.standard_tags
}

resource "aws_apigatewayv2_integration" "file_editor" {
  api_id                 = aws_apigatewayv2_api.file_editor.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.file_editor.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_files" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "GET /config/files"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_apigatewayv2_route" "get_file" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "GET /config/files/{filename}"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_apigatewayv2_route" "put_file" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "PUT /config/files/{filename}"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_apigatewayv2_route" "agent_status" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "GET /status/agents"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

# --- Infrastructure Dashboard Routes ---

resource "aws_apigatewayv2_route" "infra_workspaces" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "GET /infra/workspaces"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_apigatewayv2_route" "infra_workspace_state" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "GET /infra/workspaces/{app}/state"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_apigatewayv2_route" "board_status" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "GET /status/board"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_apigatewayv2_route" "board_move" {
  api_id    = aws_apigatewayv2_api.file_editor.id
  route_key = "PUT /status/board/move"
  target    = "integrations/${aws_apigatewayv2_integration.file_editor.id}"
}

resource "aws_lambda_permission" "file_editor_apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_editor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.file_editor.execution_arn}/*/*"
}

# --- Custom Domain (api.xomware.com) ---

resource "aws_acm_certificate" "api" {
  domain_name       = "api.${local.domain_name}"
  validation_method = "DNS"
  tags              = local.standard_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

resource "aws_apigatewayv2_domain_name" "file_editor" {
  domain_name = "api.${local.domain_name}"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = local.standard_tags
}

resource "aws_apigatewayv2_api_mapping" "file_editor" {
  api_id      = aws_apigatewayv2_api.file_editor.id
  domain_name = aws_apigatewayv2_domain_name.file_editor.id
  stage       = aws_apigatewayv2_stage.file_editor.id
}

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = "api.${local.domain_name}"
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.file_editor.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.file_editor.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# --- Outputs ---

output "file_editor_api_url" {
  value       = "https://api.${local.domain_name}/config"
  description = "File Editor API base URL"
}

output "workspace_config_bucket" {
  value       = aws_s3_bucket.workspace_config.id
  description = "S3 bucket for workspace config files"
}
