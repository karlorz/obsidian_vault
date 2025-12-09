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
| **Code scanning alerts(Security events)** | Read-only | Code scanning alerts integration |

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
| `CMUX_GITHUB_APP_PRIVATE_KEY` | Private key in **PKCS#8 format** (see note below) |
| `GITHUB_APP_WEBHOOK_SECRET` | Webhook secret (for signature verification) |
| `INSTALL_STATE_SECRET` | HMAC secret for signing installation state tokens (generate with `openssl rand -hex 32`) |

> **Important: Private Key Format**
>
> GitHub provides private keys in PKCS#1 format (`-----BEGIN RSA PRIVATE KEY-----`), but Convex's Web Crypto API requires **PKCS#8 format** (`-----BEGIN PRIVATE KEY-----`).
>
> Convert using:
> ```bash
> openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in github-app-private-key.pem
> ```
>
> The `setup-convex-env.sh` script handles this conversion automatically.

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

### ASN.1 DER Error: "unexpected ASN.1 DER tag: expected SEQUENCE, got INTEGER"

**Cause**: Private key is in PKCS#1 format instead of PKCS#8.

**Fix**:
Convert the key from PKCS#1 to PKCS#8:
```bash
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in github-app-private-key.pem
```

Or use the setup script which handles this automatically:
```bash
make convex-init-prod
# or
./scripts/setup-convex-env.sh --prod
```

### Convex Auth "No auth provider found matching the given token"

**Cause**: Trailing newlines in environment variable values corrupt the issuer URLs.

**Root cause analysis** (tested and confirmed):
1. Convex's `auth.config.ts` runs in a **V8 isolate** that **CAN access** `process.env` at runtime
2. Environment variables set via Convex dashboard ARE passed to the auth.config isolate
3. The original `setup-convex-env.sh` script used `echo "$value" | jq -Rs .` which added trailing newlines
4. This caused `NEXT_PUBLIC_STACK_PROJECT_ID` to be stored as `"uuid\n"` instead of `"uuid"`
5. The corrupted value produced invalid issuer URLs like:
   ```
   https://api.stack-auth.com/api/v1/projects/6bfe8b9a-2e36-431d-861c-01ba7712d844\n
   ```
6. Stack Auth JWT tokens have the correct issuer (no newline), so the comparison fails

**Fix**:
Use `printf '%s'` instead of `echo` in the setup script to avoid adding trailing newlines:
```bash
# Before (buggy) - echo adds a newline, jq -Rs preserves it
local escaped_value=$(echo "$value" | jq -Rs . | sed 's/^"//;s/"$//')

# After (fixed) - printf doesn't add trailing newline
local escaped_value=$(printf '%s' "$value" | jq -Rs . | sed 's/^"//;s/"$//')
```

Then re-run the setup script:
```bash
make convex-init-prod
# or
./scripts/setup-convex-env.sh --prod
```

> **Note**: The upstream code using `env.NEXT_PUBLIC_STACK_PROJECT_ID` works correctly - the issue was in our local setup script corrupting env var values with trailing newlines.

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
- GitHub App JWT signing: `packages/convex/_shared/githubApp.ts`
- Auth config: `packages/convex/convex/auth.config.ts`
- Client env: `apps/client/src/client-env.ts`
- Server env: `apps/www/lib/utils/www-env.ts`
- Dashboard install button: `apps/client/src/components/dashboard/DashboardInputControls.tsx`
- Setup script: `scripts/setup-convex-env.sh`

---

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make convex-init-prod` | Set Convex env vars for production (auto-converts PKCS#1 to PKCS#8) |
| `make convex-clear-prod` | Clear ALL data from production Convex DB |
