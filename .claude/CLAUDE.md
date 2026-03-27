# xomware-infrastructure

> Core Terraform infrastructure for xomware.com platform hub.

## What This Is
Terraform configuration for the root Xomware platform infrastructure. Manages the Route53 zone for xomware.com (shared by all Xomware apps), S3 + CloudFront frontend hosting, WAF, TLS certs, and encryption keys.

## Stack
- Terraform >= 1.0
- AWS (Route53, S3, CloudFront, WAF, ACM, KMS)
- S3 backend for state (bucket: xomware-terraform-state)

## Key Commands
```bash
cd terraform && terraform init   # initialize
terraform plan                   # preview changes
terraform apply                  # apply changes
```

## Important Paths
```
terraform/          # all .tf files (10 total)
  main.tf           # provider + backend config
  route53.tf        # xomware.com DNS zone (SHARED)
  s3.tf             # S3 + CloudFront hosting
  waf.tf            # WAF rules
  kms.tf            # encryption keys
  acm.tf            # TLS certificates
```

## Project Config
```yaml
pm_tool: none
base_branch: master
test_commands:
  - cd terraform && terraform validate
build_commands:
  - cd terraform && terraform plan -no-color
```

## Constraints
- NO infrastructure changes without Dom's explicit approval
- Route53 zone is shared — changes here affect DNS for ALL Xomware apps
- State stored in S3 with DynamoDB locking (table: xomware-terraform-locks)
- CI/CD via GitHub Actions — plan on PR, apply on merge to master
- WAF module sourced from the shared `waf` repo

## Lessons
