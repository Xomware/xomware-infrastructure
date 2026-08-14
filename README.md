# Xomware Infrastructure

Core infrastructure for the Xomware platform hub at `xomware.com`.

## Xomware Ecosystem

| App | URL | Frontend | Backend | Infrastructure |
|-----|-----|----------|---------|----------------|
| **Xomware** (Hub) | [xomware.com](https://xomware.com) | [xomware-frontend](https://github.com/domgiordano/xomware-frontend) | - | [xomware-infrastructure](https://github.com/domgiordano/xomware-infrastructure) |
| **Xomify** | [xomify.xomware.com](https://xomify.xomware.com) | [xomify-frontend](https://github.com/domgiordano/xomify-frontend) | [xomify-backend](https://github.com/domgiordano/xomify-backend) | [xomify-infrastructure](https://github.com/domgiordano/xomify-infrastructure) |
| **Xomcloud** | [xomcloud.xomware.com](https://xomcloud.xomware.com) | [xomcloud-frontend](https://github.com/domgiordano/xomcloud-frontend) | [xomcloud-backend](https://github.com/domgiordano/xomcloud-backend) | [xomcloud-infrastructure](https://github.com/domgiordano/xomcloud-infrastructure) |
| **Xomper** | [xomper.xomware.com](https://xomper.xomware.com) | [xomper-front-end](https://github.com/domgiordano/xomper-front-end) | [xomper-back-end](https://github.com/domgiordano/xomper-back-end) | [xomper-infrastructure](https://github.com/domgiordano/xomper-infrastructure) |

## Architecture

This workspace manages the central landing page and shared DNS zone that all Xomware apps use as subdomains:

| Subdomain | App | Description |
|-----------|-----|-------------|
| `xomware.com` | Hub | Landing page linking to all apps |
| `xomify.xomware.com` | Xomify | Music tracking & social platform |
| `xomcloud.xomware.com` | Xomcloud | SoundCloud music library |
| `xomper.xomware.com` | Xomper | Fantasy football companion |

## Resources

- **Route53** - Hosted zone for `xomware.com` (subdomains managed by individual app workspaces)
- **S3 + CloudFront** - Static site hosting via [web-hosting](https://github.com/domgiordano/web-hosting) module
- **ACM** - SSL certificate for `xomware.com`
- **KMS** - Encryption key for S3 bucket
- **WAF** - CloudFront Web ACL via [waf](https://github.com/domgiordano/waf) module

## Modules Used

| Module | Version | Purpose |
|--------|---------|---------|
| [web-hosting](https://github.com/domgiordano/web-hosting) | v1.1.0 | S3 + CloudFront + ACM + Route53 |
| [waf](https://github.com/domgiordano/waf) | v1.1.0 | CloudFront WAF with managed rules |

## Lambda tests

Lambda source lives in `lambda/`. There is no package.json and no test
framework — the few tests here use Node's built-in runner and need neither:

```bash
node --test lambda/events/events-track/validate.test.js
```

Pass the file, not the directory: `node --test <dir>` also tries to load
`index.js`, which requires the AWS SDK that only exists in the Lambda runtime.
Testable logic is kept in modules with no SDK import (e.g. `validate.js`) so it
can run outside AWS.

## Terraform Cloud

- **Organization:** Domjgiordano
- **Workspace:** xomware-infrastructure

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `access_key` | Sensitive | AWS access key |
| `secret_key` | Sensitive | AWS secret key |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `xomware` | Application name |
| `us_canada_only` | `true` | Geo-restrict to US/CA |
| `enable_cloudfront_cache` | `true` | Enable CloudFront caching |
| `retain_on_delete` | `false` | Disable instead of delete CloudFront on destroy |

## Outputs

The Route53 zone ID (`Z0212401124Q11NWHM1D1`) is referenced by each app workspace to create subdomain records.
# Force Actions trigger Mon Mar  2 21:41:36 EST 2026
