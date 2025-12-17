# cmux Electron Build Guide (macOS)

## Prerequisites

- **bun** (v1.3+)
- **Rust** (for native addon)
- **Node.js** (v24+)
- Environment file: `.env` or `.env.production` at project root

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

## Production Build

Build a packaged `.app` for macOS:

```bash
./scripts/build-electron-local.sh
```

### Output Location

```
apps/client/dist-electron/mac-arm64/cmux.app   # ARM64 (Apple Silicon)
apps/client/dist-electron/mac-x64/cmux.app     # Intel x64
```

### Build Process

1. Rebuilds native Electron modules
2. Builds native Rust addon (`cmux_native_core.darwin-*.node`)
3. Generates app icons (`.icns`, `.ico`, `.png`)
4. Builds Electron bundles (main/preload/renderer) via electron-vite
5. Downloads Electron binary (v37.2.4)
6. Creates `.app` bundle with resources
7. Opens the app automatically

### Environment Variables

The build uses `.env.production` if present, otherwise falls back to `.env`.

## Key Scripts

| Script | Description |
|--------|-------------|
| `./scripts/dev-electron.sh` | Dev mode with hot reload |
| `./scripts/build-electron-local.sh` | Local production build |
| `./scripts/build-electron-prod.sh` | Production build wrapper |

## apps/client Scripts

| Command | Description |
|---------|-------------|
| `bun run dev:electron` | Start dev mode |
| `bun run build:electron` | Full build with electron-builder |
| `bun run build:mac` | macOS-specific build |
| `bun run build:mac:workaround` | Manual macOS app bundle |
| `bun run rebuild:electron` | Rebuild native modules |

## Configuration Files

- `apps/client/electron-builder.json` - electron-builder config
- `apps/client/electron-builder.local.json` - Local dev overrides (no code signing)
- `apps/client/electron.vite.config.ts` - electron-vite build config
- `apps/client/electron/app-update.yml` - Auto-update settings

## Troubleshooting

### tsconfig Warnings from dev-docs/

These warnings are benign - the `dev-docs/` folder contains external reference code that isn't part of the actual cmux build.

### Native Module Issues

```bash
cd apps/client
bun run rebuild:electron
```

### Rust Addon Build Failure

Ensure Rust is installed:

```bash
rustc --version
# If not installed: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Manual rebuild:

```bash
cd apps/server/native/core
bunx --bun @napi-rs/cli build --platform --release
```

## App Details

- **App ID**: `com.cmux.app`
- **URL Scheme**: `cmux://`
- **Electron Version**: 37.2.4 (build script) / 38.0.0 (package.json)
- **Auto-update**: GitHub releases via electron-updater
