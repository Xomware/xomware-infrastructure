# xomware-infrastructure

> Main infrastructure repo — hosts all Xomware sites.

## What This Is
Terraform IaC for xomware.com and shared infra. S3, CloudFront, Route53, ACM.

## Stack
- Terraform, HCL, Python (Lambda), AWS

## Key Commands
```bash
cd terraform && terraform init
cd terraform && terraform plan
cd terraform && terraform apply
```

## Project Config
```yaml
pm_tool: github-projects
github_project_number: 2
github_project_owner: Xomware
base_branch: master
test_commands:
  - echo "no tests configured"
```

## Constraints

## Lessons
