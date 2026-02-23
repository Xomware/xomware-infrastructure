terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.75"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Auth via AWS CLI profile, env vars (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY),
  # or IAM role. No hardcoded credentials.
}
