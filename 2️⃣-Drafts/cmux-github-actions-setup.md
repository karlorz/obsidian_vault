# cmux GitHub Actions Workflow Setup Guide

## Overview

The `.github/workflows/release-updates.yml` workflow builds and publishes Electron desktop app updates for cmux across multiple platforms (macOS, Windows, Linux).

**Triggers:**
- Manual dispatch via GitHub Actions UI
- Automatic on push to `main` branch when `package.json` or `apps/client/package.json` changes

## Workflow Architecture

### Job Flow

```
prepare-release (Ubuntu)
    ↓
    ├─→ mac-arm64 (self-hosted)
    ├─→ mac-universal (self-hosted)
    ├─→ windows-x64 (windows-latest)
    └─→ linux-x64 (ubuntu-latest)
```

### 1. prepare-release Job

**Purpose:** Version resolution and release creation

- Reads version from `apps/client/package.json` (line 50)
- Searches for existing GitHub release matching version
- Creates draft release if none exists
- Outputs `release_tag` for downstream jobs

### 2. Platform Build Jobs

#### mac-arm64 (lines 213-320)
- **Runner:** `self-hosted` (requires Apple Silicon Mac)
- **Target:** Apple Silicon (aarch64-apple-darwin)
- **Output:** `.dmg`, `.zip`, `.yml`, `.blockmap` files
- **Special:** Builds Rust native addon, signs & notarizes

#### mac-universal (lines 322-545)
- **Runner:** `self-hosted` (requires Apple Silicon Mac)
- **Target:** Universal binary (arm64 + x64)
- **Output:** Universal `.dmg` (renamed with `-universal` suffix)
- **Special:**
  - Builds both architecture slices of Rust addon
  - Full notarization workflow with stapling
  - Renames `latest-mac.yml` → `latest-universal-mac.yml`

#### windows-x64 (lines 547-596)
- **Runner:** `windows-latest` (GitHub-hosted)
- **Target:** x86_64-pc-windows-msvc
- **Output:** Windows installer artifacts
- **Special:** Uses PowerShell for Rust build

#### linux-x64 (lines 598-644)
- **Runner:** `ubuntu-latest` (GitHub-hosted)
- **Target:** x86_64-unknown-linux-gnu
- **Output:** AppImage format
- **Special:** Simplest build, no signing required

**Note:** `mac-x64` job exists but is commented out (lines 95-211)

## Required GitHub Secrets

Configure these in your fork: **Settings → Secrets and variables → Actions → Repository secrets**

### Environment Secrets (All Platforms)

Referenced throughout workflow (lines 150-155, 273-277, 399-403, 578-582, 627-630):

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `NEXT_PUBLIC_CONVEX_URL` | Convex deployment URL | `https://your-project.convex.cloud` |
| `NEXT_PUBLIC_STACK_PROJECT_ID` | Stack Auth project ID | `project_abc123xyz` |
| `NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY` | Stack Auth client key | `pk_live_abc123...` |
| `NEXT_PUBLIC_WWW_ORIGIN` | Web app origin URL | `https://your-app.com` |
| `NEXT_PUBLIC_GITHUB_APP_SLUG` | GitHub App slug | `your-github-app` |

**These are injected into `.env` file during build process**

### CI/CD Secrets (Checks & Tests Workflows)

These secrets are required for `.github/workflows/checks.yml` and `.github/workflows/tests.yml`:

| Secret Name | Description | Format |
|-------------|-------------|--------|
| `STACK_SECRET_SERVER_KEY` | Stack Auth server key | Plain string |
| `STACK_SUPER_SECRET_ADMIN_KEY` | Stack Auth admin key | Plain string |
| `STACK_DATA_VAULT_SECRET` | Stack Auth data vault secret | Plain string |
| `CMUX_GITHUB_APP_ID` | GitHub App ID | Plain string (e.g., `123456`) |
| `CMUX_GITHUB_APP_PRIVATE_KEY` | GitHub App private key | **Single-line with `\n`** (see below) |
| `CMUX_TASK_RUN_JWT_SECRET` | JWT secret for task runs | Plain string |
| `MORPH_API_KEY` | Morph Cloud API key | Plain string |
| `CONVEX_DEPLOY_KEY` | Convex deployment key | Plain string |
| `ANTHROPIC_API_KEY` | Anthropic API key | Plain string |
| `STACK_TEST_USER_ID` | Test user ID for e2e tests | Plain string |

### GitHub App Private Key Setup (Critical)

The `CMUX_GITHUB_APP_PRIVATE_KEY` requires special handling depending on the environment.

**Symptoms of incorrect setup:**
- CI fails with `error:0900006e:PEM routines:OPENSSL_internal:NO_START_LINE`
- CI fails with `error:1E08010C:DECODER routines::unsupported`
- Error occurs at module load time, not during GitHub API calls

#### Format Requirements by Environment

| Environment | Required Format | Why |
|-------------|-----------------|-----|
| **GitHub Secrets** | Single-line with literal `\n` | GitHub can mangle multi-line values |
| **Convex** | Either format works | JSON API preserves newlines; `setup-convex-env.sh` uploads multi-line |
| **Vercel** | Single-line with literal `\n` | Environment variables can mangle multi-line |
| **Local `.env`** | Either format works | Both are handled by code |

#### Setting GitHub Secrets (Single-line format)

Convert your `.pem` file to single-line format:
```bash
# Generate single-line key
awk '{printf "%s\\n", $0}' /path/to/your-github-app-private-key.pem
```

Set in GitHub Secrets:
```bash
awk '{printf "%s\\n", $0}' /path/to/your-github-app-private-key.pem | gh secret set CMUX_GITHUB_APP_PRIVATE_KEY --repo karlorz/cmux
```

#### Setting Convex Environment Variables

Use `scripts/setup-convex-env.sh` which reads from your `.env` file and uploads via JSON API:
```bash
# Local development
./scripts/setup-convex-env.sh

# Production
./scripts/setup-convex-env.sh --prod --env-file .env.production
```

The script uploads the key with **actual newlines** (multi-line format) via JSON encoding. The Convex dashboard will show the key as multi-line - this is correct and expected.

#### How the Code Handles Both Formats

All code paths use `.replace(/\\n/g, "\n")` which:
- **Single-line input** (literal `\n`): Converts to actual newlines
- **Multi-line input** (actual newlines): No change needed, passes through

| Environment | File | How It Handles the Key |
|-------------|------|------------------------|
| `apps/www` (Node.js) | `lib/utils/githubPrivateKey.ts` | `.replace(/\\n/g, "\n")` then `node:crypto` converts PKCS#1 → PKCS#8 |
| `packages/convex` (Web Crypto) | `_shared/githubApp.ts` | `.replace(/\\n/g, "\n")` then pure JS ASN.1 wrapping converts PKCS#1 → PKCS#8 |

#### Why PKCS#1 vs PKCS#8 matters

- GitHub generates keys in **PKCS#1** format (`-----BEGIN RSA PRIVATE KEY-----`)
- Web Crypto API (`crypto.subtle.importKey`) only supports **PKCS#8** format (`-----BEGIN PRIVATE KEY-----`)
- The Convex runtime cannot use `node:crypto`, so it uses pure JavaScript ASN.1 manipulation to wrap PKCS#1 in PKCS#8 structure
- This conversion happens automatically at runtime - no manual pre-conversion needed

### macOS Signing & Notarization Secrets

Referenced at lines 162-166, 285-289, 444-448:

| Secret Name | Description | How to Generate |
|-------------|-------------|-----------------|
| `MAC_CERT_BASE64` | Base64-encoded .p12 certificate | `base64 -i cert.p12 \| pbcopy` |
| `MAC_CERT_PASSWORD` | Password for .p12 certificate | Password you set during export |
| `APPLE_API_KEY` | Base64-encoded .p8 API key | `base64 -i AuthKey_XXX.p8 \| pbcopy` |
| `APPLE_API_KEY_ID` | Apple API key ID | Found in App Store Connect (e.g., `ABC123XYZ`) |
| `APPLE_API_ISSUER` | Apple API issuer UUID | Found in App Store Connect (UUID format) |

## Additional Setup Requirements

### 1. Self-Hosted macOS Runner

**Jobs affected:** `mac-arm64`, `mac-universal`

**Why needed:** GitHub doesn't provide hosted Apple Silicon runners for free

**Setup steps:**
1. Get an Apple Silicon Mac (M1/M2/M3/M4)
2. Install GitHub Actions runner:
   - Go to **Settings → Actions → Runners → New self-hosted runner**
   - Follow macOS arm64 instructions
3. Install dependencies:
   ```bash
   # Install Homebrew if needed
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

   # Install Node.js 24
   brew install node@24

   # Install Bun 1.2.21
   curl -fsSL https://bun.sh/install | bash

   # Install Rust
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   rustup target add aarch64-apple-darwin x86_64-apple-darwin

   # Install Xcode command-line tools
   xcode-select --install
   ```
4. Start the runner as a service

**Alternative:** Modify workflow to use `macos-14` or `macos-latest` (slower, costs GitHub Actions minutes)

### 2. GitHub Environment

**Referenced:** lines 216, 325, 550, 601

Create an `electron` environment:
1. Go to **Settings → Environments**
2. Click **New environment**
3. Name it `electron`
4. (Optional) Add environment-specific protection rules or secrets

### 3. Repository Permissions

**Required:** `contents: write` (lines 18, 30)

Ensure GitHub Actions has write permissions:
- **Settings → Actions → General → Workflow permissions**
- Select "Read and write permissions"

## How to Get macOS Signing Credentials

### Developer Certificate (`MAC_CERT_BASE64` + password)

1. **Enroll in Apple Developer Program** ($99/year)
   - https://developer.apple.com/programs/

2. **Create Certificate**
   - Open Xcode → Preferences → Accounts
   - Select your Apple ID → Manage Certificates
   - Click "+" → "Developer ID Application"
   - OR use [App Store Connect](https://developer.apple.com/account/resources/certificates/list)

3. **Export as .p12**
   - Open Keychain Access
   - Find "Developer ID Application: Your Name"
   - Right-click → Export
   - Save as .p12 with a password
   - **Remember this password!**

4. **Convert to Base64**
   ```bash
   base64 -i /path/to/certificate.p12 | pbcopy
   # Paste into GitHub secret MAC_CERT_BASE64
   ```

### App Store Connect API Key (for notarization)

1. **Create API Key**
   - Go to [App Store Connect → Users and Access → Keys](https://appstoreconnect.apple.com/access/api)
   - Click "+" to create a key
   - Select "Developer" or "App Manager" role
   - Name it (e.g., "cmux-notarization")
   - Click **Generate**

2. **Download Key** (⚠️ only available once!)
   - Download the `.p8` file (e.g., `AuthKey_ABC123XYZ.p8`)
   - **Note the Key ID** (e.g., `ABC123XYZ`)
   - **Note the Issuer ID** (UUID, shown at top of page)

3. **Convert to Base64**
   ```bash
   base64 -i /path/to/AuthKey_ABC123XYZ.p8 | pbcopy
   # Paste into GitHub secret APPLE_API_KEY
   ```

4. **Set Remaining Secrets**
   - `APPLE_API_KEY_ID`: The key ID from step 2 (e.g., `ABC123XYZ`)
   - `APPLE_API_ISSUER`: The issuer UUID from step 2

## Minimal Setup for Testing (Skip macOS)

If you only want Windows/Linux builds:

1. **Comment out macOS jobs** (lines 213-545)
   ```yaml
   # mac-arm64:
   #   name: macOS arm64
   #   ...

   # mac-universal:
   #   name: macOS universal
   #   ...
   ```

2. **Only set environment secrets** (skip all `MAC_*` and `APPLE_*` secrets)

3. **Keep Windows and Linux jobs** as-is

## Triggering the Workflow

### Automatic Trigger
Push changes to `main` branch that modify:
- `package.json` (root)
- `apps/client/package.json`

### Manual Trigger
1. Go to **Actions** tab in GitHub
2. Select "Build & Publish Electron Updates (GitHub Releases)"
3. Click **Run workflow**
4. Select branch (usually `main`)
5. Click **Run workflow**

## Build Artifacts

All artifacts are uploaded to a GitHub Release with tag matching the version in `apps/client/package.json`.

**Example outputs:**
- `cmux-1.2.3-arm64.dmg` (Apple Silicon)
- `cmux-1.2.3-universal.dmg` (Universal macOS)
- `cmux-1.2.3-setup.exe` (Windows)
- `cmux-1.2.3.AppImage` (Linux)
- `latest-*.yml` (Update manifests for auto-updater)

## Troubleshooting

### Build Fails: "No self-hosted runner available"
- macOS jobs require self-hosted runner
- Either set one up or comment out macOS jobs

### Build Fails: "Notarization failed"
- Check `APPLE_API_KEY`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER` are correct
- Ensure .p8 key has proper permissions in App Store Connect
- Check notarization logs in workflow output

### Build Fails: "Signing failed"
- Verify `MAC_CERT_BASE64` is correctly base64-encoded
- Check `MAC_CERT_PASSWORD` matches your .p12 password
- Ensure certificate is "Developer ID Application" type

### Secrets Not Working
- Double-check secret names match exactly (case-sensitive)
- Ensure secrets are set at repository level, not environment level
- Try re-creating secrets (delete and add again)

### Build Fails: "PEM routines" or "DECODER routines" Error
This indicates the `CMUX_GITHUB_APP_PRIVATE_KEY` is malformed:
```
error:0900006e:PEM routines:OPENSSL_internal:NO_START_LINE
error:1E08010C:DECODER routines::unsupported
```

**Fix for GitHub Secrets:** Re-set the secret using single-line format:
```bash
awk '{printf "%s\\n", $0}' /path/to/your-github-app-private-key.pem | gh secret set CMUX_GITHUB_APP_PRIVATE_KEY --repo karlorz/cmux
```

**Fix for Convex:** Re-run the setup script:
```bash
./scripts/setup-convex-env.sh --prod --env-file .env.production
```

**Why this happens:**
- GitHub Secrets can mangle multi-line values (use single-line format)
- The PEM key needs proper `-----BEGIN RSA PRIVATE KEY-----` header
- Newlines must be preserved for the key to be parsed correctly
- Convex uses JSON API which preserves newlines correctly (multi-line is fine)

## Next Steps After Setup

1. Test with manual workflow dispatch first
2. Verify all secrets are correctly configured
3. Check that GitHub release is created successfully
4. Download and test each platform artifact
5. Enable auto-updates in your Electron app to consume `latest-*.yml` files

## References

- Workflow file: `.github/workflows/release-updates.yml`
- Apple Developer: https://developer.apple.com/
- App Store Connect: https://appstoreconnect.apple.com/
- GitHub Actions Runners: https://docs.github.com/en/actions/hosting-your-own-runners
- electron-builder docs: https://www.electron.build/
