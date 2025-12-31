# PVE LXC vs Morph Cloud: Production Deployment Comparison

> Comparing sandbox providers for cmux production deployment with focus on resilience, ease of deployment, public access, and HTTPS.
> **Constraint:** PVE v8 behind home router, no port forwarding/DMZ allowed.
> **Status:** Tested and working with Cloudflare Tunnel (2025-12-27)
> **PR:** https://github.com/karlorz/cmux/pull/27
> **Update (2025-12-31):** URL pattern refactored to Morph-consistent `port-{port}-vm-{vmid}.{domain}`

---

## Executive Summary

| Requirement       | Morph Cloud           | PVE LXC + Cloudflare Tunnel       |
| ----------------- | --------------------- | --------------------------------- |
| **Resilience**    | Managed, auto-scaling | Self-managed, single node OK      |
| **Easy Deploy**   | API call              | API call + one-time tunnel setup  |
| **Public Access** | Built-in              | Cloudflare Tunnel (no port open)  |
| **HTTPS**         | Automatic SSL         | Cloudflare Universal SSL (free)   |
| **Auth**          | API key optional      | Zero Trust Access (free)          |
| **Cost**          | Pay-per-use           | Free (Cloudflare) + infra         |

**Recommendation for your setup:** PVE LXC + Cloudflare Tunnel is ideal - no port forwarding needed, free tier covers homelab use, and you already have Cloudflare domain control.

---

## Architecture: PVE Behind Home Router

```
┌─────────────────────────────────────────────────────────────────┐
│                         Home Network                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    PVE Host (v8)                        │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                 │   │
│  │  │cmux-200 │  │cmux-201 │  │cmux-N   │   LXC containers│   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘                 │   │
│  │       └────────────┼───────────┘                       │   │
│  │              vmbr0 (bridge)                            │   │
│  │                    │                                    │   │
│  │  ┌─────────────────┼──────────────────┐                │   │
│  │  │           cloudflared              │  Outbound only │   │
│  │  │     (tunnel connector daemon)      │  No ports open │   │
│  │  └─────────────────┬──────────────────┘                │   │
│  └────────────────────┼────────────────────────────────────┘   │
│                       │                                        │
│  ┌────────────────────┼────────────────────┐                   │
│  │              Home Router               │                    │
│  │         (NAT, no port forward)         │                    │
│  └────────────────────┼────────────────────┘                   │
└───────────────────────┼─────────────────────────────────────────┘
                        │ Outbound HTTPS (443)
                        ▼
┌───────────────────────────────────────────────────────────────────┐
│                    Cloudflare Edge                                │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Zero Trust Tunnel          │  Access Policies              │ │
│  │  - SSL termination          │  - Email OTP auth             │ │
│  │  - DDoS protection          │  - GitHub/Google SSO          │ │
│  │  - WAF (basic)              │  - IP allowlist               │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────┬─────────────────────────────────────────┘
                          │
              https://port-{port}-vm-{vmid}.yourdomain.com
```

---

## URL Pattern (Morph-Consistent)

### Pattern Comparison

| Provider | Pattern | Example |
|----------|---------|---------|
| **Morph Cloud** | `port-{port}-morphvm_{id}.http.cloud.morph.so` | `port-39378-morphvm_mmcz8L6eoJHtLqFz3.http.cloud.morph.so` |
| **PVE LXC/VM** | `port-{port}-vm-{vmid}.{domain}` | `port-39378-vm-200.alphasolves.com` |

### New URL Pattern

The PVE URL pattern uses **port-first** format like Morph Cloud, with a single Caddy rule handling all services:

```
https://port-39378-vm-200.yourdomain.com   - VSCode (port 39378)
https://port-39377-vm-200.yourdomain.com   - Worker (port 39377)
https://port-39375-vm-200.yourdomain.com   - Exec (port 39375)
https://port-39380-vm-200.yourdomain.com   - VNC (port 39380)
https://port-39383-vm-200.yourdomain.com   - Xterm (port 39383)
https://port-5173-vm-200.yourdomain.com    - Preview (port 5173)
```

### Benefits

1. **Morph-consistent**: Same `port-{port}-vm-{id}` structure as Morph Cloud
2. **Single Caddy rule**: One regex handles all services, no hardcoded service names
3. **Extensible**: Any new port works automatically without config changes
4. **Easy to identify**: `vm-{vmid}` makes it easy to identify in PVE host management

### Note on Free Cloudflare Universal SSL

Cloudflare's free Universal SSL covers single-level wildcards (`*.domain.com`). The pattern works with free SSL:

```
https://port-39378-vm-200.yourdomain.com  (works with free SSL)
```

---

## Tunneling Solutions Comparison

Since you cannot open ports, tunneling is **required** (not optional) for public access.

### Solution Comparison

| Feature | Cloudflare Tunnel | Tailscale Funnel | ngrok |
|---------|-------------------|------------------|-------|
| **Cost** | Free (50 tunnels) | Free (personal) | Free limited, $8+/mo |
| **Custom Domain** | Yes (your domain) | No (*.ts.net) | Paid only |
| **Wildcard Subdomain** | Yes (single-level free) | No | Paid only |
| **SSL** | Automatic (Universal) | Automatic | Automatic |
| **Auth Layer** | Zero Trust Access | Tailscale ACL | Basic auth |
| **Latency** | CDN routed (medium) | P2P (low) | Server routed (medium) |
| **Setup Complexity** | Medium | Low | Very Low |
| **Best For** | Public services | Private access | Dev/testing |

### Recommendation: Cloudflare Tunnel

Given your requirements:
- You have Cloudflare domain control
- Need public access with custom domain
- Need wildcard subdomains for dynamic sandboxes
- Cost-sensitive (free tier)

**Cloudflare Tunnel is the best choice.**

---

## Automated Setup Script

A setup script is available at `scripts/pve/pve-tunnel-setup.sh` that automates the entire process:

```bash
# Copy to PVE host
scp scripts/pve/pve-tunnel-setup.sh root@pve:/tmp/

# Set environment variables on PVE host
export CF_API_TOKEN="your-api-token"
export CF_ZONE_ID="your-zone-id"
export CF_ACCOUNT_ID="your-account-id"
export CF_DOMAIN="yourdomain.com"

# Run full setup
bash /tmp/pve-tunnel-setup.sh setup
```

The script will:
1. Install cloudflared
2. Install Caddy
3. Create tunnel via Cloudflare API
4. Configure wildcard DNS (`*.yourdomain.com` -> tunnel)
5. Set up Caddy for dynamic subdomain routing
6. Create systemd services

---

## Manual Setup Guide

### Step 1: Install cloudflared on PVE host

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

### Step 2: Create Tunnel via API

```bash
# Create tunnel
curl -X POST "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"name":"cmux-tunnel","config_src":"local"}'

# Get tunnel token
curl -X GET "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" \
    -H "Authorization: Bearer ${CF_API_TOKEN}"
```

### Step 3: Configure cloudflared

```yaml
# /etc/cloudflared/config.yml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/<tunnel-id>.json

ingress:
  # Route all subdomains to local Caddy
  - hostname: "*.yourdomain.com"
    service: http://localhost:8080
    originRequest:
      noTLSVerify: true

  # Catch-all (required)
  - service: http_status:404
```

### Step 4: DNS Configuration in Cloudflare

```bash
# Add wildcard CNAME pointing to tunnel
# Type: CNAME
# Name: *
# Target: <tunnel-id>.cfargotunnel.com
# Proxy: ON (orange cloud)
```

### Step 5: Local Reverse Proxy (Caddy)

```caddyfile
# /etc/caddy/Caddyfile.cmux
# Morph-consistent URL pattern: port-{port}-vm-{vmid}.{domain}
:8080 {
    # Single rule handles all services: port-{port}-vm-{vmid}.{domain}
    @service header_regexp match Host ^port-(\d+)-vm-(\d+)\.
    handle @service {
        reverse_proxy cmux-{re.match.2}.lan:{re.match.1}
    }

    # Default: 404
    handle {
        respond "Use format: port-{port}-vm-{vmid}.{domain}" 404
    }
}
```

### Step 6: Run as Service

```bash
# cloudflared service
systemctl enable cloudflared
systemctl start cloudflared

# Caddy service
systemctl enable caddy-cmux
systemctl start caddy-cmux

# Check status
systemctl status cloudflared
systemctl status caddy-cmux
```

---

## Zero Trust Access (Optional but Recommended)

Add authentication layer without modifying your application:

### Option A: One-Time PIN (Simplest)

```
1. Zero Trust Dashboard > Access > Applications > Add Application
2. Application type: Self-hosted
3. Application domain: *.yourdomain.com
4. Policy: Allow
   - Selector: Emails
   - Value: your-email@example.com
5. Authentication: One-time PIN
```

Users receive email with PIN to access sandbox URLs.

### Option B: GitHub/Google SSO

```
1. Zero Trust Dashboard > Settings > Authentication
2. Add Identity Provider > GitHub
3. Create OAuth App in GitHub, copy Client ID/Secret
4. Update Access Application policy to use GitHub
```

### Best Practice: Skip Auth for Specific Paths

For API endpoints or webhooks that need public access:

```
1. Create bypass policy for specific paths
2. Selector: URI Path
3. Value: /api/webhook/*
4. Action: Bypass
```

---

## Complete Architecture with Cloudflare

```
┌─────────────────────────────────────────────────────────────────┐
│                         PVE Host                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  LXC Containers                                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │   │
│  │  │cmux-200  │  │cmux-201  │  │cmux-202  │               │   │
│  │  │:39378 vs │  │:39378 vs │  │:39378 vs │  vscode       │   │
│  │  │:39377 wk │  │:39377 wk │  │:39377 wk │  worker       │   │
│  │  │:39375 ex │  │:39375 ex │  │:39375 ex │  cmux-execd   │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘               │   │
│  │       └─────────────┼─────────────┘                      │   │
│  └─────────────────────┼────────────────────────────────────┘   │
│                        │                                        │
│  ┌─────────────────────┼────────────────────────────────────┐   │
│  │              Caddy (:8080)                               │   │
│  │  port-39378-vm-200.* -> cmux-200.lan:39378              │   │
│  │  port-39377-vm-200.* -> cmux-200.lan:39377              │   │
│  │  port-39375-vm-200.* -> cmux-200.lan:39375              │   │
│  └─────────────────────┬────────────────────────────────────┘   │
│                        │                                        │
│  ┌─────────────────────┼────────────────────────────────────┐   │
│  │           cloudflared (outbound only)                    │   │
│  │  *.yourdomain.com -> localhost:8080                      │   │
│  └─────────────────────┬────────────────────────────────────┘   │
└────────────────────────┼────────────────────────────────────────┘
                         │
                    ─────┼───── Home Router (NAT) ─────
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                  Cloudflare Edge                               │
│  - SSL termination (Universal SSL, free)                       │
│  - Zero Trust Access (optional auth)                           │
│  - DDoS protection                                             │
│  - WAF (basic protection)                                      │
└────────────────────────┬───────────────────────────────────────┘
                         │
        https://port-39378-vm-200.yourdomain.com
        https://port-39377-vm-200.yourdomain.com
```

---

## Production Checklist

### Cloudflare Setup (One-time)
- [x] Domain added to Cloudflare (NS records updated)
- [x] Tunnel created via API
- [x] Wildcard DNS CNAME added (`*` -> tunnel)
- [ ] Zero Trust Access policy configured (optional)

### PVE Host Setup (One-time)
- [x] PVE 8.x installed
- [x] cloudflared installed and configured
- [x] Caddy installed with subdomain routing
- [x] LXC template prepared
- [x] Systemd services enabled

### Per-Sandbox (Automated via API)
- [ ] Clone from template (`pct clone`)
- [ ] Start container (`pct start`)
- [ ] URL available: `https://port-{port}-vm-{vmid}.yourdomain.com`

---

## Comparison: Final Verdict

| Aspect | Morph Cloud | PVE + Cloudflare Tunnel |
|--------|-------------|-------------------------|
| **Setup Time** | Minutes | Hours (one-time) |
| **Ongoing Effort** | None | Minimal |
| **Public URL** | Automatic | Automatic (after setup) |
| **HTTPS** | Automatic | Automatic (Cloudflare edge) |
| **Custom Domain** | No | Yes |
| **Auth Options** | API key | Zero Trust (SSO, OTP, etc.) |
| **Cost** | $$ (pay-per-use) | Free tier sufficient |
| **Resilience** | Managed | Self-managed |
| **Port Forwarding** | N/A | Not needed |

### When to Use Each

| Scenario | Recommendation |
|----------|----------------|
| Quick prototyping | Morph Cloud |
| Production (budget available) | Morph Cloud |
| **Homelab behind NAT, no port forward** | **PVE + Cloudflare Tunnel** |
| Air-gapped network | PVE only (no tunnel) |
| Cost-sensitive production | PVE + Cloudflare Tunnel |

---

## Exposing PVE API via Cloudflare Tunnel

If you want to access the PVE API from outside your network (e.g., from cmux running elsewhere), you can expose the local PVE API (`https://karl-ws.lan:8006`) via Cloudflare Tunnel as `https://pve.alphasolves.com`.

### Why Expose PVE API?

- **Remote Management**: Manage PVE and LXC containers from anywhere
- **cmux Integration**: Allow cmux (hosted elsewhere) to provision sandboxes on your home PVE
- **No Port Forwarding**: Works behind NAT without opening router ports
- **Zero Trust Auth**: Protect API access with Cloudflare Access policies

### Step 1: Add PVE Route to Caddy

Update your Caddy configuration to route `pve.alphasolves.com` to the local PVE API:

```caddyfile
# /etc/caddy/Caddyfile.cmux
:8080 {
    # PVE API - route to local PVE host
    @pve host pve.alphasolves.com
    handle @pve {
        reverse_proxy https://karl-ws.lan:8006 {
            transport http {
                tls_insecure_skip_verify
            }
        }
    }

    # Generic port-based routing (Morph-consistent)
    @service header_regexp match Host ^port-(\d+)-vm-(\d+)\.
    handle @service {
        reverse_proxy cmux-{re.match.2}.lan:{re.match.1}
    }

    # ... rest of existing config ...
}
```

Key points:
- `@pve host pve.alphasolves.com` matches exact hostname
- `tls_insecure_skip_verify` is needed because PVE uses self-signed cert
- This rule should come before wildcard rules

### Step 2: Add DNS Record in Cloudflare

Add a CNAME record for `pve.alphasolves.com`:

```
Type: CNAME
Name: pve
Target: <tunnel-id>.cfargotunnel.com
Proxy: ON (orange cloud)
```

Or via API:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{
        "type": "CNAME",
        "name": "pve",
        "content": "<tunnel-id>.cfargotunnel.com",
        "proxied": true
    }'
```

### Step 3: (Optional but Recommended) Add Zero Trust Access Policy

Protect the PVE API with authentication:

1. Go to **Zero Trust Dashboard > Access > Applications > Add Application**
2. Application type: **Self-hosted**
3. Application domain: `pve.alphasolves.com`
4. Create policy:
   - **Name**: `PVE API Access`
   - **Action**: Allow
   - **Include**: Emails - `your-email@example.com`
5. Enable **One-time PIN** or configure SSO

For API access (e.g., from cmux), create a **Service Token**:

1. **Zero Trust Dashboard > Access > Service Auth > Create Service Token**
2. Copy the `CF-Access-Client-Id` and `CF-Access-Client-Secret`
3. Use in API calls:

```bash
curl -H "CF-Access-Client-Id: <client-id>" \
     -H "CF-Access-Client-Secret: <client-secret>" \
     https://pve.alphasolves.com/api2/json/version
```

### Step 4: Update Environment Variables

Update your `.env` to use the public URL:

```bash
# Before (local only)
PVE_API_URL=https://karl-ws.lan:8006

# After (accessible from anywhere via Cloudflare Tunnel)
PVE_API_URL=https://pve.alphasolves.com

# If using Zero Trust, add service token credentials
CF_ACCESS_CLIENT_ID=<client-id>
CF_ACCESS_CLIENT_SECRET=<client-secret>
```

### Step 5: Reload Services

```bash
# Reload Caddy config
systemctl reload caddy-cmux

# Verify the route is working
curl -k https://pve.alphasolves.com/api2/json/version
```

### Security Considerations

| Protection Layer | Description |
|------------------|-------------|
| **Cloudflare WAF** | Basic protection against common attacks |
| **Zero Trust Access** | Require authentication before reaching PVE |
| **PVE API Token** | Use limited-permission API tokens, not root |
| **SSL/TLS** | End-to-end encryption (Cloudflare -> Caddy -> PVE) |

**Best Practice**: Create a dedicated PVE API token with minimal permissions:

```bash
# On PVE host, create user and token
pveum user add cmux@pve
pveum aclmod / -user cmux@pve -role PVEVMAdmin
pveum user token add cmux@pve cmux-token --privsep=0
```

Use the generated token:
```
PVE_API_TOKEN=cmux@pve!cmux-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

## cmux-execd: HTTP Exec Daemon

The `cmux-execd` service runs inside each LXC container and provides HTTP-based command execution. This replaces the need for SSH access and enables command execution via Cloudflare Tunnel.

### Service Details

| Property | Value |
|----------|-------|
| **Port** | 39375 |
| **Protocol** | HTTP |
| **URL Pattern** | `https://port-39375-vm-{vmid}.{domain}/exec` |
| **Systemd Unit** | `cmux-execd.service` |

### API Endpoint

```bash
# Execute a command (Morph-consistent URL pattern)
curl -X POST https://port-39375-vm-200.alphasolves.com/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "echo hello", "cwd": "/workspace"}'

# Response
{
  "stdout": "hello\n",
  "stderr": "",
  "exitCode": 0
}
```

### Key Features

- **No SSH Required**: HTTP-only, no SSH keys or port 22 exposure
- **Works with CF Tunnel**: Accessible via public URL with SSL
- **Stateless**: Each request is independent
- **Timeout Handling**: Configurable command timeouts
- **Environment Variables**: Supports `HOME=/root` and custom env

### Container Setup

The service is installed during template creation:

```bash
# Check service status
pct exec 200 -- systemctl status cmux-execd

# View logs
pct exec 200 -- journalctl -u cmux-execd -f
```

---

## Quick Reference Commands

```bash
# Cloudflared
cloudflared tunnel list
cloudflared tunnel info cmux-tunnel
systemctl status cloudflared
journalctl -u cloudflared -f

# Caddy
systemctl status caddy-cmux
journalctl -u caddy-cmux -f

# PVE LXC
pct clone 9000 200 --hostname cmux-200 --full 0
pct start 200
pct exec 200 -- systemctl status cmux-execd

# Test public URL (Morph-consistent pattern)
curl -I https://port-39378-vm-200.yourdomain.com

# Test exec service via tunnel
curl -X POST https://port-39375-vm-200.alphasolves.com/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "whoami"}'

# Test PVE API via tunnel
curl -k https://pve.alphasolves.com/api2/json/version
```

---

## Tested Configuration (2025-12-31)

| Component | Version | Status |
|-----------|---------|--------|
| PVE | 8.4.14 | Working |
| cloudflared | 2025.11.1 | Working |
| Caddy | 2.10.2 | Working |
| Cloudflare DNS | Universal SSL | Working |
| Tunnel ID | `6e04bb92-1500-44a7-b469-713cafa9ee5f` | Active |
| URL Pattern | `port-{port}-vm-{vmid}` | Updated |

**Working URLs (Morph-consistent pattern):**
- `https://pve.alphasolves.com` - PVE API (via tunnel)
- `https://port-39378-vm-200.alphasolves.com` - VSCode (port 39378)
- `https://port-39377-vm-200.alphasolves.com` - Worker (port 39377)
- `https://port-39375-vm-200.alphasolves.com` - Exec (port 39375)

---

## Port Reference

| Service | Port | URL Pattern (Morph-consistent) | Description |
|---------|------|--------------------------------|-------------|
| VSCode | 39378 | `port-39378-vm-{vmid}.domain` | VSCode Web UI |
| Worker | 39377 | `port-39377-vm-{vmid}.domain` | Worker service |
| Xterm | 39383 | `port-39383-vm-{vmid}.domain` | Xterm terminal |
| Exec | 39375 | `port-39375-vm-{vmid}.domain` | cmux-execd HTTP exec |
| VNC | 39380 | `port-39380-vm-{vmid}.domain` | noVNC websockify |
| Preview | 5173 | `port-5173-vm-{vmid}.domain` | Dev server preview |

---

## Related Files

- `apps/www/lib/utils/pve-lxc-client.ts` - PVE LXC client
- `apps/www/lib/utils/sandbox-instance.ts` - Unified sandbox interface
- `scripts/snapshot-pvelxc.py` - PVE template builder
- `scripts/pve/pve-tunnel-setup.sh` - Automated tunnel setup script
- `scripts/pve/test-pve-cf-tunnel.ts` - Test script for CF tunnel + LXC exec

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Cloudflare Zero Trust Access](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [Cloudflare Wildcard DNS](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/)
- [Cloudflare Universal SSL](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/)
- [Homelab with Cloudflare Tunnels](https://itsfoss.com/cloudflare-tunnels/)
- [Zero Trust Homelab Setup](https://netsecops.blog/2024/12/20/zero-trust-homelab-setup-with-cloudflare/)
- [Cloudflare vs Tailscale vs ngrok](https://dev.to/mechcloud_academy/cloudflare-tunnel-vs-ngrok-vs-tailscale-choosing-the-right-secure-tunneling-solution-4inm)
- [PVE LXC Documentation](https://pve.proxmox.com/pve-docs/chapter-pct.html)
- [Morph Cloud HTTP Services](https://cloud.morph.so/docs/documentation/instances/http-services)
