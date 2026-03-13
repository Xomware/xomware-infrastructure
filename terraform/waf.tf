#**********************
# Shared WAF (via reusable module)
# These WAFs are shared across all Xomware apps
# ARNs are exported via SSM for child repos to consume
#**********************

# Shared CloudFront WAF (protects all app CloudFront distributions)
module "waf_cloudfront" {
  source = "git::https://github.com/Xomware/waf.git?ref=v2.0.0"

  app_name = "xomware-shared-cloudfront"
  scope    = "CLOUDFRONT"
  tags     = local.standard_tags
}

# Shared Regional WAF (protects all app API Gateways)
module "waf_regional" {
  source = "git::https://github.com/Xomware/waf.git?ref=v2.0.0"

  app_name   = "xomware-shared-regional"
  scope      = "REGIONAL"
  rate_limit = 2000
  tags       = local.standard_tags
}

#**********************
# SSM Parameters (for child repos to consume)
#**********************

resource "aws_ssm_parameter" "shared_cloudfront_waf_arn" {
  name  = "/xomware/shared/cloudfront-waf-acl-arn"
  type  = "String"
  value = module.waf_cloudfront.web_acl_arn
  tags  = local.standard_tags
}

resource "aws_ssm_parameter" "shared_regional_waf_arn" {
  name  = "/xomware/shared/regional-waf-acl-arn"
  type  = "String"
  value = module.waf_regional.web_acl_arn
  tags  = local.standard_tags
}
