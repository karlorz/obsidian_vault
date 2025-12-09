# Setting up GitHub App for cmux

## Quick Steps

1. **Create GitHub App**: Go to GitHub Settings → Developer settings → GitHub Apps → New GitHub App
2. **Configure permissions**: See [Required Permissions](#required-permissions) below
3. **Configure webhook**: See [Webhook Configuration](#webhook-configuration) below
4. **Generate App ID**: Copy the App ID as `CMUX_GITHUB_APP_ID`
5. **Generate Private Key**: Download and save as `CMUX_GITHUB_APP_PRIVATE_KEY`
6. **Get App Slug**: From the app settings page, copy the slug as `NEXT_PUBLIC_GITHUB_APP_SLUG`
7. **Set environment variables**: See [Environment Variables](#environment-variables-configuration) below

---

## Required Permissions

### Repository Permissions

| Permission | Access Level | Why Needed |
|------------|--------------|------------|
| **Contents** | Read & Write | Create/delete branches, merge branches, create/update files |
| **Pull requests** | Read & Write | Create PRs, merge PRs, mark draft as ready |
| **Issues** | Read & Write | Add comments and reactions to PRs (GitHub API treats PR comments as issue comments) |
| **Metadata** | Read-only | Required for all GitHub Apps - access repo info |
| **Actions** | Read-only | Process `workflow_run` webhook events |
| **Checks** | Read-only | Process `check_run` webhook events (Vercel, CI, etc.) |
| **Commit statuses** | Read-only | Process `status` webhook events |
| **Deployments** | Read-only | Process `deployment` and `deployment_status` webhook events |

### Account Permissions

| Permission | Access Level | Why Needed |
|------------|--------------|------------|
| **Email addresses** | Read-only | Get user email for identification |

---

## Webhook Configuration

### Webhook URL
```
https://<your-convex-deployment>.convex.site/github_webhook
```

Example: `https://outstanding-stoat-794.convex.site/github_webhook`

### Webhook Events to Subscribe

Check these boxes in your GitHub App settings:

- [x] Installation
- [x] Push
- [x] Pull request
- [x] Pull request review
- [x] Pull request review comment
- [x] Issue comment
- [x] Workflow run
- [x] Check run
- [x] Check suite
- [x] Deployment
- [x] Deployment status
- [x] Status

---

## Environment Variables Configuration

### 1. Convex Environment Variables

Set these in your **Convex Dashboard** → Settings → Environment Variables:

| Variable | Description |
|----------|-------------|
| `CMUX_GITHUB_APP_ID` | Numeric App ID from GitHub App settings |
| `CMUX_GITHUB_APP_PRIVATE_KEY` | RSA private key (PEM format) |
| `GITHUB_APP_WEBHOOK_SECRET` | Webhook secret (for signature verification) |
| `INSTALL_STATE_SECRET` | HMAC secret for signing installation state tokens (generate with `openssl rand -hex 32`) |

### 2. Vercel Environment Variables (apps/client)

Set these in your **Vercel Project** → Settings → Environment Variables:

| Variable | Description |
|----------|-------------|
| `NEXT_PUBLIC_GITHUB_APP_SLUG` | GitHub App slug (e.g., `cmux-client`) |

**Important**: After adding this variable, you must **redeploy** the client app for changes to take effect.

### 3. Vercel Environment Variables (apps/www)

Set these in your **Vercel Project** for the www app:

| Variable | Description |
|----------|-------------|
| `CMUX_GITHUB_APP_ID` | Numeric App ID |
| `CMUX_GITHUB_APP_PRIVATE_KEY` | RSA private key |
| `GITHUB_APP_WEBHOOK_SECRET` | Webhook secret |
| `NEXT_PUBLIC_GITHUB_APP_SLUG` | GitHub App slug |

---

## Installation Flow

How the GitHub App installation works:

1. User clicks "Add repos from GitHub" in the dashboard
2. Client checks `NEXT_PUBLIC_GITHUB_APP_SLUG` is set
3. Client calls `mintInstallState` mutation to generate signed state token
4. User is redirected to `https://github.com/apps/{slug}/installations/new?state={token}`
5. User authorizes the app and selects repositories
6. GitHub redirects to `/github_setup` with `installation_id` and `state`
7. Convex validates state signature and stores the installation in `providerConnections` table
8. Repositories are synced to the `repos` table
9. Pop-up closes and dashboard refreshes to show available repos

---

## Troubleshooting

### "GitHub App not configured. Please contact support."

**Cause**: `NEXT_PUBLIC_GITHUB_APP_SLUG` is not set in the client build.

**Fix**:
1. Add `NEXT_PUBLIC_GITHUB_APP_SLUG` to Vercel environment variables for `apps/client`
2. Redeploy the client app

### Empty repository list after installation

**Cause**: Installation webhook not processed or `INSTALL_STATE_SECRET` missing.

**Fix**:
1. Check Convex has `INSTALL_STATE_SECRET` set
2. Check GitHub App webhook deliveries at `https://github.com/settings/apps/{slug}/advanced`
3. Verify webhook URL is correct and webhook secret matches

### Webhook returns 400/500 errors

**Cause**: `GITHUB_APP_WEBHOOK_SECRET` mismatch or missing.

**Fix**:
1. Ensure the webhook secret in GitHub App settings matches `GITHUB_APP_WEBHOOK_SECRET` in Convex
2. Check Convex logs for specific error messages

---

## Notes

- The `CMUX_GITHUB_APP_ID` is the numeric ID shown on your GitHub App's main page
- The `NEXT_PUBLIC_GITHUB_APP_SLUG` is the URL-friendly name in your app's installation URL (e.g., `https://github.com/apps/your-app-slug/installations/new`)
- Store the private key securely - it's used to generate JWT tokens for API access
- Installation state tokens expire after 10 minutes
- These variables are also referenced in CI/CD workflows as secrets

---

## Reference: Codebase Locations

- Webhook handler: `packages/convex/convex/github_webhook.ts`
- HTTP routes: `packages/convex/convex/http.ts`
- State token generation: `packages/convex/convex/github_app.ts`
- Installation setup: `packages/convex/convex/github_setup.ts`
- Client env: `apps/client/src/client-env.ts`
- Server env: `apps/www/lib/utils/www-env.ts`
- Dashboard install button: `apps/client/src/components/dashboard/DashboardInputControls.tsx`
