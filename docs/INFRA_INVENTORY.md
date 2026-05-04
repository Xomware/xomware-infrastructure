# Xomware Infrastructure Inventory + Cost Center

> **Snapshot date:** 2026-05-04. This is a manual reference doc. Phase 5 of the auth epic builds an `/admin/infra` portal tab on `xomware.com` that surfaces the same data live (driven by Cost Explorer + Resource Groups Tagging + per-service list APIs).

## 1. Executive summary

| Metric | Value |
|---|---|
| AWS account | 318658035812 (us-east-1) |
| Apps in production | 6 — xomify, xomper, xomcloud, xomfit, derby, **xomappetit** + xomware (org hub) |
| Total Lambdas | 160 |
| Total DynamoDB tables | 44 |
| Total S3 buckets | 10 |
| Total CloudFront distributions | 7 |
| Total Route 53 hosted zones | 4 |
| Total KMS customer keys | 8 (active) + 1 PendingDeletion |
| Total ACM certs | 16 |
| Total API Gateways | 6 REST v1 + 2 HTTP v2 |
| Total Cognito User Pools | 1 (shared `xomware-users`) |
| Total WAF ACLs | 2 (1 CloudFront + 1 Regional) |
| Total Secrets Manager secrets | 4 |

## 2. Cost trend

| Month | Spend | Notes |
|---|---|---|
| 2025-12 | $74.05 | Pre-consolidation |
| 2026-01 | $43.83 | After WAF consolidation work |
| 2026-02 | $77.06 | Peak (likely shared-WAF setup churn + duplicate KMS keys) |
| 2026-03 | $56.26 | |
| 2026-04 | $27.88 | Settled steady-state baseline |
| **2026-05** | **$4.67 MTD → $55.48 forecast** | Phase 3 provisioning bumped recent activity; AWS extrapolating |

**Steady-state run rate:** ~$28–35/mo. The $55 May forecast is AWS extrapolating from this week's Phase 3 provisioning activity (new CloudFront distribution `cdn.xomware.com`, new ACM certs, new resources getting their first usage). Real May actual will likely land closer to $35–40/mo.

## 3. Cost by service (April actuals)

| Service | Apr cost | Why | Optimizable? |
|---|---|---|---|
| **AWS WAF** | **$15.02** | 2 shared ACLs + managed rule groups (~$1–3/mo each) | Marginally — could review rule groups; shared ACLs are already minimal |
| **AWS KMS** | **$8.82** | 8 customer keys × $1/mo flat fee + minimal usage | **YES — biggest fixable cost** (see §6) |
| AWS Secrets Manager | $1.60 | 4 secrets × $0.40/mo | Yes — move to SSM Parameter Store (free) |
| Amazon Route 53 | $2.00 | 4 hosted zones × $0.50/mo + minimal queries | No — each zone owns a domain |
| Amazon API Gateway | <$0.10 | Per-million calls; hobby scale = pennies | No — already optimal |
| AWS Lambda | <$0.05 | Per-invocation + duration; well within free tier | No |
| Amazon DynamoDB | <$0.05 | PAY_PER_REQUEST + free tier | No |
| Amazon CloudFront | $0 | Within 1 TB/month free tier | No |
| Amazon S3 | <$0.05 | KB-scale storage + KMS request fees | No |

**Apr total: $27.88. ~85% of cost is WAF + KMS fixed monthly fees.**

## 4. Inventory by app

### xomify (Spotify stats)
- Frontend: `xomify.xomware.com` (CloudFront)
- API: `api.xomify.xomware.com` (REST v1)
- Lambdas: 64 (auth, friends, groups, invites, likes, notifications, ratings, release_radar, shares, user, wrapped, plus crons)
- DDB tables: 17 (xomify-{users, friendships, groups, group-members, group-tracks, invites, likes, ratings, shares, share-comments, share-reactions, share-listeners, share-interactions, top-items-cache, device-tokens, release-radar-history, wrapped-history})
- KMS: 1 customer key (`Web App S3 bucket`)
- Secrets: 1 (spotify-app-creds)
- Auth: Spotify OAuth (NOT Cognito)

### xomper (Fantasy football)
- Frontend: `xomper.xomware.com`
- API: `api.xomper.xomware.com`
- Lambdas: 42 (api-* + email-* + notif-*)
- DDB tables: 11 (xomper-{users, profiles, draft-history, league-champions, matchup-history, season-standings, taxi-steal-requests, rule-proposals, rule-votes, worldcup-snapshots, notification-log, device-tokens, whitelisted-users})
- KMS: 1 customer key
- Auth: Supabase (NOT Cognito)

### xomcloud (SoundCloud)
- Frontend: `xomcloud.xomware.com`
- API: `api.xomcloud.xomware.com`
- Lambdas: 2 (authorizer, download-tracks)
- DDB tables: 0 (relies on SoundCloud)
- KMS: 1 customer key
- Auth: SoundCloud OAuth

### derby (Sun God Derby)
- Frontend: `derby.xomware.com`
- API: `api.derby.xomware.com`
- Lambdas: 35 (admin-*, auth-*, comments-*, cron-*, leaderboard, picks, predictions, results, votes, track-visit)
- DDB tables: 8 (derby-{users, picks, predictions, race-results, comments, votes, poll-runs, visits})
- KMS: 1 customer key
- Auth: Custom JWT

### xomappetit (Meals — this epic)
- Frontend: `xomappétit.xomware.com` (canonical IDN) + `xomappetit.xomware.com` (ASCII redirect)
- API: `api.xomappetit.xomware.com` (REST v1)
- Lambdas: 11 (xomappetit-meals-{create, get, list, edit, update, delete, rate, ratings, comment-add, comments-list, comment-delete} + authorizer was deleted)
- DDB tables: 3 (xomappetit-{meals, meal-ratings, meal-comments})
- KMS: 2 customer keys (web app + DynamoDB) — **note: redundant, could share**
- Auth: shared Cognito (Phase 2)

### xomware (org hub + shared identity)
- Frontend: `xomware.com` (CloudFront)
- API: `api.xomware.com` (REST v1, NEW from Phase 3)
- API: `editor-api.xomware.com` (HTTP v2, file-editor for Command Center)
- Avatars CDN: `cdn.xomware.com`
- Lambdas: 6 (xomware-file-editor + xomware-users-{create, edit, get-by-handle, me, presign-avatar})
- DDB tables: 1 (xomware-users) + 2 terraform-state related
- KMS: 1 customer key (`Web App S3 bucket`)
- S3 buckets: xomware.com, xomware-avatars
- Cognito User Pool: `xomware-users` (shared identity for xomappetit + future apps)
- Shared WAF ACLs: 1 CloudFront + 1 Regional (consumed by ALL apps via SSM)

## 5. Cross-cutting resources

### KMS keys (9 total — 8 active + 1 PendingDeletion)
| Key ID (short) | Description | App | Status | Cost |
|---|---|---|---|---|
| 1a5419fc | KMS key for xomappetit | xomappetit | Enabled | $1/mo |
| c54e49a0 | KMS key for xomappetit DynamoDB | xomappetit | Enabled | $1/mo |
| a07450be | derby S3 bucket encryption | derby | Enabled | $1/mo |
| 20ed0744 | KMS CMK for Web App S3 bucket | xomify(?) | Enabled | $1/mo |
| 6fef9995 | KMS CMK for Web App S3 bucket | xomper(?) | Enabled | $1/mo |
| 71f8199f | KMS CMK for Web App S3 bucket | xomcloud(?) | Enabled | $1/mo |
| 734d6ea5 | KMS CMK for Web App S3 bucket | xomware-com | Enabled | $1/mo |
| 81b28037 | KMS CMK for Web App S3 bucket | (one of above) | Enabled | $1/mo |
| 2d59a601 | hornets-southeast-champs (decommissioned) | retired | PendingDeletion | $0 (will delete) |

**Naming collision:** 5 keys are named identically `KMS CMK for Web App S3 bucket`. Each app's Terraform created its own. Per-app isolation is fine, but it's also $5/mo of separate keys when one shared org-level key would suffice.

### ACM certs (16)
All free. Owned per-domain.

### CloudFront distributions (7)
| Domain | Purpose |
|---|---|
| xomware.com | Org landing |
| xomify.xomware.com | xomify frontend |
| xomper.xomware.com | xomper frontend |
| xomcloud.xomware.com | xomcloud frontend |
| derby.xomware.com | derby frontend |
| xomappetit.xomware.com | xomappetit frontend |
| **cdn.xomware.com** | NEW (Phase 3) — avatars CDN |

All within free tier on data transfer. Each distribution has fixed minimums (~$0/mo at hobby scale).

### Route 53 zones (4 × $0.50 = $2/mo)
- xomware.com (48 records)
- xomify.com (2 records)
- xomper.com (2 records)
- xomcloud.com (2 records)

`xomify.com`, `xomper.com`, `xomcloud.com` each have just 2 records — basically NS + SOA. **Could potentially delete these zones if you don't actually use those bare domains** (everything resolves under xomware.com subdomains anyway). Saves $1.50/mo.

### WAF ACLs (2 × $5/mo = $10/mo + rule fees)
- `xomware-cloudfront-waf-cloudfront` (CloudFront-scope, used for static frontend distributions)
- `xomware-regional-waf-regional` (Regional, used for API Gateway stages)

Both shared across all apps via SSM lookup pattern. **Already optimized** — can't easily cut without losing protection.

### Secrets Manager (4 secrets × $0.40/mo = $1.60/mo)
- secret_key
- access_key
- spotify-app-creds
- xom-claude/rds/password

### Cognito User Pool (1 — shared)
- `xomware-users` (Pool ID `us-east-1_IRLcrkzEE`)
- Free tier: 50,000 MAU. At <100 users, $0/mo.
- App Clients: `xomware-com-client`, `xomappetit-client`
- Group: `admin`
- PostConfirmation trigger: `xomware-users-create`

## 6. Optimization opportunities (ranked by savings)

| # | Opportunity | Saves | Effort | Risk |
|---|---|---|---|---|
| 1 | **Consolidate the 5 "Web App S3 bucket" KMS keys into 1 shared org-level key.** Each app's Terraform reuses the shared key via SSM lookup. | $4–5/mo | Medium — touches each app's `kms.tf`, requires KMS key policy carrying allowances for all apps | Low — the keys today are functionally equivalent; consolidation is a state migration |
| 2 | **Move 4 Secrets Manager secrets to SSM Parameter Store.** SSM SecureString is free for standard params. | $1.60/mo | Low — read existing secrets, write to SSM, swap consumers | Low — same encryption, same access patterns |
| 3 | **Delete the 3 unused vanity domains** (xomify.com, xomper.com, xomcloud.com — only 2 records each, you serve from xomware.com subdomains) | $1.50/mo | Low — `aws route53 delete-hosted-zone` (after confirming no DNS dependency) | Low — verify nothing points at these zones first |
| 4 | **Audit WAF managed rule groups.** Each ManagedRuleGroup is $1/mo + per-request fees. List the rules attached and turn off any not needed. | $0–6/mo | Low | Low — keep core protection (SQLi, XSS, IP rep) |
| 5 | **Drop xomappetit's separate DynamoDB KMS key** (`c54e49a0`). Use the same `1a5419fc` key for both web app and DDB. | $1/mo | Low | Low |

**Total potential savings: $7–13/mo (~25–40%).**

## 7. Phase 5 admin portal data model

The `/admin/infra` tab in xomware-frontend will surface this data live. Endpoints (will live at `api.xomware.com/admin/*`, gated to `cognito:groups` includes `admin`):

| Endpoint | Method | Returns | Source |
|---|---|---|---|
| `/admin/cost-summary` | POST | `{ mtd, lastMonth, forecast, currency, lastUpdated }` | Cost Explorer `GetCostAndUsage` + `GetCostForecast` |
| `/admin/cost-by-service` | POST `{ from, to }` | array of `{ service, amount }` | Cost Explorer with SERVICE dimension |
| `/admin/cost-trend` | POST `{ months }` | array of `{ month, amount }` | Cost Explorer monthly granularity |
| `/admin/inventory` | POST | grouped by app, all resources | per-service `List*` APIs + Resource Groups Tagging API |
| `/admin/optimization-callouts` | POST | computed list of savings opportunities | Lambda computes from inventory + cost data |

**IAM policies required for the admin lambdas (READ-ONLY):**
- `ce:GetCostAndUsage`, `ce:GetCostForecast`
- `tag:GetResources`
- `lambda:ListFunctions`
- `dynamodb:ListTables`, `dynamodb:DescribeTable`
- `s3:ListAllMyBuckets`
- `cloudfront:ListDistributions`
- `route53:ListHostedZones`, `route53:GetHostedZone`
- `kms:ListKeys`, `kms:DescribeKey`
- `acm:ListCertificates`
- `apigateway:GET /restapis`, `apigateway:GET /domainnames`
- `cognito-idp:ListUserPools`, `cognito-idp:DescribeUserPool`
- `wafv2:ListWebACLs`
- `secretsmanager:ListSecrets`

**Caching:** Cost Explorer is rate-limited and slow. Cache cost responses in DynamoDB (`xomware-cost-cache`) for 1h. Inventory list calls are cheaper — cache 15m.

**Tab UX:** Three tabs at the top of `/admin/infra`:
1. **Summary** — month-to-date, forecast, cost trend chart, top 5 services by spend
2. **Inventory** — collapsible sections per app, resource counts + drill-down
3. **Optimization** — ranked list of savings opportunities with one-click "I've reviewed this" dismissal

## 8. Tagging recommendation (do this in Phase 5)

Today, resources are inconsistently tagged. To enable proper "cost per app" breakdowns, ensure every Terraform-managed resource has these tags applied (via `local.standard_tags`):

- `app_name` (xomify, xomper, xomappetit, derby, xomware, etc.)
- `source` ("terraform")
- `environment` (prod, shared)
- `owner` ("xomware" or "dom")
- `purpose` (free-form short description)

After tags are applied, **activate cost allocation tags** in the AWS billing console (one-click). Within 24h, Cost Explorer can filter/group by these tags. This unlocks "cost per app" in the admin portal.

## 9. Audit/refresh cadence

This doc is a manual snapshot taken 2026-05-04. Once Phase 5's `/admin/infra` ships, **delete this section and link to it instead** — the live data replaces the snapshot. Keep this doc only for historical comparison + the optimization rationale (§6).
