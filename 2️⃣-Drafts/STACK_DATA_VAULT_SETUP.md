# Stack Auth Data Vault Setup Guide

## Overview

The cmux application uses Stack Auth's Data Vault feature to securely store environment variables for workspace configurations. This guide explains how to set up the required data vault store.

## Problem

Without proper Stack Auth Data Vault configuration, you may encounter errors when using the `/api/workspace-configs` endpoint:

```
Error: Failed to persist environment variables
POST /api/workspace-configs 500
```

This typically happens when:
- The `cmux-snapshot-envs` data vault store doesn't exist in your Stack Auth account
- The `STACK_DATA_VAULT_SECRET` environment variable is not configured

## Prerequisites

### 1. Stack Auth Account

Ensure you have a Stack Auth account and project set up:
- Sign up at [stack-auth.com](https://stack-auth.com)
- Create a new project or use an existing one
- Note your project credentials:
  - `NEXT_PUBLIC_STACK_PROJECT_ID`
  - `NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY`
  - `STACK_SECRET_SERVER_KEY`

### 2. Environment Variables

Add the following to your environment configuration:

**Development** (`.env` or `.env.local`):
```env
NEXT_PUBLIC_STACK_PROJECT_ID=your_project_id
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=your_publishable_key
STACK_SECRET_SERVER_KEY=your_secret_key
STACK_DATA_VAULT_SECRET=your_vault_secret
```

**Production** (GitHub Actions, hosting platform, etc.):
Configure the same environment variables in your deployment environment.

## Setup Steps

### Step 1: Create the Data Vault Store

1. Log into your Stack Auth dashboard at [stack-auth.com](https://stack-auth.com)
2. Navigate to your project
3. Go to the Data Vault section
4. Create a new data vault store with the name: **`cmux-snapshot-envs`**

> **Important**: The store name must be exactly `cmux-snapshot-envs` (case-sensitive).

### Step 2: Configure the Vault Secret

Set the `STACK_DATA_VAULT_SECRET` environment variable. This secret is used to encrypt and decrypt data stored in the vault.

**Generate a secure secret**:
```bash
# Generate a random 32-character secret
openssl rand -hex 32
```

Add this value to your environment configuration as `STACK_DATA_VAULT_SECRET`.

### Step 3: Verify the Setup

Run the verification script to ensure everything is configured correctly:

```bash
cd apps/www
bun run scripts/hello-stack-secrets.ts
```

Expected output:
```
setting value
getting value
value a very secure cat
```

If you see any errors, double-check:
- The data vault store `cmux-snapshot-envs` exists in your Stack Auth dashboard
- All environment variables are correctly set
- The `STACK_DATA_VAULT_SECRET` matches between your environment and Stack Auth configuration

## How It Works

The `cmux-snapshot-envs` data vault is used throughout the application to:

1. **Store Environment Variables**: When creating or updating workspace configurations, the `envVarsContent` (entire `.env` file content) is encrypted and stored in the vault.

2. **Secure Encryption**: All data is encrypted using the `STACK_DATA_VAULT_SECRET` before being sent to Stack Auth's servers.

3. **Retrieve Environment Variables**: When loading workspace configurations, the encrypted data is retrieved from the vault and decrypted using the same secret.

### Code References

The data vault is used in these files:

- `apps/www/lib/routes/workspace-configs.route.ts:42` - Load and save workspace config env vars
- `apps/www/lib/routes/sandboxes/environment.ts` - Sandbox environment variable management
- `apps/www/lib/routes/environments.route.ts` - Environment configuration management

### Data Flow

```
User creates/updates workspace config
         ↓
envVarsContent is encrypted with STACK_DATA_VAULT_SECRET
         ↓
Encrypted data stored in Stack Auth vault with unique dataVaultKey
         ↓
dataVaultKey is stored in Convex database (workspaceConfigs table)
         ↓
When loading: retrieve dataVaultKey from Convex
         ↓
Use dataVaultKey to fetch encrypted data from Stack Auth vault
         ↓
Decrypt with STACK_DATA_VAULT_SECRET
         ↓
Return envVarsContent to application
```

## Troubleshooting

### Error: "Failed to persist environment variables"

**Cause**: The `cmux-snapshot-envs` data vault store doesn't exist in Stack Auth.

**Solution**: Follow Step 1 to create the data vault store.

### Error: "Unauthorized" or "Invalid secret"

**Cause**: The `STACK_DATA_VAULT_SECRET` is incorrect or not set.

**Solution**:
1. Verify the secret is set in your environment
2. Ensure it matches the secret configured in Stack Auth
3. Restart your development server after updating environment variables

### Production works but development doesn't

**Cause**: The data vault store is configured in production but not in your development Stack Auth project.

**Solution**:
- If using separate Stack Auth projects for dev/prod, create the `cmux-snapshot-envs` store in both projects
- Ensure both environments have the correct `STACK_DATA_VAULT_SECRET` configured

## Security Considerations

- **Never commit** `STACK_DATA_VAULT_SECRET` to version control
- Use different secrets for development and production environments
- Rotate the vault secret periodically following your security policies
- The data vault provides encryption at rest and in transit
- Only authenticated users with proper team access can read/write vault data

## Additional Resources

- [Stack Auth Documentation](https://docs.stack-auth.com/)
- [Stack Auth Data Vault API](https://docs.stack-auth.com/api/overview)
- [cmux Discord Community](https://discord.gg/SDbQmzQhRK)

## Support

If you encounter issues:
1. Check this guide's troubleshooting section
2. Verify all prerequisites are met
3. Run the verification script (Step 3)
4. Join the [cmux Discord](https://discord.gg/SDbQmzQhRK) for community support
5. Check [Stack Auth's documentation](https://docs.stack-auth.com/) for vault-specific questions
