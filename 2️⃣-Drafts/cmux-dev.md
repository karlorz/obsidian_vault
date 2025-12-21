To set up GitHub App Integration for local development, you need to configure four environment variables in your local `.env` file:

## Required Environment Variables

Create a `.env.local` file in the root of your project with these variables:

```bash
# GitHub App Configuration
CMUX_GITHUB_APP_ID=your_github_app_id_here
CMUX_GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
your_github_app_private_key_here
-----END RSA PRIVATE KEY-----"
GITHUB_APP_WEBHOOK_SECRET=your_github_webhook_secret_here
NEXT_PUBLIC_GITHUB_APP_SLUG=your_github_app_slug_here
```

## How to Obtain These Values

### 1. Create a GitHub App
1. Go to GitHub Settings → Developer settings → GitHub Apps
2. Click "New GitHub App"
3. Fill in the app details:
   - **App name**: Choose a unique name (e.g., "cmux-local-dev")
   - **Homepage URL**: `http://localhost:5173` (for local dev)
   - **Webhook URL**: `https://9779.karldigi.dev/api/github/webhook` (or use ngrok for testing)

### 2. Configure Permissions
Set these repository permissions:
- **Contents**: Read & write
- **Metadata**: Read
- **Pull requests**: Read & write

### 3. Get the Values
- **App ID**: Found on the app's main page
- **Private Key**: Generate and download a PEM file from the app settings
- **Webhook Secret**: Create a secret in the webhook settings
- **App Slug**: The URL-friendly name from the app's page (e.g., "cmux-local-dev")

## Environment Variable Details

The environment variables are validated in the configuration files:

- `CMUX_GITHUB_APP_ID` and `CMUX_GITHUB_APP_PRIVATE_KEY` are required for server-side GitHub API authentication [1](#0-0) 
- `GITHUB_APP_WEBHOOK_SECRET` validates incoming webhook events [2](#0-1) 
- `NEXT_PUBLIC_GITHUB_APP_SLUG` is used client-side for the GitHub App installation flow [3](#0-2) 

## Private Key Format

The private key must be properly formatted with newlines. The system handles normalization by replacing `\n` with actual newlines [4](#0-3) .

## Testing the Setup

You can test your GitHub App configuration using the test script:

```bash
bun run apps/www/scripts/github-test.ts
```

This script validates the connection and lists repositories accessible through the GitHub App [5](#0-4) .

## Notes

- For local development, you can use `http://localhost:3000` as the webhook URL
- If you need to test webhooks locally, consider using ngrok to expose your local server
- The GitHub App must be installed on your test repositories to work properly
- All four variables are required for the GitHub integration to function correctly

---

## Stack Auth Integration (Optional - for GitHub App Login)

> [!info] Added 2025-12-21
> If you want user login to use your GitHub App (matching upstream production), additional setup is required.

### Why This Matters

cmux has **two separate GitHub integrations**:
1. **Repository Access** - Uses GitHub App for repo installation (configured above)
2. **User Login** - Uses Stack Auth, which can use either OAuth App OR GitHub App

Upstream production uses **GitHub App** for both. By default, Stack Auth uses its shared OAuth credentials.

### Configure GitHub App for Stack Auth Login

#### 1. Add Stack Auth Callback URL

In your GitHub App settings, add this callback URL:
```
https://api.stack-auth.com/api/v1/auth/oauth/callback/github
```

#### 2. Generate Client Secret

In GitHub App settings → "Client secrets" → "Generate a new client secret"

**Save this immediately** - you won't see it again.

#### 3. Update Stack Auth

Go to your Stack Auth project → Auth Methods → GitHub → Configure:

| Field | Value |
|-------|-------|
| Client ID | Your GitHub App's `Iv23li...` ID |
| Client Secret | The secret you generated |

### Verification

After setup, users logging in will see authorization for your **GitHub App** (shows in `github.com/settings/apps/authorizations`) instead of an OAuth App (shows in `github.com/settings/applications`).

See [[github app.md#Stack Auth Integration]] for detailed instructions.

---

Wiki pages you might want to explore:
- [External Integrations (manaflow-ai/cmux)](/wiki/manaflow-ai/cmux#10)
- [Environment and Repository Management (manaflow-ai/cmux)](/wiki/manaflow-ai/cmux#7.3)

### Citations

**File:** apps/www/lib/utils/www-env.ts (L11-14)
```typescript
    // GitHub App
    CMUX_GITHUB_APP_ID: z.string().min(1),
    CMUX_GITHUB_APP_PRIVATE_KEY: z.string().min(1),
    // Morph
```

**File:** apps/www/lib/utils/www-env.ts (L25-25)
```typescript
    NEXT_PUBLIC_GITHUB_APP_SLUG: z.string().min(1).optional(),
```

**File:** packages/convex/_shared/convex-env.ts (L12-12)
```typescript
    GITHUB_APP_WEBHOOK_SECRET: z.string().min(1).optional(),
```

**File:** apps/www/lib/utils/githubPrivateKey.ts (L3-6)
```typescript
export const githubPrivateKey = env.CMUX_GITHUB_APP_PRIVATE_KEY.replace(
  /\\n/g,
  "\n"
);
```

**File:** apps/www/scripts/github-test.ts (L44-88)
```typescript
// For each provider connection (GitHub App installation), use an installation token
// so private repos are included. Do NOT use the user's OAuth token here.
const appId = env.CMUX_GITHUB_APP_ID;

await Promise.all(
  result
    .filter((c) => c.isActive)
    .map(async (connection) => {
      if (!connection.installationId) {
        throw new Error("Missing installationId for connection");
      }

      // Create an Octokit client authenticated as the app installation
      const octokit = new Octokit({
        authStrategy: createAppAuth,
        auth: {
          appId,
          privateKey: githubPrivateKey,
          installationId: connection.installationId,
        },
      });

      // List repositories accessible to this installation (includes private)
      try {
        const { data } = await octokit.request(
          "GET /installation/repositories",
          { per_page: 100 }
        );

        const repos = data.repositories.map((r) => ({
          name: r.name,
          full_name: r.full_name,
          private: r.private,
        }));

        console.log(repos);
      } catch (err) {
        const e = err as { status?: number; message?: string };
        console.error(
          `Failed to list repos for installation ${connection.installationId} (${connection.accountLogin ?? "unknown"})`,
          e
        );
      }
    })
);
```
