terraform {
  backend "s3" {
    bucket         = "xomware-terraform-state"
    key            = "xomware/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "xomware-terraform-locks"
    encrypt        = true
  }
}

data "aws_caller_identity" "web_app_account" {
  provider = aws
}
# Updated Mon Mar  2 21:41:53 EST 2026

# CI verification test - 2026-03-06
