# Setting up GitHub App for cmux

## Quick Steps

1. **Create GitHub App**: Go to GitHub Settings → Developer settings → GitHub Apps → New GitHub App
2. **Configure permissions**: Set repository permissions (Contents: Read & Write, Metadata: Read, Pull requests: Read)
3. **Generate App ID**: Copy the App ID as `CMUX_GITHUB_APP_ID`
4. **Generate Private Key**: Download and save as `CMUX_GITHUB_APP_PRIVATE_KEY`
5. **Get App Slug**: From the app settings page, copy the slug as `NEXT_PUBLIC_GITHUB_APP_SLUG`

## Detailed Setup

### 1. Create the GitHub App

The cmux application requires a GitHub App with specific permissions to access repositories and manage installations [1](#0-0) .

### 2. Required Permissions

Based on the codebase usage, the GitHub App needs these permissions:
- **Contents**: Read & Write (for creating previews and accessing code) [2](#0-1) 
- **Metadata**: Read (for repository information) [2](#0-1) 
- **Pull requests**: Read (for code review features) [3](#0-2) 

### 3. Environment Variables Configuration

After creating the app, you'll need to configure these environment variables:

#### Server-side variables:
```bash
CMUX_GITHUB_APP_ID=your_app_id_here
CMUX_GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n..."
```

These are used for server-side GitHub App authentication [4](#0-3) .

#### Client-side variable:
```bash
NEXT_PUBLIC_GITHUB_APP_SLUG=your-app-slug
```

This is used to construct installation URLs in the frontend [5](#0-4) .

### 4. Webhook Configuration

Set the webhook URL to: `https://your-domain.com/api/github/webhook`
Subscribe to events: Installation, Installation repositories

### 5. Installation Flow

The app uses these variables in the installation flow:
1. User clicks "Install GitHub App" [6](#0-5) 
2. System generates install state using the App ID [7](#0-6) 
3. User is redirected to GitHub using the App Slug [8](#0-7) 

## Notes

- The `CMUX_GITHUB_APP_ID` is the numeric ID shown on your GitHub App's main page
- The `NEXT_PUBLIC_GITHUB_APP_SLUG` is the URL-friendly name in your app's installation URL (e.g., `https://github.com/apps/your-app-slug/installations/new`)
- Store the private key securely - it's used to generate JWT tokens for API access [9](#0-8) 
- These variables are also referenced in CI/CD workflows as secrets [10](#0-9) 

Wiki pages you might want to explore:
- [Next.js Application Structure (manaflow-ai/cmux)](/wiki/manaflow-ai/cmux#7.1)

### Citations

**File:** apps/www/lib/utils/www-env.ts (L6-26)
```typescript
  server: {
    // Stack server-side env
    STACK_SECRET_SERVER_KEY: z.string().min(1),
    STACK_SUPER_SECRET_ADMIN_KEY: z.string().min(1),
    STACK_DATA_VAULT_SECRET: z.string().min(32), // For secure DataBook storage
    // GitHub App
    CMUX_GITHUB_APP_ID: z.string().min(1),
    CMUX_GITHUB_APP_PRIVATE_KEY: z.string().min(1),
    // Morph
    MORPH_API_KEY: z.string().min(1),
    OPENAI_API_KEY: z.string().min(1).optional(),
    GEMINI_API_KEY: z.string().min(1).optional(),
    ANTHROPIC_API_KEY: z.string().min(1),
    CMUX_TASK_RUN_JWT_SECRET: z.string().min(1),
  },
  client: {
    NEXT_PUBLIC_STACK_PROJECT_ID: z.string().min(1),
    NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY: z.string().min(1),
    NEXT_PUBLIC_CONVEX_URL: z.string().min(1),
    NEXT_PUBLIC_GITHUB_APP_SLUG: z.string().min(1).optional(),
  },
```

**File:** apps/www/lib/utils/github-app-token.ts (L34-37)
```typescript
  permissions = {
    contents: "write",
    metadata: "read",
  },
```

**File:** apps/www/lib/utils/github-app-token.ts (L52-56)
```typescript
    auth: {
      appId: env.CMUX_GITHUB_APP_ID,
      privateKey: githubPrivateKey,
      installationId,
    },
```

**File:** apps/www/lib/services/code-review/run-simple-anthropic-review.ts (L246-250)
```typescript
          permissions: {
            contents: "read",
            metadata: "read",
            pull_requests: "read",
          },
```

**File:** apps/www/components/preview/preview-dashboard.tsx (L2607-2614)
```typescript
        const githubAppSlug = process.env.NEXT_PUBLIC_GITHUB_APP_SLUG;
        if (!githubAppSlug) {
          throw new Error("GitHub App slug is not configured");
        }

        const url = new URL(
          `https://github.com/apps/${githubAppSlug}/installations/new`
        );
```

**File:** apps/client/src/components/dashboard/DashboardInputControls.tsx (L529-535)
```typescript
                      const slug = env.NEXT_PUBLIC_GITHUB_APP_SLUG!;
                      const baseUrl = `https://github.com/apps/${slug}/installations/new`;
                      const { state } = await mintState({ teamSlugOrId });
                      const sep = baseUrl.includes("?") ? "&" : "?";
                      const url = `${baseUrl}${sep}state=${encodeURIComponent(
                        state,
                      )}`;
```

**File:** apps/www/lib/routes/github.install-state.route.ts (L84-86)
```typescript
          appId: env.CMUX_GITHUB_APP_ID,
          privateKey: githubPrivateKey,
        },
```

**File:** apps/www/lib/routes/github.install-state.route.ts (L96-99)
```typescript
      const installUrl = new URL(
        `https://github.com/apps/${appSlug}/installations/new`,
      );
      installUrl.searchParams.set("state", result.state);
```

**File:** packages/convex/_shared/githubApp.ts (L186-194)
```typescript
  const appId = env.CMUX_GITHUB_APP_ID;
  const privateKey = env.CMUX_GITHUB_APP_PRIVATE_KEY;
  if (!appId || !privateKey) {
    return null;
  }

  try {
    const normalizedPrivateKey = privateKey.replace(/\\n/g, "\n");
    const jwt = await createGithubAppJwt(appId, normalizedPrivateKey);
```

**File:** .github/workflows/checks.yml (L42-43)
```yaml
          CMUX_GITHUB_APP_ID: ${{ secrets.CMUX_GITHUB_APP_ID }}
          CMUX_GITHUB_APP_PRIVATE_KEY: ${{ secrets.CMUX_GITHUB_APP_PRIVATE_KEY }}
```
