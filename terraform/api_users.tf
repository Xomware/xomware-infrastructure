#**********************
# Users service - REST API v1 via api-gateway-service v2.5.0
# Hosted at api.xomware.com (formerly file-editor; migrated to editor-api).
# Authorization: COGNITO_USER_POOLS using shared Xomware pool.
#**********************

# ACM cert for api.xomware.com — replaces the file-editor cert that just got
# moved to editor-api.<domain>. file_editor_api.tf's aws_acm_certificate.api
# resource still has TF resource name "api" but now provisions a cert for
# editor-api.<domain>, so this REST API uses a separately named cert.

resource "aws_acm_certificate" "users_api" {
  domain_name       = "api.${local.domain_name}"
  validation_method = "DNS"
  tags              = local.standard_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "users_api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.users_api.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "users_api" {
  certificate_arn         = aws_acm_certificate.users_api.arn
  validation_record_fqdns = [for record in aws_route53_record.users_api_cert_validation : record.fqdn]
}

# --- API Gateway via shared module ---

locals {
  users_endpoints = [
    {
      name        = "me"
      path_part   = "me"
      http_method = "POST"
      invoke_arn  = aws_lambda_function.users["me"].invoke_arn
    },
    {
      name        = "get-by-handle"
      path_part   = "get-by-handle"
      http_method = "POST"
      invoke_arn  = aws_lambda_function.users["get_by_handle"].invoke_arn
    },
    {
      name        = "edit"
      path_part   = "edit"
      http_method = "POST"
      invoke_arn  = aws_lambda_function.users["edit"].invoke_arn
    },
    {
      name        = "presign-avatar"
      path_part   = "presign-avatar"
      http_method = "POST"
      invoke_arn  = aws_lambda_function.users["presign_avatar"].invoke_arn
    },
  ]

  users_allow_origins = join(",", [
    "https://xomware.com",
    "https://xn--xomapptit-g4a.xomware.com",
    "https://xomappetit.xomware.com",
    "http://localhost:3000",
    "http://localhost:4200",
  ])

  users_allow_headers = [
    "Authorization",
    "Content-Type",
    "X-Amz-Date",
    "X-Amz-Security-Token",
    "X-Api-Key",
    "Origin",
    "Accept",
  ]
}

module "users_api" {
  source = "git::https://github.com/domgiordano/api-gateway-service.git?ref=v2.5.0"

  app_name      = "${var.app_name}-users"
  stage_name    = "prod"
  authorization = "COGNITO_USER_POOLS"
  cognito_user_pool_arns = [
    aws_cognito_user_pool.xomware_users.arn,
  ]
  tags          = local.standard_tags
  allow_headers = local.users_allow_headers
  allow_origin  = local.users_allow_origins

  domain_name     = "api.${local.domain_name}"
  certificate_arn = aws_acm_certificate_validation.users_api.certificate_arn

  services = {
    users = {
      path_prefix = "users"
      endpoints   = local.users_endpoints
    }
  }
}

# Route53 alias for api.xomware.com -> users-service domain
resource "aws_route53_record" "users_api" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = "api.${local.domain_name}"
  type    = "A"

  alias {
    name                   = module.users_api.domain_regional_domain_name
    zone_id                = module.users_api.domain_regional_zone_id
    evaluate_target_health = true
  }
}
