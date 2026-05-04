#**********************
# SSM exports - users service + avatars + file-editor migration
# Consumed by xomware-frontend (Command Center, profile page).
#**********************

resource "aws_ssm_parameter" "users_api_url" {
  name        = "/xomware/shared/users-api/url"
  description = "Shared Xomware users service base URL"
  type        = "String"
  value       = "https://api.${local.domain_name}"

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "avatars_bucket_name" {
  name        = "/xomware/shared/avatars/bucket-name"
  description = "S3 bucket name for shared user avatars"
  type        = "String"
  value       = aws_s3_bucket.avatars.id

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "avatars_cdn_url" {
  name        = "/xomware/shared/avatars/cdn-url"
  description = "CloudFront CDN base URL for shared user avatars"
  type        = "String"
  value       = "https://cdn.${local.domain_name}"

  lifecycle { ignore_changes = [tags, tags_all] }
}

resource "aws_ssm_parameter" "file_editor_api_url" {
  name        = "/xomware/shared/file-editor-api/url"
  description = "File Editor API base URL (Command Center backend)"
  type        = "String"
  value       = "https://editor-api.${local.domain_name}"

  lifecycle { ignore_changes = [tags, tags_all] }
}
