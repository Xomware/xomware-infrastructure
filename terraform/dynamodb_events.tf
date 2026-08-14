#**********************
# Events / audit log — `xomware-events`
#
# Append-only audit table written by Cognito triggers (signup, signin) and
# read by the /admin portal. TTL = 90 days to keep storage near-free at
# hobby scale; tighten/loosen via `events_retention_days`.
#
# Access patterns:
#   - by day:   `eventDate` (YYYY-MM-DD) sorted by `eventTime#eventId`
#   - by user:  `userId`                  sorted by `eventTime#eventId`
#   - by type:  `eventType`               sorted by `eventTime#eventId`
#
# All sort keys are `eventTime#eventId` so DynamoDB sorts lexicographically
# by ISO-8601 timestamp, then de-duplicates within the same instant via the
# trailing eventId.
#**********************

resource "aws_dynamodb_table" "events" {
  name         = "${var.app_name}-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "eventId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.web_app.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  # As with the users table: PITR does not protect against the table itself
  # being deleted. Audit rows are the only record of who came and when.
  deletion_protection_enabled = true

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  attribute {
    name = "eventId"
    type = "S"
  }

  attribute {
    name = "eventDate"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "eventType"
    type = "S"
  }

  attribute {
    name = "eventTimeId"
    type = "S"
  }

  global_secondary_index {
    name            = "by-day"
    hash_key        = "eventDate"
    range_key       = "eventTimeId"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "by-user"
    hash_key        = "userId"
    range_key       = "eventTimeId"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "by-type"
    hash_key        = "eventType"
    range_key       = "eventTimeId"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-events"
    "environment" = "shared"
    "owner"       = "xomware"
    "purpose"     = "audit"
  })
}

# Retention window for audit rows (TTL). 90 days is plenty for hobby scale
# usage analytics; raise to capture longer trends.
variable "events_retention_days" {
  type    = number
  default = 90
}
