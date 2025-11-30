# Stack Auth OAuth Scopes Issue - cmux

**Date:** 2025-11-30
**Status:** ✅ Resolved
**Issue Type:** Configuration & User State Management

## Problem Summary

When creating new tasks/workspaces with cloud mode enabled in cmux, GitHub authentication failed with error:
```
error validating token: missing required scopes 'repo', 'read:org'
```

GitHub OAuth authorization screen only showed:
- ✅ Access user email addresses (read-only)

Missing scopes:
- ❌ Organizations and teams (read:org)
- ❌ Repositories (repo)

## Root Cause

**This is NOT a codebase issue.** The issue was caused by **connecting GitHub OAuth BEFORE adding the `oauthScopesOnSignIn` configuration**.

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

## Why This Isn't a Codebase Issue

The official cmux production app doesn't have this issue because:

1. The `oauthScopesOnSignIn` configuration was added to the codebase from the beginning
2. Users connecting for the first time automatically get the correct scopes
3. This issue only affects:
   - **Early adopters** who connected before the configuration was added
   - **Development environments** where developers connect before adding the config
   - **Self-hosted instances** where the deployer connects before configuring scopes

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

## Related Files

- `apps/www/lib/utils/stack.ts` - Server-side Stack Auth configuration
- `apps/client/src/lib/stack.ts` - Client-side Stack Auth configuration
- `apps/www/lib/routes/sandboxes/git.ts` - GitHub token validation logic
- `.env.production` - Stack Auth environment variables

---

**Key Takeaway:** Stack Auth's `oauthScopesOnSignIn` must be configured **before** users first connect their OAuth accounts, as scopes are cached on initial connection and do not automatically update when the configuration changes.
