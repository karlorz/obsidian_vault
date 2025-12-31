# cmux Deployment Guide

> Complete environment variable reference for all deployment targets.
> Last updated: 2025-12-31

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       CMUX DEPLOYMENT ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    │
│  │  Stack Auth     │    │  Convex Cloud    │    │  GitHub App         │    │
│  │  (Auth SaaS)    │    │  (Database/BaaS) │    │  (OAuth + Webhooks) │    │
│  └────────┬────────┘    └────────┬─────────┘    └──────────┬──────────┘    │
│           │                      │                         │               │
│           └──────────────┬───────┴─────────────────────────┘               │
│                          │                                                  │
│  ┌───────────────────────▼───────────────────────────────────────────────┐ │
│  │                     apps/www (Vercel)                                  │ │
│  │                     Backend API (Hono + Next.js)                       │ │
│  │  - OpenAPI routes for sandbox management                               │ │
│  │  - GitHub App webhook handler                                          │ │
│  │  - AI features (Anthropic/OpenAI)                                      │ │
│  └───────────────────────┬───────────────────────────────────────────────┘ │
│                          │                                                  │
│  ┌───────────────────────▼───────────────────────────────────────────────┐ │
│  │                     apps/client (Vercel)                               │ │
│  │                     Frontend SPA (Vite + React + TanStack Router)      │ │
│  │  - Task dashboard                                                      │ │
│  │  - VS Code workspace embeds                                            │ │
│  │  - Diff viewer                                                         │ │
│  └───────────────────────┬───────────────────────────────────────────────┘ │
│                          │                                                  │
│  ┌───────────────────────▼───────────────────────────────────────────────┐ │
│  │                SANDBOX PROVIDER (choose one)                           │ │
│  │                                                                        │ │
│  │  Option A: Morph Cloud          Option B: PVE LXC (Self-Hosted)       │ │
│  │  ┌─────────────────────┐        ┌─────────────────────────────┐       │ │
│  │  │ Cloud VMs           │        │ Proxmox VE Host             │       │ │
│  │  │ Instant snapshots   │        │ LXC Containers              │       │ │
│  │  │ MORPH_API_KEY       │        │ Cloudflare Tunnel           │       │ │
│  │  └─────────────────────┘        │ PVE_API_URL + PVE_API_TOKEN │       │ │
│  │                                  └─────────────────────────────┘       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start: Which Platform Needs What?

| Platform | Purpose | Key Variables |
|----------|---------|---------------|
| **Stack Auth** | Authentication | Project ID, Client Key, Server Key |
| **Convex Cloud** | Database + Functions | Deploy Key, Webhook Secret |
| **Vercel (www)** | Backend API | Stack keys, GitHub App, AI keys, Sandbox provider |
| **Vercel (client)** | Frontend | Convex URL, Stack client keys, WWW origin |
| **Sandbox Host** | Agent execution | Morph OR PVE credentials |

---

## 1. Stack Auth Configuration

**Dashboard:** https://app.stack-auth.com/projects

Create a project and obtain these credentials:

| Variable | Where to Find | Used By |
|----------|---------------|---------|
| `NEXT_PUBLIC_STACK_PROJECT_ID` | Project Settings > Project ID | Client, WWW, Convex |
| `NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY` | Project Settings > API Keys | Client, WWW, Convex |
| `STACK_SECRET_SERVER_KEY` | Project Settings > API Keys | WWW, Convex |
| `STACK_SUPER_SECRET_ADMIN_KEY` | Project Settings > API Keys | WWW (admin ops) |
| `STACK_WEBHOOK_SECRET` | Project Settings > Webhooks | Convex |

### Webhook Configuration

In Stack Auth dashboard, add webhook:
- **URL:** `https://your-convex-deployment.convex.site/stack-webhook`
- **Events:** User created, User updated, Team events

---

## 2. Convex Configuration

**Dashboard:** https://dashboard.convex.dev

### Deploy Key Setup

1. Go to Project Settings
2. Click "Generate Production Deploy Key"
3. Copy the key

| Variable | Where to Use | Description |
|----------|--------------|-------------|
| `CONVEX_DEPLOY_KEY` | CI/CD, Local deploy | Deploy functions to production |
| `NEXT_PUBLIC_CONVEX_URL` | Client, WWW | Database connection URL |
| `CONVEX_SITE_URL` | WWW (optional) | HTTP actions URL (auto-derived if not set) |

### Convex Environment Variables

Set these in Convex Dashboard > Settings > Environment Variables:

```
# Required
STACK_WEBHOOK_SECRET=whsec_...
BASE_APP_URL=https://your-www-domain.com
CMUX_TASK_RUN_JWT_SECRET=your-jwt-secret

# Stack Auth
NEXT_PUBLIC_STACK_PROJECT_ID=...
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=pck_...
STACK_SECRET_SERVER_KEY=ssk_...
STACK_SUPER_SECRET_ADMIN_KEY=sk_...

# GitHub App
CMUX_GITHUB_APP_ID=1234567
CMUX_GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."
GITHUB_APP_WEBHOOK_SECRET=...
INSTALL_STATE_SECRET=...

# AI
ANTHROPIC_API_KEY=sk-ant-...

# Sandbox (one of these)
MORPH_API_KEY=morph_...
# OR for PVE: No Convex config needed

# Flags
CMUX_IS_STAGING=false
```

---

## 3. Vercel: apps/www (Backend)

**Project:** Link to `apps/www` directory

### Required Variables

```bash
# Stack Auth (Server-side)
STACK_SECRET_SERVER_KEY=ssk_...
STACK_SUPER_SECRET_ADMIN_KEY=sk_...
STACK_DATA_VAULT_SECRET=your-32-char-min-secret

# Stack Auth (Client-side, also needed here)
NEXT_PUBLIC_STACK_PROJECT_ID=...
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=pck_...

# Convex
NEXT_PUBLIC_CONVEX_URL=https://your-project.convex.cloud

# GitHub App
CMUX_GITHUB_APP_ID=1234567
CMUX_GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."

# AI (Required)
ANTHROPIC_API_KEY=sk-ant-...

# JWT
CMUX_TASK_RUN_JWT_SECRET=...
```

### Sandbox Provider (Choose One)

**Option A: Morph Cloud**
```bash
MORPH_API_KEY=morph_...
```

**Option B: PVE LXC**
```bash
PVE_API_URL=https://pve.example.com
PVE_API_TOKEN=root@pam!mytoken=secret-uuid
PVE_PUBLIC_DOMAIN=example.com
# Optional: PVE_NODE (auto-detected)
```

**Optional: Force Provider**
```bash
SANDBOX_PROVIDER=morph   # or pve-lxc
```

### Optional Variables

```bash
OPENAI_API_KEY=sk-...           # For PR review features
GEMINI_API_KEY=...              # For Gemini model support
CONVEX_SITE_URL=...             # Self-hosted Convex only
NEXT_PUBLIC_GITHUB_APP_SLUG=... # OAuth redirect
GITHUB_TOKEN=...                # Rate-limited GitHub API calls
```

---

## 4. Vercel: apps/client (Frontend)

**Project:** Link to `apps/client` directory

### Required Variables

```bash
# Convex
NEXT_PUBLIC_CONVEX_URL=https://your-project.convex.cloud

# Stack Auth (Client-side only)
NEXT_PUBLIC_STACK_PROJECT_ID=...
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=pck_...

# Backend URL
NEXT_PUBLIC_WWW_ORIGIN=https://your-www-domain.com
```

### Optional Variables

```bash
NEXT_PUBLIC_GITHUB_APP_SLUG=...  # OAuth redirects
NEXT_PUBLIC_POSTHOG_KEY=...      # Analytics
NEXT_PUBLIC_POSTHOG_HOST=...
NEXT_PUBLIC_WEB_MODE=false       # true = web-only restrictions
SENTRY_AUTH_TOKEN=...            # Error tracking (build-time)
```

---

## 5. GitHub App Configuration

**Create at:** https://github.com/settings/apps/new

### Required Settings

| Setting | Value |
|---------|-------|
| **Callback URL** | `https://your-www-domain.com/api/github/callback` |
| **Webhook URL** | `https://your-convex.convex.site/github-webhook` |
| **Webhook Secret** | Generate and save as `GITHUB_APP_WEBHOOK_SECRET` |

### Required Permissions

**Repository:**
- Contents: Read & Write
- Pull requests: Read & Write
- Metadata: Read

**Account:**
- Email addresses: Read

### Generate Private Key

1. Scroll to "Private keys" section
2. Click "Generate a private key"
3. Save as `CMUX_GITHUB_APP_PRIVATE_KEY`

### Environment Variables from GitHub App

```bash
CMUX_GITHUB_APP_ID=1234567              # App ID from app settings
CMUX_GITHUB_APP_PRIVATE_KEY="..."       # Downloaded .pem file contents
GITHUB_APP_WEBHOOK_SECRET=...           # Webhook secret you created
INSTALL_STATE_SECRET=...                # Random string for OAuth state
NEXT_PUBLIC_GITHUB_APP_SLUG=your-app    # URL slug of your app
```

---

## 6. Sandbox Provider: Morph Cloud

**Dashboard:** https://cloud.morph.so

### Setup

1. Create account and project
2. Generate API key
3. Build snapshots (automated via GitHub Action)

### Environment Variables

```bash
MORPH_API_KEY=morph_...
```

### Snapshot Build (GitHub Action)

```bash
gh workflow run "Daily Morph Snapshot" --repo your/cmux-fork --ref main
```

---

## 7. Sandbox Provider: PVE LXC (Self-Hosted)

### Prerequisites

- Proxmox VE 8.x host
- Domain with Cloudflare DNS
- Cloudflare API token

### PVE API Token

1. In PVE: Datacenter > Permissions > API Tokens
2. Create token for user (e.g., `root@pam`)
3. Note: Token ID + Secret = `user@realm!tokenid=secret`

### Backend Environment Variables

```bash
PVE_API_URL=https://pve.example.com
PVE_API_TOKEN=root@pam!cmux=12345678-1234-1234-1234-1234567890ab
PVE_PUBLIC_DOMAIN=example.com

# Optional (auto-detected)
PVE_NODE=pve1
PVE_STORAGE=local-lvm
PVE_BRIDGE=vmbr0
```

### Cloudflare Tunnel Setup (on PVE host)

```bash
# Set environment
export CF_API_TOKEN="your-cloudflare-api-token"
export CF_ZONE_ID="your-zone-id"
export CF_ACCOUNT_ID="your-account-id"
export CF_DOMAIN="example.com"

# Run setup
curl -fsSL https://raw.githubusercontent.com/karlorz/cmux/main/scripts/pve/pve-tunnel-setup.sh | bash -s -- setup
```

### Build Template & Snapshots

```bash
# On PVE host: Create base template
curl -fsSL https://raw.githubusercontent.com/karlorz/cmux/main/scripts/pve/pve-lxc-setup.sh | bash -s -- 9000

# On dev machine: Build snapshots
uv run --env-file .env ./scripts/snapshot-pvelxc.py --template-vmid 9000
```

---

## 8. Local Development

### Minimal .env

```bash
# Convex
CONVEX_DEPLOY_KEY="prod:your-deploy-key"
NEXT_PUBLIC_CONVEX_URL=https://your-project.convex.cloud

# Stack Auth
NEXT_PUBLIC_STACK_PROJECT_ID=...
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=pck_...
STACK_SECRET_SERVER_KEY=ssk_...
STACK_SUPER_SECRET_ADMIN_KEY=sk_...
STACK_DATA_VAULT_SECRET=your-32-char-secret-minimum
STACK_WEBHOOK_SECRET=whsec_...

# GitHub App
CMUX_GITHUB_APP_ID=1234567
CMUX_GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."
GITHUB_APP_WEBHOOK_SECRET=...
INSTALL_STATE_SECRET=...

# AI
ANTHROPIC_API_KEY=sk-ant-...

# JWT
CMUX_TASK_RUN_JWT_SECRET=...
BASE_APP_URL=http://localhost:9779

# Sandbox (choose one)
MORPH_API_KEY=morph_...
# OR:
# PVE_API_URL=https://pve.example.com
# PVE_API_TOKEN=root@pam!token=secret
# PVE_PUBLIC_DOMAIN=example.com
```

### Start Development

```bash
make dev
# or
./scripts/dev.sh
```

---

## Production Checklist

### Stack Auth
- [ ] Project created
- [ ] Webhook configured pointing to Convex
- [ ] All 5 keys copied

### Convex
- [ ] Production deploy key generated
- [ ] All environment variables set in dashboard
- [ ] `bun run convex:deploy` successful

### Vercel apps/www
- [ ] All required variables set
- [ ] Sandbox provider configured (Morph or PVE)
- [ ] Deployment successful

### Vercel apps/client
- [ ] `NEXT_PUBLIC_WWW_ORIGIN` points to www deployment
- [ ] `NEXT_PUBLIC_CONVEX_URL` set
- [ ] Stack Auth client keys set

### GitHub App
- [ ] App created with correct permissions
- [ ] Webhook URL points to Convex
- [ ] Private key saved
- [ ] App installed on target repositories

### Sandbox Provider

**If Morph:**
- [ ] API key set
- [ ] Snapshots built via GitHub Action

**If PVE LXC:**
- [ ] PVE API token created
- [ ] Cloudflare Tunnel deployed on PVE host
- [ ] Template created and snapshots built
- [ ] DNS wildcard configured

---

## Troubleshooting

### "No sandbox provider configured"
- Check `MORPH_API_KEY` or `PVE_API_URL`+`PVE_API_TOKEN` is set in apps/www

### Stack Auth 401 errors
- Verify `STACK_SECRET_SERVER_KEY` matches dashboard
- Check project ID is correct

### Convex connection errors
- Verify `NEXT_PUBLIC_CONVEX_URL` format
- Check Convex deployment status

### GitHub webhook not triggering
- Verify webhook URL in GitHub App settings
- Check `GITHUB_APP_WEBHOOK_SECRET` matches

### PVE containers not accessible
- Verify Cloudflare Tunnel is running: `systemctl status cloudflared`
- Check DNS propagation for wildcard domain

---

## Links

- **cmux Repo:** https://github.com/manaflow-ai/cmux
- **Stack Auth:** https://app.stack-auth.com
- **Convex:** https://dashboard.convex.dev
- **Vercel:** https://vercel.com/dashboard
- **Cloudflare:** https://dash.cloudflare.com
- **PVE API Docs:** https://pve.proxmox.com/pve-docs/api-viewer/

---

## Appendix A: Electron Desktop Build & Release

### Build Commands

```bash
# macOS arm64 with signing/notarization
./scripts/build-prod-mac-arm64.sh --env-file .env.codesign

# macOS without notarization (development)
./scripts/build-prod-mac-arm64-no-notarize-or-sign.sh

# Manual build
cd apps/client
bunx electron-vite build -c electron.vite.config.ts
bunx electron-builder --config electron-builder.json --mac dmg zip
```

### Build Output

```
apps/client/dist-electron/
├── cmux-1.0.188-arm64.dmg       # macOS installer
├── cmux-1.0.188-arm64-mac.zip   # macOS ZIP
├── latest-mac.yml               # Auto-update manifest
└── *.blockmap                   # Delta update files
```

### CI/CD Secrets (GitHub Actions)

| Secret | Purpose |
|--------|---------|
| `MAC_CERT_BASE64` | Apple Developer certificate (P12, base64) |
| `MAC_CERT_PASSWORD` | Certificate password |
| `APPLE_API_KEY` | App Store Connect API key (P8) |
| `APPLE_API_KEY_ID` | API key ID |
| `APPLE_API_ISSUER` | API issuer ID |

### Auto-Update Flow

The Electron app uses `electron-updater`:
1. App checks GitHub Releases for `latest-*.yml`
2. Compares version with current
3. Downloads delta updates (blockmap) or full installer
4. Installs on restart

---

## Appendix B: Sandbox Ports Reference

| Port | Service |
|------|---------|
| 39375 | Exec service (cmux-execd) |
| 39376 | VS Code Extension Socket Server |
| 39377 | Worker service |
| 39378 | OpenVSCode server |
| 39379 | cmux-proxy |
| 39380 | VNC websocket proxy (noVNC) |
| 39381 | Chrome DevTools (CDP) |
| 39382 | Chrome DevTools target |
| 39383 | cmux-xterm server |

---

## Appendix C: Authentication Architecture

cmux uses GitHub in two separate ways:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     GitHub Integration in cmux                       │
├─────────────────────────────────┬───────────────────────────────────┤
│       User Authentication       │       Repository Access            │
├─────────────────────────────────┼───────────────────────────────────┤
│ Stack Auth → GitHub App/OAuth   │ GitHub App Installation            │
│                                 │                                     │
│ Purpose: Login users            │ Purpose: Access repos, create PRs   │
│ Config: Stack Auth dashboard    │ Config: CMUX_GITHUB_APP_ID etc.     │
└─────────────────────────────────┴───────────────────────────────────┘
```

### Auth Flow

```
User clicks "Sign in with GitHub"
        │
        ▼
   Stack Auth
        │
        ▼
GitHub App Authorization
        │
        ▼
User authorized → Stack Auth creates/updates user
        │
        ▼
User can access cmux dashboard
```

---

## Appendix D: Local Development Services

### Dev Script Options

```bash
./scripts/dev.sh                      # Full stack
./scripts/dev.sh --electron           # With Electron client
./scripts/dev.sh --skip-docker        # Skip Docker services
./scripts/dev.sh --show-compose-logs  # Show Docker logs
```

### Local Services

| Service | Port | Log File |
|---------|------|----------|
| Convex (local) | 9777 | `logs/convex-dev.log` |
| Next.js/Hono API | 9779 | `logs/server.log` |
| Vite Client | 5173 | `logs/client.log` |

### Quality Checks

```bash
bun run check    # Typecheck + lint (run before committing)
bun run test     # Run vitest tests
```
