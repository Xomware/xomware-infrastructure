# Org Conventions — Xomware (Personal Projects)

## Secrets
- **Local dev:** `.env` files (gitignored)
- **Production:** environment variables via hosting platform (Vercel, Railway, Fly.io, etc.)
- Never commit `.env` files -- use `.env.example` with placeholder values

## Auth
<!-- Fill in your preferred auth: Clerk, Supabase Auth, Firebase Auth, NextAuth, etc. -->

## GitHub
- **Org:** `Xomware`
- **User:** `domgiordano`

## Cloud / Infra
- **Hosting:** project-dependent (Vercel, Railway, Fly.io, AWS, etc.)
- **IaC:** Terraform with remote state where applicable
- Keep infra simple -- managed services over self-hosted where possible

## CI/CD
- GitHub Actions for CI
- Deploy on merge to main (platform-specific)

## Common Mistakes
- Committing `.env` files
- Over-engineering infra for personal projects -- start simple, scale when needed
- Forgetting to update `.env.example` when adding new env vars
