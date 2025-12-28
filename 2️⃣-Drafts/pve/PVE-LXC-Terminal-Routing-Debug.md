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

---

## Complete PVE LXC URL Configuration Reference

### Service Port Mapping

| Service | Port | Description | Container Service |
|---------|------|-------------|-------------------|
| Exec | 39375 | cmux-execd (HTTP command exec) | cmux-execd |
| Worker | 39377 | cmux-worker (Socket.IO) | cmux-worker |
| VSCode | 39378 | OpenVSCode Server (Web IDE) | openvscode-server |
| Proxy | 39379 | cmux-proxy (HTTP proxy) | cmux-proxy |
| VNC | 39380 | noVNC websockify | vnc-websockify |
| CDP | 39381 | Chrome DevTools Protocol | chrome-devtools |
| **Xterm** | **39383** | cmux-pty (Web terminal) | cmux-pty |
| Preview | 5173 | Vite dev server | user app |

### Environment Variables (Server-side)

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SANDBOX_PROVIDER` | No | Force provider selection | `"morph"` or `"proxmox"` |
| `PVE_API_URL` | For PVE | Proxmox API endpoint | `https://pve.example.com` |
| `PVE_API_TOKEN` | For PVE | API token with LXC permissions | `root@pam!mytoken=uuid` |
| `PVE_NODE` | No | Target PVE node (auto-detected) | `pve1` |
| `PVE_PUBLIC_DOMAIN` | For CF Tunnel | Domain for public URLs | `example.com` |
| `MORPH_API_KEY` | For Morph | Morph Cloud API key | `morph_xxx` |

### Cloudflare Tunnel URL Pattern

```
https://{service}-{vmid}.{PVE_PUBLIC_DOMAIN}
```

Examples for VMID 202 with domain `alphasolves.com`:
- VSCode: `https://vscode-202.alphasolves.com`
- Worker: `https://worker-202.alphasolves.com`
- Xterm: `https://xterm-202.alphasolves.com`
- Exec: `https://exec-202.alphasolves.com`
- VNC: `https://vnc-202.alphasolves.com`
- Preview: `https://preview-202.alphasolves.com`

### Caddy Routing Configuration

Location: `/etc/caddy/Caddyfile.cmux` on PVE host

```caddyfile
:8080 {
    # VSCode service
    @vscode header_regexp vmid Host ^vscode-(\d+)\.
    handle @vscode {
        reverse_proxy cmux-{re.vmid.1}.lan:39378
    }

    # Worker service (Socket.IO)
    @worker header_regexp vmid Host ^worker-(\d+)\.
    handle @worker {
        reverse_proxy cmux-{re.vmid.1}.lan:39377
    }

    # Xterm service (cmux-pty)
    @xterm header_regexp vmid Host ^xterm-(\d+)\.
    handle @xterm {
        reverse_proxy cmux-{re.vmid.1}.lan:39383
    }

    # Exec service (cmux-execd)
    @exec header_regexp vmid Host ^exec-(\d+)\.
    handle @exec {
        reverse_proxy cmux-{re.vmid.1}.lan:39375
    }

    # VNC service (noVNC websockify)
    @vnc header_regexp vmid Host ^vnc-(\d+)\.
    handle @vnc {
        reverse_proxy cmux-{re.vmid.1}.lan:39380
    }

    # Preview service (port 5173)
    @preview header_regexp vmid Host ^preview-(\d+)\.
    handle @preview {
        reverse_proxy cmux-{re.vmid.1}.lan:5173
    }
}
```

### Convex Schema (vscode object)

```typescript
vscode: v.optional(
  v.object({
    provider: v.union(
      v.literal("docker"),
      v.literal("morph"),
      v.literal("daytona"),
      v.literal("pve-lxc"),
      v.literal("other")
    ),
    containerName: v.optional(v.string()),
    status: v.union(
      v.literal("starting"),
      v.literal("running"),
      v.literal("stopped")
    ),
    url: v.optional(v.string()),           // VSCode base URL
    workspaceUrl: v.optional(v.string()),  // VSCode with ?folder=
    vncUrl: v.optional(v.string()),        // VNC base URL
    xtermUrl: v.optional(v.string()),      // Xterm base URL
    // ... other fields
  })
)
```

### Client-side URL Derivation Functions

| Function | Purpose | Works with PVE LXC? |
|----------|---------|---------------------|
| `toMorphVncUrl()` | Derive VNC URL from Morph workspace URL | No - Morph only |
| `toMorphXtermBaseUrl()` | Derive xterm URL from Morph workspace URL | No - Morph only |
| `toVncViewerUrl()` | Convert any VNC base URL to noVNC viewer | Yes |

**Key insight**: For PVE LXC, we must store `vncUrl` and `xtermUrl` explicitly in Convex because we cannot derive them from the workspace URL (which only works for Morph's URL pattern).

### Frontend Components URL Flow

```
sandboxes.route.ts (server)
  └── Starts sandbox, gets httpServices
  └── Persists to Convex: { url, workspaceUrl, vncUrl, xtermUrl }

Task Detail Page (client)
  └── Reads selectedRun?.vscode from Convex
  └── For browser panel:
      └── If vncUrl exists: use toVncViewerUrl(vncUrl)
      └── Else if rawBrowserUrl: use toMorphVncUrl(rawBrowserUrl)
  └── For terminal panel:
      └── If xtermUrl exists: use xtermUrl directly
      └── Else if rawWorkspaceUrl: use toMorphXtermBaseUrl(rawWorkspaceUrl)
```

### Checklist: Adding New PVE LXC Service

1. [ ] Add port constant to `scripts/pve/pve-tunnel-setup.sh`
2. [ ] Add Caddy route in `configure_caddy()` function
3. [ ] Add httpService in `pve-lxc-client.ts` → `instances.start()`
4. [ ] Add field to Convex schema if needed
5. [ ] Update `updateVSCodeInstance` mutation if needed
6. [ ] Persist URL in `sandboxes.route.ts`
7. [ ] Update frontend components to read new URL
8. [ ] Redeploy Caddy config on PVE host: `systemctl reload caddy-cmux`

---

## Lessons Learned

1. When debugging CF Tunnel 502 errors, test both external (via tunnel) and internal (localhost) to isolate the issue
2. The cmux-pty service runs on port 39383, not 39376
3. Always verify port mappings in Caddy config match actual service ports
4. PVE LXC URLs cannot be derived from workspace URL like Morph - must be stored explicitly
5. When adding new services, update both `pve-tunnel-setup.sh` AND the live Caddy config on PVE host
