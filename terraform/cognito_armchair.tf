# armchair-users: the Armchair app family's own pool, separate from xomware-users
# so it gets its own provider-type Google IdP slot and custom-domain slot. Same
# ownership model as the shared pool: clients live here, apps read SSM.

locals {
  armchair_tags = merge(local.standard_tags, {
    "environment" = "shared"
    "project"     = "armchair"
    "owner"       = "xomware"
  })
}

resource "aws_cognito_user_pool" "armchair_users" {
  name = "armchair-users"

  # Cognito has no undelete; losing the pool loses every account.
  deletion_protection = "ACTIVE"

  user_pool_tier    = "ESSENTIALS"
  mfa_configuration = "OFF"

  # Google-only sign-in: there are no native passwords to recover.
  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = local.armchair_tags

  lifecycle {
    ignore_changes = [tags_all]
  }
}

resource "aws_cognito_user_pool_domain" "armchair_auth" {
  domain       = "armchair-auth"
  user_pool_id = aws_cognito_user_pool.armchair_users.id
}


# Public-by-design values (they ship in the bundle), so String, as in cognito_ssm.tf.
resource "aws_ssm_parameter" "armchair_cognito_user_pool_arn" {
  name        = "/armchair/shared/cognito/user-pool-arn"
  description = "Armchair Cognito User Pool ARN"
  type        = "String"
  value       = aws_cognito_user_pool.armchair_users.arn
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_user_pool_id" {
  name        = "/armchair/shared/cognito/user-pool-id"
  description = "Armchair Cognito User Pool ID"
  type        = "String"
  value       = aws_cognito_user_pool.armchair_users.id
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_user_pool_jwks_url" {
  name        = "/armchair/shared/cognito/user-pool-jwks-url"
  description = "Armchair Cognito User Pool JWKS URL"
  type        = "String"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.armchair_users.id}/.well-known/jwks.json"
  tags        = local.armchair_tags
}

resource "aws_ssm_parameter" "armchair_cognito_hosted_ui_domain" {
  name        = "/armchair/shared/cognito/hosted-ui-domain"
  description = "Armchair Cognito Hosted UI domain (FQDN)"
  type        = "String"
  value       = aws_cognito_user_pool_domain.armchair_custom.domain
  tags        = local.armchair_tags
}
