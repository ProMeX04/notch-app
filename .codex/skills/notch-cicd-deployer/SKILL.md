---
name: notch-cicd-deployer
description: Manage, configure, debug, and verify CI/CD pipelines, GitHub Actions workflows, and deployments (Google Cloud Run, Vercel) for Notch.
---

# Notch CI/CD and Deployer

Use this skill when adding, modifying, debugging, or reviewing GitHub Actions workflows under `.github/workflows/`, deploy scripts, or deployment configurations for the Notch Portal backend and frontend.

## Core Pipelines & Infrastructure

### 1. Google Cloud Run (Backend)
- **Workflow File**: `.github/workflows/deploy-portal-backend.yml`
- **Runner**: Must use `runs-on: self-hosted`.
- **Authentication**: Authenticate using Workload Identity Federation:
  - Workload Identity Pool Provider: `projects/657193756037/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
  - Service Account: `657193756037-compute@developer.gserviceaccount.com`
  - Project ID: `tryapi-489314`
- **Region**: Deploy to `asia-southeast1`.
- **Command**:
  ```bash
  gcloud run deploy notch-portal-api --source portal/api --region asia-southeast1 --project tryapi-489314 --quiet
  ```

### 2. Vercel (Frontend)
- **Workflow File**: `.github/workflows/deploy-portal-frontend.yml`
- **Runner**: Must use `runs-on: self-hosted`.
- **Secrets required**: `VERCEL_ORG_ID`, `VERCEL_TOKEN`, `VERCEL_PORTAL_WEB_PROJECT_ID` (or fallback `VERCEL_PROJECT_ID`).
- **Build Step Environment Variables**: Ensure the build step includes the correct production Supabase configurations:
  - `VITE_SUPABASE_URL` (currently Singapore DB endpoint)
  - `VITE_SUPABASE_ANON_KEY` (Supabase publishable key)
- **Flow**:
  1. `vercel pull --yes --environment=production --token=${{ secrets.VERCEL_TOKEN }}`
  2. `cp .vercel/.env.production.local .env.production.local`
  3. `vercel build --prod --token=${{ secrets.VERCEL_TOKEN }}`
  4. `vercel deploy --prebuilt --prod --token=${{ secrets.VERCEL_TOKEN }}`

### 3. Node.js & Tooling
- Always set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as an environment variable in workflows to ensure proper Node runtime support on self-hosted runners.
- Use `node-version: 22` or later for web build/deployment steps.

## Verification & Safety

- When changing workflows, ensure that file triggers (`on.push.paths`) target exactly the directories affected.
- Avoid introducing inline scripts that bypass environment variable configuration; use GitHub secrets for all tokens.
- Review recent workflow runs or run local verification checks before pushing modifications.
