# PVE LXC vs Morph Cloud: Production Deployment Comparison

> Comparing sandbox providers for cmux production deployment with focus on resilience, ease of deployment, public access, and HTTPS.
> **Constraint:** PVE v8 behind home router, no port forwarding/DMZ allowed.
> **Status:** Tested and working with Cloudflare Tunnel (2025-12-27)

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
              https://{service}-{vmid}.yourdomain.com
```

---

## URL Pattern (Free Cloudflare Universal SSL)

**Important:** Cloudflare's free Universal SSL only covers single-level wildcards (`*.domain.com`), NOT multi-level (`*.sub.domain.com`). For free SSL, use:

```
https://vscode-200.yourdomain.com    (works with free SSL)
https://worker-200.yourdomain.com    (works with free SSL)
https://xterm-200.yourdomain.com     (works with free SSL)
https://preview-200.yourdomain.com   (works with free SSL)
```

NOT:
```
https://vscode-200.sandbox.yourdomain.com  (requires paid Advanced Certificate)
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
:8080 {
    # VSCode service
    @vscode header_regexp vmid Host ^vscode-(\d+)\.
    handle @vscode {
        reverse_proxy cmux-{re.vmid.1}.lan:39378
    }

    # Worker service
    @worker header_regexp vmid Host ^worker-(\d+)\.
    handle @worker {
        reverse_proxy cmux-{re.vmid.1}.lan:39377
    }

    # Xterm service
    @xterm header_regexp vmid Host ^xterm-(\d+)\.
    handle @xterm {
        reverse_proxy cmux-{re.vmid.1}.lan:39376
    }

    # Preview service (port 5173)
    @preview header_regexp vmid Host ^preview-(\d+)\.
    handle @preview {
        reverse_proxy cmux-{re.vmid.1}.lan:5173
    }

    # Default: 404
    handle {
        respond "cmux sandbox not found" 404
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
│  │  │:39378 vs │  │:39378 vs │  │:39378 vs │               │   │
│  │  │:39377 wk │  │:39377 wk │  │:39377 wk │               │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘               │   │
│  │       └─────────────┼─────────────┘                      │   │
│  └─────────────────────┼────────────────────────────────────┘   │
│                        │                                        │
│  ┌─────────────────────┼────────────────────────────────────┐   │
│  │              Caddy (:8080)                               │   │
│  │  vscode-200.* → cmux-200.lan:39378                      │   │
│  │  worker-200.* → cmux-200.lan:39377                      │   │
│  │  vscode-201.* → cmux-201.lan:39378                      │   │
│  └─────────────────────┬────────────────────────────────────┘   │
│                        │                                        │
│  ┌─────────────────────┼────────────────────────────────────┐   │
│  │           cloudflared (outbound only)                    │   │
│  │  *.yourdomain.com → localhost:8080                      │   │
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
        https://vscode-200.yourdomain.com
        https://worker-200.yourdomain.com
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
- [ ] URL available: `https://{service}-{vmid}.yourdomain.com`

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

# Test public URL
curl -I https://vscode-200.yourdomain.com
```

---

## Tested Configuration (2025-12-27)

| Component | Version | Status |
|-----------|---------|--------|
| PVE | 8.4 | Working |
| cloudflared | 2025.11.1 | Working |
| Caddy | 2.10.2 | Working |
| Cloudflare DNS | Universal SSL | Working |
| Tunnel ID | `6e04bb92-1500-44a7-b469-713cafa9ee5f` | Active |

**Working URLs:**
- `https://vscode-200.alphasolves.com` - VSCode Web UI

---

## Related Files

- `apps/www/lib/utils/pve-lxc-client.ts` - PVE LXC client
- `apps/www/lib/utils/sandbox-instance.ts` - Unified sandbox interface
- `scripts/snapshot-pvelxc.py` - PVE template builder
- `scripts/pve/pve-tunnel-setup.sh` - Automated tunnel setup script

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
