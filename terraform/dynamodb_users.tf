#**********************
# Users service - DynamoDB
# Single table: xomware-users
# PK: userId (Cognito sub)
# GSI: handle-index (preferredUsername -> userId)
#**********************

resource "aws_dynamodb_table" "users" {
  name         = "${var.app_name}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_alias.web_app.target_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  # PITR restores a table; it does not survive one being deleted. This is the
  # guardrail for the delete itself — profile data has no other source.
  deletion_protection_enabled = true

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "preferredUsername"
    type = "S"
  }

  global_secondary_index {
    name            = "handle-index"
    hash_key        = "preferredUsername"
    projection_type = "ALL"
  }

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-users"
    "environment" = "shared"
    "owner"       = "xomware"
  })
}
