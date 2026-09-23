# auth.smirnoff-league.com: custom Cognito domain for the Smirnoff League.
# Google's consent screen names the redirect host until the app's branding is
# verified, and it can't verify amazoncognito.com. A pool allows one custom
# domain alongside its prefix domain, so this uses the shared pool's only slot;
# a future auth.xomware.com means moving Smirnoff to its own pool first.

data "aws_route53_zone" "smirnoff" {
  name = "smirnoff-league.com"
}

resource "aws_acm_certificate" "smirnoff_auth" {
  domain_name       = "auth.smirnoff-league.com"
  validation_method = "DNS"
  tags              = local.standard_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "smirnoff_auth_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.smirnoff_auth.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.smirnoff.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "smirnoff_auth" {
  certificate_arn         = aws_acm_certificate.smirnoff_auth.arn
  validation_record_fqdns = [for r in aws_route53_record.smirnoff_auth_cert_validation : r.fqdn]
}

resource "aws_cognito_user_pool_domain" "smirnoff_auth" {
  domain          = "auth.smirnoff-league.com"
  certificate_arn = aws_acm_certificate_validation.smirnoff_auth.certificate_arn
  user_pool_id    = aws_cognito_user_pool.xomware_users.id
}

resource "aws_route53_record" "smirnoff_auth" {
  zone_id = data.aws_route53_zone.smirnoff.zone_id
  name    = "auth.smirnoff-league.com"
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.smirnoff_auth.cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.smirnoff_auth.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}
