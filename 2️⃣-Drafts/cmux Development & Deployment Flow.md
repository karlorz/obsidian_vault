# cmux Development & Deployment Flow

## Overview

cmux is a web app that spawns coding agent CLIs (Claude Code, Codex, Gemini CLI, Amp, Opencode) in parallel across multiple tasks, with an Electron desktop client and backend services.

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              cmux Monorepo                               │
├─────────────────┬───────────────────┬───────────────────────────────────┤
│     Frontend    │      Backend      │           Infrastructure          │
├─────────────────┼───────────────────┼───────────────────────────────────┤
│ apps/client     │ apps/www (Hono)   │ packages/convex (Database)        │
│ (Electron)      │ apps/server       │ packages/sandbox (Docker)         │
│                 │ apps/worker       │ .devcontainer (Local Docker)      │
└─────────────────┴───────────────────┴───────────────────────────────────┘
```

---

## 2. Local Development

### Start Development
```bash
./scripts/dev.sh                      # Full stack
./scripts/dev.sh --electron           # With Electron client
./scripts/dev.sh --skip-docker        # Skip Docker services
./scripts/dev.sh --show-compose-logs  # Show Docker logs
```

### Services Started
| Service | Port | Log File |
|---------|------|----------|
| Convex (local) | 9777 | `logs/convex-dev.log` |
| Next.js/Hono API | 9779 | `logs/server.log` |
| Vite Client | 5173 | `logs/client.log` |

### Quality Checks
```bash
bun run check    # Typecheck + lint (ALWAYS run before committing)
bun run test     # Run vitest tests
```

---

## 3. Backend Services

### Convex (Database + Serverless Functions)
- **Schema**: `packages/convex/convex/schema.ts`
- **Local**: Self-hosted Docker container at port 9777
- **Production**: Convex Cloud

```bash
# Deploy to production
bun run convex:deploy:prod

# Or manually
CONVEX_DEPLOY_KEY="prod:xxx|ey..." npx convex deploy
```

### Hono API (apps/www)
- OpenAPI routes in `apps/www/lib/routes/*.route.ts`
- Auto-generates client: `@cmux/www-openapi-client`

```bash
cd apps/www && bun run generate-openapi-client
```

---

## 4. Electron Desktop App Build

### Configuration Files
| File | Purpose |
|------|---------|
| `apps/client/electron-builder.json` | electron-builder config |
| `apps/client/electron.vite.config.ts` | Vite build for Electron |
| `apps/client/build/entitlements.mac.plist` | macOS entitlements |

### Build Targets
- **macOS**: arm64, x64, universal (DMG + ZIP)
- **Windows**: x64 (NSIS installer)
- **Linux**: x64 (AppImage)

### Local Build Commands
```bash
# macOS arm64 with signing/notarization
./scripts/build-prod-mac-arm64.sh --env-file .env.codesign

# macOS without notarization (development)
./scripts/build-prod-mac-arm64-no-notarize-or-sign.sh

# Manual build steps
cd apps/client
bunx electron-vite build -c electron.vite.config.ts
bunx electron-builder --config electron-builder.json --mac dmg zip
```

### Output
```
apps/client/dist-electron/
├── cmux-1.0.188-arm64.dmg       # macOS installer
├── cmux-1.0.188-arm64-mac.zip   # macOS ZIP
├── latest-mac.yml               # Auto-update manifest
└── *.blockmap                   # Delta update files
```

---

## 5. CI/CD Release Pipeline

### GitHub Actions Workflows

#### `release-updates.yml` - Main Release Workflow
**Triggers**:
- Push to `main` when `package.json` changes
- Manual `workflow_dispatch`

**Jobs**:
```
prepare-release → mac-arm64 (self-hosted)
                → mac-universal (self-hosted)
                → windows-x64 (windows-latest)
                → linux-x64 (ubuntu-latest)
```

**Build Steps (macOS)**:
1. Checkout + setup Node/Bun/Rust
2. Install dependencies (`bun install --frozen-lockfile`)
3. Write `.env` with production secrets
4. Build native Rust addon (`@napi-rs/cli build`)
5. Build with electron-vite + electron-builder
6. Sign with Apple Developer certificate
7. Notarize with Apple notarytool
8. Staple notarization ticket
9. Upload to GitHub Releases

### Required Secrets
| Secret | Purpose |
|--------|---------|
| `MAC_CERT_BASE64` | Apple Developer certificate (P12, base64) |
| `MAC_CERT_PASSWORD` | Certificate password |
| `APPLE_API_KEY` | App Store Connect API key (P8) |
| `APPLE_API_KEY_ID` | API key ID |
| `APPLE_API_ISSUER` | API issuer ID |
| `NEXT_PUBLIC_CONVEX_URL` | Production Convex URL |
| `NEXT_PUBLIC_STACK_*` | Stack Auth credentials |

---

## 6. Auto-Update Flow

The Electron app uses `electron-updater` to check for updates:

```yaml
# latest-mac.yml (uploaded to GitHub Releases)
version: 1.0.188
path: cmux-1.0.188-arm64.dmg
sha512: Dj51I0q8...
```

When users launch the app:
1. App checks GitHub Releases for `latest-*.yml`
2. Compares version with current
3. Downloads delta updates (blockmap) or full installer
4. Installs on restart

---

## 7. Docker & Sandbox Environment

### Main Dockerfile Structure
```
Stage 1: rust-builder     → Compile Rust binaries
Stage 2: builder-base     → Node, Go, Python, Bun, openvscode
Stage 3: dind-installer   → Docker-in-Docker
Stage 4: runtime-base     → Base runtime
Stage 5: runtime-local    → With Docker (local dev)
Stage 6: morph            → Sandboxed runtime (production)
```

### Sandbox Ports
| Port | Service |
|------|---------|
| 39375 | Exec service (HTTP) |
| 39376 | VS Code Extension Socket Server |
| 39377 | Worker service |
| 39378 | OpenVSCode server |
| 39379 | cmux-proxy |
| 39380 | VNC websocket proxy (noVNC) |
| 39381 | Chrome DevTools (CDP) |
| 39382 | Chrome DevTools target |
| 39383 | cmux-xterm server |

### Rebuild Sandbox Snapshot
```bash
uv run --env-file .env.production ./scripts/snapshot.py \
  --snapshot-id snapshot_p47jfz9s \
  --standard-vcpus 2 \
  --standard-memory 4096 \
  --boosted-vcpus 4 \
  --boosted-memory 8192
```

---

## 8. Complete Release Checklist

- [ ] Code changes merged to main
- [ ] `bun run check` passes
- [ ] Version bumped in `apps/client/package.json`
- [ ] Push triggers `release-updates.yml`
- [ ] CI builds for all platforms
- [ ] macOS: signed + notarized
- [ ] Artifacts uploaded to GitHub Releases
- [ ] Users receive auto-updates

---

## 9. Environment Variables Summary

### Development (`.env`)
```bash
CONVEX_PORT=9777
NEXT_PUBLIC_CONVEX_URL=http://localhost:9777
```

### Production (`.env.production`)
```bash
NEXT_PUBLIC_CONVEX_URL=https://xxx.convex.cloud
NEXT_PUBLIC_STACK_PROJECT_ID=...
NEXT_PUBLIC_WWW_ORIGIN=https://cmux.dev
NEXT_PUBLIC_GITHUB_APP_SLUG=cmux-app
```

### Code Signing (`.env.codesign`)
```bash
MAC_CERT_BASE64=...
MAC_CERT_PASSWORD=...
APPLE_API_KEY=...
APPLE_API_KEY_ID=...
APPLE_API_ISSUER=...
```

---

## 10. Key Technologies

| Category | Technology |
|----------|------------|
| Package Manager | Bun |
| Frontend | React, TanStack Router/Query, Vite |
| Desktop | Electron, electron-vite, electron-builder |
| Backend API | Hono (OpenAPI) |
| Database | Convex |
| Auth | Stack Auth |
| Native Addons | Rust (N-API via @napi-rs/cli) |
| CI/CD | GitHub Actions |
| Containerization | Docker, Docker-in-Docker |
| Sandbox | MorphCloud (production), Docker Compose (local) |
