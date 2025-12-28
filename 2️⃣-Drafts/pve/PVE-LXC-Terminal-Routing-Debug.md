# PVE LXC Terminal Routing Debug

Date: 2025-12-28

## Problem

Terminals page for PVE LXC sandboxes showed:
1. Initially: "Terminals are only available for Cloud-based runs"
2. After code fix: 502 Bad Gateway errors from Cloudflare Tunnel

## Diagnostic Process

### Step 1: Check Frontend Provider Support

Found in `terminals.tsx`:
```typescript
// Only checked for morph provider
const isMorphProvider = vscodeInfo?.provider === "morph";
```

**Fix**: Support both providers
```typescript
const isSupportedProvider = vscodeInfo?.provider === "morph" || vscodeInfo?.provider === "pve-lxc";
```

### Step 2: Add xtermUrl to Schema

PVE LXC doesn't use Morph URLs, so we can't derive xterm URL from vscode URL.

Added `xtermUrl` field to:
- `packages/convex/convex/schema.ts` - vscode object
- `packages/convex/convex/taskRuns.ts` - updateVSCodeInstance mutation
- `apps/www/lib/routes/sandboxes.route.ts` - persist when starting sandbox
- `apps/www/lib/utils/pve-lxc-client.ts` - expose in httpServices

### Step 3: Debug 502 Bad Gateway

Created diagnostic script `scripts/test-xterm-cors.sh`:

```bash
# Test 1: External via CF Tunnel - 502 Bad Gateway
curl -s -I "https://xterm-202.alphasolves.com/sessions"

# Test 2: Internal from container - 200 OK with CORS headers
curl -s -X POST "https://exec-202.alphasolves.com/exec" \
  -H "Content-Type: application/json" \
  -d '{"command": "curl -s -i http://127.0.0.1:39383/sessions"}'
```

**Key finding**: cmux-pty works internally with CORS (`access-control-allow-origin: *`), but CF Tunnel returns 502.

### Step 4: Check Caddy Config

```bash
ssh root@karlws "cat /etc/caddy/Caddyfile.cmux | grep -A5 '@xterm'"
```

Found wrong port:
```
reverse_proxy cmux-{re.vmid.1}.lan:39376  # WRONG!
```

Should be:
```
reverse_proxy cmux-{re.vmid.1}.lan:39383  # CORRECT
```

### Step 5: Root Cause

Bug in `scripts/pve/pve-tunnel-setup.sh`:
```bash
# Line 49 - WRONG
XTERM_PORT=39376

# Should be
XTERM_PORT=39383
```

## Fix Applied

1. **Code changes** (committed):
   - Support pve-lxc provider in terminals.tsx
   - Add xtermUrl field to schema and mutations
   - Expose xterm service in pve-lxc-client
   - Fix XTERM_PORT in pve-tunnel-setup.sh

2. **PVE host fix** (live):
   ```bash
   ssh root@karlws "sed -i 's/39376/39383/g' /etc/caddy/Caddyfile.cmux && systemctl reload caddy-cmux"
   ```

## Verification

```bash
curl -s -I "https://xterm-202.alphasolves.com/sessions"
# HTTP/2 200
# access-control-allow-origin: *
```

## Port Reference (Correct)

| Service | Port | Description |
|---------|------|-------------|
| VSCode | 39378 | OpenVSCode Server |
| Worker | 39377 | cmux-worker |
| Exec | 39375 | cmux-execd |
| **Xterm** | **39383** | cmux-pty terminal backend |
| VNC | 39380 | noVNC websockify |
| Preview | 5173 | Vite dev server |

## Lessons Learned

1. When debugging CF Tunnel 502 errors, test both external (via tunnel) and internal (localhost) to isolate the issue
2. The cmux-pty service runs on port 39383, not 39376
3. Always verify port mappings in Caddy config match actual service ports
