# auth.armchairjudge.com: custom Cognito domain for armchair-users, so Google's
# consent screen names Armchair Judge rather than amazoncognito.com. Same shape
# as cognito_smirnoff_domain.tf. The armchair-auth prefix domain stays, so
# bundles built against it keep signing in.
#
# Cognito refuses a custom domain whose parent has no A record. The apex record
# belongs to the hub in domgiordano/armchair, so that has to be applied first.
# Google redirect URI for this host:
#   https://auth.armchairjudge.com/oauth2/idpresponse

data "aws_route53_zone" "armchairjudge" {
  name = "armchairjudge.com"
}

resource "aws_acm_certificate" "armchair_auth" {
  domain_name       = "auth.armchairjudge.com"
  validation_method = "DNS"
  tags              = local.armchair_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "armchair_auth_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.armchair_auth.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.armchairjudge.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "armchair_auth" {
  certificate_arn         = aws_acm_certificate.armchair_auth.arn
  validation_record_fqdns = [for r in aws_route53_record.armchair_auth_cert_validation : r.fqdn]
}

resource "aws_cognito_user_pool_domain" "armchair_custom" {
  domain          = "auth.armchairjudge.com"
  certificate_arn = aws_acm_certificate_validation.armchair_auth.certificate_arn
  user_pool_id    = aws_cognito_user_pool.armchair_users.id
}

resource "aws_route53_record" "armchair_auth" {
  zone_id = data.aws_route53_zone.armchairjudge.zone_id
  name    = "auth.armchairjudge.com"
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.armchair_custom.cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.armchair_custom.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}
