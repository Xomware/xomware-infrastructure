#**********************
# WAF (via reusable module)
#**********************

# CloudFront WAF
module "waf_cloudfront" {
  source = "git::https://github.com/Xomware/waf.git?ref=v2.0.0"

  app_name = "${var.app_name}-cloudfront"
  scope    = "CLOUDFRONT"
  tags     = local.standard_tags
}
