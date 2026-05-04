#**********************
# Users service - Avatars S3 bucket
# Public access blocked, KMS encryption, versioning enabled.
# CORS PUT from xomware web frontends + localhost.
# Lifecycle: noncurrent versions deleted at 90d.
#**********************

resource "aws_s3_bucket" "avatars" {
  bucket = "${var.app_name}-avatars"

  force_destroy = false

  tags = merge(local.standard_tags, {
    "name"        = "${var.app_name}-avatars"
    "environment" = "shared"
    "owner"       = "xomware"
  })
}

resource "aws_s3_bucket_versioning" "avatars" {
  bucket = aws_s3_bucket.avatars.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "avatars" {
  bucket = aws_s3_bucket.avatars.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_alias.web_app.target_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "avatars" {
  bucket                  = aws_s3_bucket.avatars.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "avatars" {
  bucket = aws_s3_bucket.avatars.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = [
      "https://xomware.com",
      "https://xn--xomapptit-g4a.xomware.com",
      "https://xomappetit.xomware.com",
      "http://localhost:3000",
      "http://localhost:4200",
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "avatars" {
  bucket = aws_s3_bucket.avatars.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Bucket policy: allow CloudFront (avatars distribution) to read via OAC.
resource "aws_s3_bucket_policy" "avatars" {
  bucket = aws_s3_bucket.avatars.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.avatars.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.avatars.arn
          }
        }
      },
    ]
  })
}
