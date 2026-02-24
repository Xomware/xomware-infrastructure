variable "app_name" {
  description = "The name for the application."
  type        = string
  default     = "xomware"
}

variable "domain_suffix" {
  description = "Suffix for the domain of the app."
  type        = string
  default     = ".com"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# CloudFront Variables
variable "cloudfront_origin_path" {
  description = "Optional element for cloudfront distribution that causes CloudFront to request your content from a directory in your Amazon S3 bucket."
  type        = string
  default     = ""
}

variable "us_canada_only" {
  description = "If a georestriction should be placed on the distribution to only provide access to the US and Canada"
  type        = bool
  default     = true
}

variable "custom_error_response_page_path" {
  description = "Custom error response page path for SPA routing."
  type        = string
  default     = "/index.html"
}

variable "retain_on_delete" {
  description = "Disables the distribution instead of deleting it when destroying the resource through Terraform."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for CloudFront"
  type        = string
  default     = "TLSv1.2_2018"
}

variable "enable_cloudfront_cache" {
  description = "This variable controls the cloudfront cache. Setting this to false will set the default_ttl and max_ttl values to zero"
  type        = bool
  default     = true
}

# File Editor API
variable "command_center_passphrase_hash" {
  description = "SHA-256 hash of the Command Center passphrase for API auth"
  type        = string
  sensitive   = true
}
