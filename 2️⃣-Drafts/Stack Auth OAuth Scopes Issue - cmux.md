# Stack Auth OAuth Scopes Issue - cmux

**Date:** 2025-11-30
**Updated:** 2025-12-21
**Status:** ⚠️ Partially Obsolete - See Update Below
**Issue Type:** Missing Codebase Configuration

> [!warning] Important Update (2025-12-21)
> **Upstream has switched from OAuth App to GitHub App for Stack Auth login.**
>
> - Production (`cmux.sh`) now uses **GitHub App** `cmux-agent` (`Iv23lizj2TGiaHRDIEsO`) for user authentication
> - GitHub Apps use **app-level permissions** instead of OAuth scopes
> - The `oauthScopesOnSignIn` configuration may no longer be relevant if using GitHub App for auth
> - See [[github app.md]] for GitHub App setup including Stack Auth integration

## Problem Summary (Original - OAuth App)

When creating new tasks/workspaces with cloud mode enabled in cmux, GitHub authentication failed with error:
```
error validating token: missing required scopes 'repo', 'read:org'
```

GitHub OAuth authorization screen only showed:
- ✅ Access user email addresses (read-only)

Missing scopes:
- ❌ Organizations and teams (read:org)
- ❌ Repositories (repo)

## Root Cause (OAuth App Setup)

> [!note] This section applies only if using **OAuth App** for Stack Auth login

**This IS a codebase issue.** The `oauthScopesOnSignIn` configuration **is missing from the upstream repository** (as of v1.0.182).

### Investigation Results (2025-11-30)

**Upstream Repository Status:**
- ✅ Checked v1.0.182 release (latest as of investigation)
- ❌ `oauthScopesOnSignIn` configuration **NOT present** in either:
  - `apps/www/lib/utils/stack.ts` (server-side)
  - `apps/client/src/lib/stack.ts` (client-side)
- ❌ No issues or PRs in manaflow-ai/cmux repository report this problem
- ❌ No commits in git history adding this configuration

**Local Fix Applied:**
The `oauthScopesOnSignIn` configuration exists only as **uncommitted local changes** from troubleshooting this issue.

### How Stack Auth Handles OAuth Scopes

According to [Stack Auth Issue #606](https://github.com/stack-auth/stack-auth/issues/606):

> "this was a result of connecting the account before specifying `oauthScopesOnSignIn`"

Stack Auth caches the OAuth scopes when you **first connect** an OAuth provider. If you later add `oauthScopesOnSignIn` to request additional scopes, existing connections will NOT automatically update to request the new scopes.

This is expected behavior and documented in Stack Auth's issue tracker.

## Solution

### 1. Add `oauthScopesOnSignIn` Configuration

Add the configuration to **both** server-side and client-side Stack Auth instances:

**Server-side** (`apps/www/lib/utils/stack.ts`):
```typescript
export const stackServerApp = new StackServerApp({
  projectId: env.NEXT_PUBLIC_STACK_PROJECT_ID,
  publishableClientKey: env.NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY,
  secretServerKey: env.STACK_SECRET_SERVER_KEY,
  tokenStore: "nextjs-cookie",
  urls: {
    afterSignIn: "/handler/after-sign-in",
    afterSignUp: "/handler/after-sign-in",
  },
  oauthScopesOnSignIn: {
    github: ["repo", "read:org", "user:email"],
  },
});
```

**Client-side** (`apps/client/src/lib/stack.ts`):
```typescript
export const stackClientApp = new StackClientApp({
  projectId: env.NEXT_PUBLIC_STACK_PROJECT_ID,
  publishableClientKey: env.NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY,
  tokenStore: "cookie",
  redirectMethod: {
    useNavigate() {
      const navigate = useTanstackNavigate();
      return (to: string) => {
        navigate({ to });
      };
    },
  },
  oauthScopesOnSignIn: {
    github: ["repo", "read:org", "user:email"],
  },
});
```

### 2. Remove Old OAuth Connection

Since scopes are cached on first connection, you must disconnect and reconnect to apply new scopes:

**Option A: Via Stack Auth Dashboard**
1. Go to https://app.stack-auth.com
2. Navigate to your project → Users
3. Click on your user account
4. In the "OAuth Providers" section, click the menu next to GitHub
5. Click "Delete" to remove the OAuth connection

**Option B: Via GitHub Settings**
1. Go to https://github.com/settings/applications
2. Find the cmux OAuth app
3. Click "Revoke" to remove the authorization

### 3. Restart Servers

```bash
make dev
```

### 4. Reconnect GitHub Account

1. Sign in to cmux
2. Connect GitHub OAuth again
3. Verify the authorization screen now requests all three scopes:
   - ✅ Organizations and teams (Read-only access)
   - ✅ Repositories (Public and private)
   - ✅ Access user email addresses (read-only)

## Prevention Guidelines

To avoid this issue in the future:

1. **Always configure `oauthScopesOnSignIn` BEFORE first OAuth connection**
2. **Document required OAuth scopes** in project README or setup guide
3. **Test OAuth flow** in development before deploying to production
4. **Educate team members** about Stack Auth's scope caching behavior

## Why This IS a Codebase Issue

### The Missing Configuration

The upstream cmux codebase (including v1.0.182) **lacks the `oauthScopesOnSignIn` configuration**. This means:

1. ❌ **All new users** will experience this issue when first connecting GitHub
2. ❌ **Production deployments** will have this problem
3. ❌ **Every fresh installation** will fail GitHub authentication for cloud workspaces

### Impact on Users

Without `oauthScopesOnSignIn` in the codebase:
- GitHub OAuth only requests the default scope: `user:email`
- Cloud workspace creation fails with: `error validating token: missing required scopes 'repo', 'read:org'`
- Users must manually:
  1. Add the configuration themselves
  2. Delete their OAuth connection
  3. Reconnect with proper scopes

### Recommended Upstream Fix

This issue should be fixed in the upstream repository by:
1. **Adding `oauthScopesOnSignIn` to both Stack Auth configurations**
2. **Adding documentation** about required GitHub scopes
3. **Optionally:** Improving error messages to guide users when scopes are missing

## Technical Details

### Required GitHub Scopes for cmux

| Scope | Purpose |
|-------|---------|
| `repo` | Full access to repositories (needed for git operations in sandboxes) |
| `read:org` | Read organization membership (needed for accessing org repositories) |
| `user:email` | Access email addresses (needed for user identification) |

### Where Scopes Are Validated

The scope validation happens in sandbox provisioning:

**File:** `apps/www/lib/routes/sandboxes/git.ts` (lines 36-86)

```typescript
export const configureGithubAccess = async (
  instance: MorphInstance,
  token: string,
  maxRetries = 5
) => {
  // Validates that the token has required scopes
  // Fails with "missing required scopes" error if scopes are insufficient
}
```

## References

- Stack Auth OAuth Scopes Documentation: https://docs.stack-auth.com/docs/apps/oauth
- Stack Auth Issue #606 (Discord oauthScopesOnSignIn not taking effect): https://github.com/stack-auth/stack-auth/issues/606
- GitHub OAuth Scopes Documentation: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps
- cmux Repository: https://github.com/manaflow-ai/cmux

## Upstream Contribution Needed

### Current Status (v1.0.182)
- ❌ `oauthScopesOnSignIn` not configured
- ❌ No documentation about required GitHub scopes
- ❌ No issues filed in repository about this problem

### Suggested Actions
1. **File an issue** in manaflow-ai/cmux repository describing this problem
2. **Submit a PR** adding the `oauthScopesOnSignIn` configuration to both:
   - `apps/www/lib/utils/stack.ts`
   - `apps/client/src/lib/stack.ts`
3. **Add documentation** in README about required GitHub OAuth scopes
4. **Consider adding** better error messages when GitHub authentication fails due to missing scopes

## Related Files

- `apps/www/lib/utils/stack.ts` - Server-side Stack Auth configuration
- `apps/client/src/lib/stack.ts` - Client-side Stack Auth configuration
- `apps/www/lib/routes/sandboxes/git.ts` - GitHub token validation logic
- `.env.production` - Stack Auth environment variables

---

**Key Takeaways:**
1. **This is a codebase issue:** The `oauthScopesOnSignIn` configuration is missing from the upstream repository (v1.0.182 and earlier)
2. **All users are affected:** Anyone installing cmux and connecting GitHub will encounter this issue
3. **Local fix applied:** The configuration has been added locally but needs to be contributed upstream
4. **Scope caching behavior:** Stack Auth caches OAuth scopes on first connection - reconnection required after adding configuration
5. **Upstream contribution needed:** Issue should be filed and PR submitted to fix this in the main repository

---

## Update: GitHub App vs OAuth App for Stack Auth (2025-12-21)

### Two Authentication Systems in cmux

cmux uses **two separate GitHub integrations**:

| Purpose | Type | Example Client ID |
|---------|------|-------------------|
| **User Login** (via Stack Auth) | GitHub App OR OAuth App | `Iv23li...` (App) or `Ov23li...` (OAuth) |
| **Repository Access** (installations) | GitHub App | Configured via `NEXT_PUBLIC_GITHUB_APP_SLUG` |

### Upstream Production Setup

As of late 2025, upstream production (`cmux.sh`) uses:
- **Stack Auth login:** GitHub App `cmux-agent` (`Iv23lizj2TGiaHRDIEsO`) by manaflow-ai
- **Repository access:** GitHub App `cmux-client`

### How to Identify Which Type You're Using

Check your Stack Auth project's GitHub SSO configuration:
- **Client ID starts with `Ov23li...`** → OAuth App (this note applies)
- **Client ID starts with `Iv23li...`** → GitHub App (permissions set in app settings, not OAuth scopes)

### Switching from OAuth App to GitHub App

If you want to match upstream's auth pattern:

1. **Configure your GitHub App for Stack Auth:**
   - Add callback URL: `https://api.stack-auth.com/api/v1/auth/oauth/callback/github`
   - Generate a Client Secret for the GitHub App

2. **Update Stack Auth GitHub SSO:**
   - Client ID: Use your GitHub App's `Iv23li...` ID
   - Client Secret: Use the generated secret

3. **Users will see:**
   - "Authorize [Your GitHub App]" instead of OAuth App authorization
   - Permissions are app-level, not OAuth scopes

See [[github app.md#Stack Auth Integration]] for detailed setup instructions.
