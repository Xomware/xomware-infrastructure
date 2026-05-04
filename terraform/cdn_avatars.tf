#**********************
# Users service - CloudFront CDN for avatars
# cdn.xomware.com -> xomware-avatars S3 bucket via OAC.
# 1y immutable cache. Geo: var.us_canada_only. Shared CloudFront WAF.
#**********************

# ACM cert for cdn.xomware.com (CloudFront cert MUST be in us-east-1).
# Provider default region is us-east-1, so this is fine without aliasing.
resource "aws_acm_certificate" "cdn" {
  domain_name       = "cdn.${local.domain_name}"
  validation_method = "DNS"
  tags              = local.standard_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cdn_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cdn.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "cdn" {
  certificate_arn         = aws_acm_certificate.cdn.arn
  validation_record_fqdns = [for record in aws_route53_record.cdn_cert_validation : record.fqdn]
}

# Origin Access Control — preferred over legacy OAI for KMS-encrypted buckets.
resource "aws_cloudfront_origin_access_control" "avatars" {
  name                              = "${var.app_name}-avatars-oac"
  description                       = "OAC for xomware-avatars bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "avatars" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "xomware-avatars CDN"
  default_root_object = ""
  price_class         = "PriceClass_100"
  http_version        = "http2"
  web_acl_id          = module.waf_cloudfront.web_acl_arn
  aliases             = ["cdn.${local.domain_name}"]

  origin {
    domain_name              = aws_s3_bucket.avatars.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.avatars.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.avatars.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.avatars.id}"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # 1y immutable cache. Avatar URLs include a UUID so cache busting is by URL.
    min_ttl     = 0
    default_ttl = 31536000
    max_ttl     = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cdn.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = var.us_canada_only ? "whitelist" : "none"
      locations        = var.us_canada_only ? ["US", "CA"] : []
    }
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-avatars-cdn"
    "environment" = "shared"
    "owner"       = "xomware"
  })
}

resource "aws_route53_record" "cdn" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = "cdn.${local.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.avatars.domain_name
    zone_id                = aws_cloudfront_distribution.avatars.hosted_zone_id
    evaluate_target_health = false
  }
}
