# cmux Electron Build Guide (macOS)

Complete guide for building the cmux Electron app locally, covering both unsigned (development) and signed (production/distribution) builds.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Development Mode](#development-mode)
3. [Unsigned Local Build (Quick Start)](#unsigned-local-build-quick-start)
4. [Signed Production Build (For Distribution)](#signed-production-build-for-distribution)
   - [Step 1: Join Apple Developer Program](#step-1-join-apple-developer-program)
   - [Step 2: Create Developer ID Certificate](#step-2-create-developer-id-certificate)
   - [Step 3: Export Certificate as .p12](#step-3-export-certificate-as-p12)
   - [Step 4: Create App Store Connect API Key](#step-4-create-app-store-connect-api-key)
   - [Step 5: Configure Environment Variables](#step-5-configure-environment-variables)
   - [Step 6: Run Signed Build](#step-6-run-signed-build)
5. [Build Types: arm64 vs Universal](#build-types-arm64-vs-universal)
6. [Configuration Files](#configuration-files)
7. [Troubleshooting](#troubleshooting)
8. [Quick Reference](#quick-reference)

---

## Prerequisites

Before building, ensure you have:

```bash
# Check installations
bun --version      # Required: bun v1.3+
node --version     # Required: Node.js 24+
rustc --version    # Required: Rust toolchain
xcrun --version    # Required: Xcode Command Line Tools
```

Install missing tools:

```bash
# Bun
curl -fsSL https://bun.sh/install | bash

# Xcode Command Line Tools
xcode-select --install

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

---

## Development Mode

Start Electron with hot reload:

```bash
./scripts/dev-electron.sh
```

This will:
1. Rebuild native Electron modules
2. Start electron-vite dev server at `http://localhost:5173`
3. Open the Electron app window

### Alternative (from apps/client):

```bash
cd apps/client
bun run predev:electron   # rebuild native modules
bun run dev:electron      # start dev mode
```

---

## Unsigned Local Build (Quick Start)

For development/testing without code signing. The app will show security warnings but works locally.

### Step 1: Install Dependencies

```bash
cd /path/to/cmux
bun install --frozen-lockfile
```

### Step 2: Ensure .env File Exists

```bash
# Copy from your production env or create minimal version
cat > .env << 'EOF'
NEXT_PUBLIC_CONVEX_URL=https://your-convex-url.convex.cloud
NEXT_PUBLIC_STACK_PROJECT_ID=your-stack-project-id
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=your-stack-key
NEXT_PUBLIC_WWW_ORIGIN=https://your-www-origin.com
NEXT_PUBLIC_GITHUB_APP_SLUG=your-github-app-slug
EOF
```

### Step 3: Build Using Local Script

```bash
./scripts/build-electron-local.sh
```

Or manually:

```bash
# Build native Rust addon
cd apps/server/native/core
bunx --bun @napi-rs/cli build --platform --release
cd ../../../..

# Generate icons
cd apps/client
bun run ./scripts/generate-icons.mjs

# Build the Electron app
bunx electron-vite build -c electron.vite.config.ts

# Package without signing (uses electron-builder.local.json)
bunx electron-builder --config electron-builder.local.json --mac
```

### Output Location

Built files are in `apps/client/dist-electron/`:
- `cmux-<version>-arm64.dmg` - Disk image
- `mac-arm64/cmux.app` - Application bundle

### Running Unsigned App

macOS will block unsigned apps. To run:

```bash
# Option 1: Remove quarantine attribute
xattr -cr apps/client/dist-electron/mac-arm64/cmux.app
open apps/client/dist-electron/mac-arm64/cmux.app

# Option 2: Right-click > Open in Finder (allows bypass)
```

---

## Signed Production Build (For Distribution)

Required for distributing the app to others without security warnings. This process involves:
1. **Code Signing** - Proves the app comes from you
2. **Notarization** - Apple scans for malware and approves distribution

### Step 1: Join Apple Developer Program

You need an Apple Developer account ($99/year):

1. Go to https://developer.apple.com/programs/
2. Click **"Enroll"**
3. Sign in with your Apple ID (or create one)
4. Choose enrollment type:
   - **Individual**: For personal use (requires government ID verification)
   - **Organization**: For companies (requires D-U-N-S number)
5. Complete payment ($99 USD/year)
6. Wait for approval (usually 24-48 hours, sometimes faster)

> **Note**: Without this, you cannot create signing certificates or notarize apps.

### Step 2: Create Developer ID Certificate

A **Developer ID Application** certificate is required for distributing apps outside the Mac App Store.

#### Method A: Using Xcode (Recommended)

1. Open **Xcode** > **Settings** (or Preferences) > **Accounts**
2. Click **"+"** and add your Apple ID if not already added
3. Select your **team** (your name or organization)
4. Click **"Manage Certificates..."**
5. Click **"+"** in bottom-left > **"Developer ID Application"**
6. Xcode creates and installs the certificate automatically

#### Method B: Using Apple Developer Portal

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click **"+"** button to create new certificate
3. Select **"Developer ID Application"** under "Software"
4. Click **Continue**
5. You need a **Certificate Signing Request (CSR)**:

   **Creating a CSR:**
   1. Open **Keychain Access** (Applications > Utilities)
   2. Menu: **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority...**
   3. Enter your email address
   4. Leave "CA Email Address" blank
   5. Select **"Saved to disk"**
   6. Click **Continue** and save the `.certSigningRequest` file

6. Upload the CSR file to Apple Developer Portal
7. Click **Continue** and then **Download**
8. Double-click the downloaded `.cer` file to install it in Keychain

#### Verify Certificate Installation

```bash
security find-identity -v -p codesigning
```

You should see something like:
```
1) ABCD1234... "Developer ID Application: Your Name (TEAM_ID)"
    1 valid identities found
```

### Step 3: Export Certificate as .p12

The build scripts need your certificate in `.p12` format (portable, includes private key).

1. Open **Keychain Access** (Applications > Utilities)
2. In the left sidebar, select **"login"** keychain
3. Click **"My Certificates"** category (not "Certificates")
4. Find your certificate: **"Developer ID Application: Your Name (TEAM_ID)"**
   - It should have a disclosure triangle showing a private key underneath
5. **Right-click** the certificate > **"Export..."**
6. Choose format: **Personal Information Exchange (.p12)**
7. Save as: `developer_id_certificate.p12`
8. **Set a strong password** - you'll need this for `MAC_CERT_PASSWORD`
9. Enter your macOS password when prompted to allow export

> **Important**: The certificate MUST include the private key. If you don't see "My Certificates" or there's no key icon, the private key is missing.

### Step 4: Create App Store Connect API Key

Required for **notarization** (Apple's automated malware scanning service).

1. Go to https://appstoreconnect.apple.com
2. Sign in with your Apple ID
3. Click **"Users and Access"** in the top menu
4. Click **"Keys"** tab (under "Integrations" section)
5. Click **"+"** to generate a new key
6. Fill in:
   - **Name**: `cmux Notarization` (or any descriptive name)
   - **Access**: Select **"Developer"** role
7. Click **"Generate"**

**CRITICAL - Save These Immediately:**

| Item | Where to Find | Example |
|------|---------------|---------|
| **Key ID** | Shown in the table after creation | `ABC1234567` (10 characters) |
| **Issuer ID** | Shown at top of Keys page | `12345678-1234-1234-1234-123456789012` (UUID) |
| **.p8 File** | Click "Download" - **ONLY AVAILABLE ONCE!** | `AuthKey_ABC1234567.p8` |

> **Warning**: The `.p8` file can only be downloaded once. If you lose it, you must create a new key.

Store the `.p8` file securely:
```bash
mkdir -p ~/.apple-keys
mv ~/Downloads/AuthKey_ABC1234567.p8 ~/.apple-keys/
chmod 600 ~/.apple-keys/AuthKey_ABC1234567.p8
```

### Step 5: Configure Environment Variables

Create `.env.codesign` in the cmux project root:

```bash
cd /path/to/cmux

# Base64 encode your certificate (single line, no newlines)
MAC_CERT_BASE64=$(base64 -i /path/to/developer_id_certificate.p12 | tr -d '\n')

# Create the codesign env file
cat > .env.codesign << EOF
# ===== macOS Code Signing Certificate =====
MAC_CERT_BASE64=${MAC_CERT_BASE64}
MAC_CERT_PASSWORD=your-p12-password-here

# ===== Apple Notarization API Key =====
# Option 1: File path (recommended)
APPLE_API_KEY=/Users/$(whoami)/.apple-keys/AuthKey_ABC1234567.p8
# Option 2: Inline content (escape newlines as \n)
# APPLE_API_KEY=-----BEGIN PRIVATE KEY-----\nMIGT...your-key...\n-----END PRIVATE KEY-----

APPLE_API_KEY_ID=ABC1234567
APPLE_API_ISSUER=12345678-1234-1234-1234-123456789012

# ===== App Configuration =====
# Copy these from your .env or .env.production
NEXT_PUBLIC_CONVEX_URL=https://your-convex-url.convex.cloud
NEXT_PUBLIC_STACK_PROJECT_ID=your-stack-project-id
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=your-stack-key
NEXT_PUBLIC_WWW_ORIGIN=https://your-www-origin.com
NEXT_PUBLIC_GITHUB_APP_SLUG=your-github-app-slug
EOF

# Secure the file (contains sensitive credentials)
chmod 600 .env.codesign
```

### Step 6: Run Signed Build

**For ARM64 (Apple Silicon) build:**

```bash
bash scripts/publish-build-mac-arm64.sh --env-file .env.codesign
```

This script will:
1. Load credentials from `.env.codesign`
2. Generate app icons
3. Prepare macOS entitlements
4. Build the Electron app with electron-vite
5. **Code sign** using your Developer ID certificate
6. **Notarize** with Apple (uploads to Apple's servers for scanning)
7. **Staple** the notarization ticket to the app
8. **Verify** with Gatekeeper

**Output**: `apps/client/dist-electron/cmux-<version>-arm64.dmg`

---

## Build Types: arm64 vs Universal

The GitHub Actions workflow (`.github/workflows/release-updates.yml`) has multiple build jobs:

| Aspect | `mac-arm64` Job | `mac-universal` Job |
|--------|-----------------|---------------------|
| **Target Architecture** | Apple Silicon only (M1/M2/M3) | Intel + Apple Silicon |
| **Rust Targets** | `aarch64-apple-darwin` | Both `aarch64-apple-darwin` AND `x86_64-apple-darwin` |
| **Native Addon** | Single build | Builds both, merges into universal |
| **Electron Builder Flag** | `--mac dmg zip --arm64` | `--mac dmg zip --universal` |
| **Requires Rosetta** | No | Yes (for x64 toolchain on ARM host) |
| **Output File** | `cmux-<version>-arm64.dmg` | `cmux-<version>-universal.dmg` |
| **File Size** | Smaller (~single arch) | ~2x larger (both archs) |
| **Compatibility** | Apple Silicon Macs only | All modern Macs |

### Building Universal Locally

```bash
# Add both Rust targets
rustup target add x86_64-apple-darwin aarch64-apple-darwin

# Install Rosetta (if on Apple Silicon)
/usr/sbin/softwareupdate --install-rosetta --agree-to-license

# Build native addons for both architectures
cd apps/server/native/core
bunx --bun @napi-rs/cli build --platform --release --target x86_64-apple-darwin
bunx --bun @napi-rs/cli build --platform --release --target aarch64-apple-darwin

# Rename x86_64 binary to match electron-builder expectations
mv cmux_native_core.darwin-x86_64.node cmux_native_core.darwin-x64.node
cd ../../../..

# Build and package
cd apps/client
bunx electron-vite build -c electron.vite.config.ts
bunx electron-builder \
  --config electron-builder.json \
  --mac dmg zip \
  --universal \
  --publish never \
  --config.mac.forceCodeSigning=true
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `apps/client/electron-builder.json` | Main electron-builder config (production) |
| `apps/client/electron-builder.local.json` | Local dev overrides (no code signing) |
| `apps/client/electron.vite.config.ts` | electron-vite build config |
| `apps/client/build/entitlements.mac.plist` | macOS security entitlements |
| `apps/client/electron/app-update.yml` | Auto-update settings |
| `scripts/publish-build-mac-arm64.sh` | ARM64 signed build script |
| `.github/workflows/release-updates.yml` | CI/CD build workflow |

### Key Scripts

| Script | Description |
|--------|-------------|
| `./scripts/dev-electron.sh` | Dev mode with hot reload |
| `./scripts/build-electron-local.sh` | Local unsigned build |
| `scripts/publish-build-mac-arm64.sh` | Signed ARM64 production build |

### apps/client Scripts

| Command | Description |
|---------|-------------|
| `bun run dev:electron` | Start dev mode |
| `bun run build:electron` | Full build with electron-builder |
| `bun run build:mac` | macOS-specific build |
| `bun run rebuild:electron` | Rebuild native modules |

---

## Troubleshooting

### "No identity found for signing"

Your certificate isn't installed or isn't a Developer ID certificate.

```bash
# List all codesigning identities
security find-identity -v -p codesigning

# Should show:
# 1) ABC123... "Developer ID Application: Your Name (TEAM_ID)"
```

**Solutions:**
- Reinstall the certificate from Keychain Access
- Ensure you exported with the private key (from "My Certificates")
- Check the certificate hasn't expired

### "Notarization failed" / "Invalid" status

Common causes:

1. **Wrong API key permissions** - Ensure the key has "Developer" role
2. **Invalid credentials** - Double-check `APPLE_API_KEY_ID` and `APPLE_API_ISSUER`
3. **Hardened runtime issues** - The app doesn't have required entitlements

Get detailed notarization log:
```bash
xcrun notarytool log <submission-id> \
  --key ~/.apple-keys/AuthKey_XXX.p8 \
  --key-id YOUR_KEY_ID \
  --issuer YOUR_ISSUER_ID
```

Check Apple's notarization status: https://developer.apple.com/system-status/

### "The application is damaged and can't be opened"

The app wasn't properly signed or the signature was invalidated.

```bash
# Remove quarantine attribute
xattr -cr /path/to/cmux.app

# Verify signature
codesign -vvv --deep --strict /path/to/cmux.app
```

### "Developer cannot be verified"

The app is signed but not notarized, or notarization ticket isn't stapled.

```bash
# Check if notarization ticket is stapled
xcrun stapler validate /path/to/cmux.app

# Re-staple if needed
xcrun stapler staple /path/to/cmux.app
```

### Certificate Expired

Developer ID certificates expire after 5 years. Create a new one following Step 2-3.

### Native Module / Rust Addon Issues

```bash
# Clean and rebuild
cd apps/server/native/core
cargo clean
rm -f *.node
bunx --bun @napi-rs/cli build --platform --release
```

### tsconfig Warnings from dev-docs/

These warnings are benign - the `dev-docs/` folder contains external reference code that isn't part of the actual cmux build.

---

## Quick Reference

| Task | Command |
|------|---------|
| Dev mode | `./scripts/dev-electron.sh` |
| Unsigned local build | `./scripts/build-electron-local.sh` |
| Signed ARM64 build | `bash scripts/publish-build-mac-arm64.sh --env-file .env.codesign` |
| List signing identities | `security find-identity -v -p codesigning` |
| Verify signature | `codesign -vvv --deep --strict /path/to/app.app` |
| Verify notarization | `spctl -a -t exec -vv /path/to/app.app` |
| Remove quarantine | `xattr -cr /path/to/app.app` |
| Notarization history | `xcrun notarytool history --key ... --key-id ... --issuer ...` |
| Rebuild native addon | `cd apps/server/native/core && bunx --bun @napi-rs/cli build --platform --release` |

---

## App Details

- **App ID**: `com.cmux.app`
- **URL Scheme**: `cmux://`
- **Electron Version**: 37.2.4 (build script) / 38.0.0 (package.json)
- **Auto-update**: GitHub releases via electron-updater
