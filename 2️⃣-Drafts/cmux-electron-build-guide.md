# cmux Electron Build Guide (macOS)

Short guide for local builds and CI macOS releases.

## Prereqs

```bash
bun --version
node --version
rustc --version
xcrun --version
```

Install tools you are missing (bun, rust, Xcode CLT).

## Local unsigned build (fast)

```bash
cd /path/to/cmux
bun install --frozen-lockfile

cat > .env <<'EOF'
NEXT_PUBLIC_CONVEX_URL=https://your-convex-url.convex.cloud
NEXT_PUBLIC_STACK_PROJECT_ID=your-stack-project-id
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=your-stack-key
NEXT_PUBLIC_WWW_ORIGIN=https://your-www-origin.com
NEXT_PUBLIC_GITHUB_APP_SLUG=your-github-app-slug
EOF

./scripts/build-electron-local.sh
```

Outputs are under `apps/client/dist-electron/`.

If macOS blocks the app:

```bash
xattr -cr apps/client/dist-electron/mac-arm64/cmux.app
open apps/client/dist-electron/mac-arm64/cmux.app
```

## Signed build (arm64)

1. Create a Developer ID Application certificate and export a `.p12`.
2. Create an App Store Connect API key (`.p8`, Key ID, Issuer ID).
3. Create `.env.codesign`:

```bash
cd /path/to/cmux
MAC_CERT_BASE64=$(base64 -i /path/to/developer_id_certificate.p12 | tr -d '\n')

cat > .env.codesign << EOF
MAC_CERT_BASE64=${MAC_CERT_BASE64}
MAC_CERT_PASSWORD=your-p12-password
APPLE_API_KEY=/Users/$(whoami)/.apple-keys/AuthKey_ABC1234567.p8
APPLE_API_KEY_ID=ABC1234567
APPLE_API_ISSUER=12345678-1234-1234-1234-123456789012
NEXT_PUBLIC_CONVEX_URL=https://your-convex-url.convex.cloud
NEXT_PUBLIC_STACK_PROJECT_ID=your-stack-project-id
NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY=your-stack-key
NEXT_PUBLIC_WWW_ORIGIN=https://your-www-origin.com
NEXT_PUBLIC_GITHUB_APP_SLUG=your-github-app-slug
EOF

chmod 600 .env.codesign
```

Run the signed build:

```bash
bash scripts/publish-build-mac-arm64.sh --env-file .env.codesign
```

Output: `apps/client/dist-electron/cmux-<version>-arm64.dmg`.

## Universal build (optional)

Universal builds require both Rust targets and Rosetta on Apple Silicon.

```bash
rustup target add x86_64-apple-darwin aarch64-apple-darwin
/usr/sbin/softwareupdate --install-rosetta --agree-to-license

cd apps/server/native/core
bunx --bun @napi-rs/cli build --platform --release --target x86_64-apple-darwin
bunx --bun @napi-rs/cli build --platform --release --target aarch64-apple-darwin
mv cmux_native_core.darwin-x86_64.node cmux_native_core.darwin-x64.node
cd ../../../..

cd apps/client
bunx electron-vite build -c electron.vite.config.ts
bunx electron-builder --config electron-builder.json --mac dmg zip --universal --publish never
```

## CI macOS release flow

Upstream mac builds run in `.github/workflows/release-updates.yml`:

- `mac-arm64` and `mac-universal` jobs run on a self-hosted macOS runner.
- Jobs use Apple signing and notarization secrets (`MAC_CERT_*`, `APPLE_API_*`).
- They call `scripts/publish-build-mac-arm64.sh` or the universal path and then upload to GitHub Releases.

In `.github/workflows/release-on-tag.yml`, the mac jobs are currently disabled (`if: false`), so tag builds only produce Windows and Linux unless you enable the mac jobs and provide a self-hosted runner + signing secrets.

## Side-by-side installs on the same Mac

Current app id is `com.cmux.app`. If two builds share the same app id:

- One app can overwrite the other in `/Applications`.
- They share the same user data directory.
- Auto-update and URL scheme registration can conflict.

To run both safely, change these per build:

- `appId` in `apps/client/electron-builder*.json`.
- `productName` (app bundle name).
- URL scheme (if you use `cmux://`).
- Update channel or GitHub release feed (to avoid cross-updates).

## Reference files

- `apps/client/electron-builder.json`
- `apps/client/electron-builder.local.json`
- `apps/client/electron.vite.config.ts`
- `apps/client/build/entitlements.mac.plist`
- `scripts/build-electron-local.sh`
- `scripts/publish-build-mac-arm64.sh`
- `.github/workflows/release-updates.yml`
