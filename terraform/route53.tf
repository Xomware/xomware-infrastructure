# Hosted Zone Data Source
data "aws_route53_zone" "web_zone" {
  private_zone = false
  zone_id      = "Z0212401124Q11NWHM1D1"
}

# Domain-ownership TXT records for third-party verifiers (Google Search
# Console, etc.). One TXT RRset can hold multiple values, so we aggregate
# them here as a single resource — append a new string when the next
# verifier shows up.
resource "aws_route53_record" "domain_verification_txt" {
  zone_id = data.aws_route53_zone.web_zone.zone_id
  name    = local.domain_name
  type    = "TXT"
  ttl     = 300

  records = [
    # Google Search Console — verifies xomware.com ownership for OAuth
    # consent screen + future Google services. Issued 2026-05-04.
    "google-site-verification=ZuymDC9YIgz5-8Fzc4WdE5PJeSB-jWL4qHcYdSBcNbE",
  ]
}
