#**********************
# WAF associations
#
# The regional WAF in waf.tf has existed for a while, but until now it was
# only *created* — its ARN was published to SSM for child repos and never
# attached to anything in this repo. api.xomware.com was therefore running
# with no rate limit at all, despite one being configured.
#
# This attaches it to the users API stage, which covers every route on that
# API: /users/*, /admin/* and the public /events/track added alongside this.
#
# The public ingest route is the reason this stopped being optional — an
# unauthenticated write endpoint in front of a PAY_PER_REQUEST table is a
# billing incident waiting to happen without a rate limit in front of it.
#**********************

resource "aws_wafv2_web_acl_association" "users_api" {
  resource_arn = module.users_api.stage_arn
  web_acl_arn  = module.waf_regional.web_acl_arn
}
