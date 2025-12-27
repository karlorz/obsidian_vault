# PVE LXC vs Morph Cloud: Production Deployment Comparison

> Comparing sandbox providers for cmux production deployment with focus on resilience, ease of deployment, public access, and HTTPS.
> **Constraint:** PVE v8 behind home router, no port forwarding/DMZ allowed.

---

## Executive Summary

| Requirement       | Morph Cloud           | PVE LXC + Cloudflare Tunnel       |
| ----------------- | --------------------- | --------------------------------- |
| **Resilience**    | Managed, auto-scaling | Self-managed, single node OK      |
| **Easy Deploy**   | API call              | API call + one-time tunnel setup  |
| **Public Access** | Built-in              | Cloudflare Tunnel (no port open)  |
| **HTTPS**         | Automatic SSL         | Cloudflare edge SSL (automatic)   |
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
            https://*.sandbox.yourdomain.com
```

---

## Tunneling Solutions Comparison

Since you cannot open ports, tunneling is **required** (not optional) for public access.

### Solution Comparison

| Feature | Cloudflare Tunnel | Tailscale Funnel | ngrok |
|---------|-------------------|------------------|-------|
| **Cost** | Free (50 tunnels) | Free (personal) | Free limited, $8+/mo |
| **Custom Domain** | Yes (your domain) | No (*.ts.net) | Paid only |
| **Wildcard Subdomain** | Yes (free tier) | No | Paid only |
| **SSL** | Automatic | Automatic | Automatic |
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

## Cloudflare Tunnel Setup Guide

### Step 1: Create Tunnel in Zero Trust Dashboard

```bash
# Install cloudflared on PVE host
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# Login and create tunnel
cloudflared tunnel login
cloudflared tunnel create cmux-tunnel

# Note the tunnel ID (e.g., a1b2c3d4-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
```

### Step 2: Configure Tunnel for Wildcard Routing

```yaml
# /etc/cloudflared/config.yml
tunnel: a1b2c3d4-xxxx-xxxx-xxxx-xxxxxxxxxxxx
credentials-file: /root/.cloudflared/a1b2c3d4-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json

ingress:
  # Route to local Caddy/Nginx for dynamic subdomain handling
  - hostname: "*.sandbox.yourdomain.com"
    service: http://localhost:8080
    originRequest:
      noTLSVerify: true

  # Catch-all (required)
  - service: http_status:404
```

### Step 3: DNS Configuration in Cloudflare

```bash
# Add wildcard CNAME pointing to tunnel
# In Cloudflare Dashboard > DNS:
# Type: CNAME
# Name: *.sandbox
# Target: a1b2c3d4-xxxx-xxxx-xxxx-xxxxxxxxxxxx.cfargotunnel.com
# Proxy: ON (orange cloud)
```

### Step 4: Local Reverse Proxy (Caddy)

Cloudflare Tunnel routes to a local proxy that handles dynamic subdomain routing:

```caddyfile
# /etc/caddy/Caddyfile
:8080 {
  @vscode header_regexp vmid Host ^vscode-(\d+)\.sandbox\.
  handle @vscode {
    reverse_proxy cmux-{re.vmid.1}.lan:39378
  }

  @worker header_regexp vmid Host ^worker-(\d+)\.sandbox\.
  handle @worker {
    reverse_proxy cmux-{re.vmid.1}.lan:39377
  }

  @xterm header_regexp vmid Host ^xterm-(\d+)\.sandbox\.
  handle @xterm {
    reverse_proxy cmux-{re.vmid.1}.lan:39376
  }

  # Default: 404
  respond "Not Found" 404
}
```

### Step 5: Run as Service

```bash
# Install as systemd service
cloudflared service install

# Enable and start
systemctl enable cloudflared
systemctl start cloudflared

# Check status
systemctl status cloudflared
journalctl -u cloudflared -f
```

---

## Zero Trust Access (Optional but Recommended)

Add authentication layer without modifying your application:

### Option A: One-Time PIN (Simplest)

```
1. Zero Trust Dashboard > Access > Applications > Add Application
2. Application type: Self-hosted
3. Application domain: *.sandbox.yourdomain.com
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
│  │  vscode-200.sandbox.* → cmux-200.lan:39378              │   │
│  │  worker-200.sandbox.* → cmux-200.lan:39377              │   │
│  │  vscode-201.sandbox.* → cmux-201.lan:39378              │   │
│  └─────────────────────┬────────────────────────────────────┘   │
│                        │                                        │
│  ┌─────────────────────┼────────────────────────────────────┐   │
│  │           cloudflared (outbound only)                    │   │
│  │  *.sandbox.yourdomain.com → localhost:8080              │   │
│  └─────────────────────┬────────────────────────────────────┘   │
└────────────────────────┼────────────────────────────────────────┘
                         │
                    ─────┼───── Home Router (NAT) ─────
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                  Cloudflare Edge                               │
│  - SSL termination (automatic)                                 │
│  - Zero Trust Access (optional auth)                           │
│  - DDoS protection                                             │
│  - WAF (basic protection)                                      │
└────────────────────────┬───────────────────────────────────────┘
                         │
        https://vscode-200.sandbox.yourdomain.com
        https://worker-200.sandbox.yourdomain.com
```

---

## Production Checklist

### Cloudflare Setup (One-time)
- [ ] Domain added to Cloudflare (NS records updated)
- [ ] Tunnel created (`cloudflared tunnel create`)
- [ ] Wildcard DNS CNAME added (`*.sandbox` → tunnel)
- [ ] Zero Trust Access policy configured (optional)

### PVE Host Setup (One-time)
- [ ] PVE 8.x installed
- [ ] cloudflared installed and configured
- [ ] Caddy installed with subdomain routing
- [ ] LXC template prepared

### Per-Sandbox (Automated via API)
- [ ] Clone from template (`pct clone`)
- [ ] Start container (`pct start`)
- [ ] URL available: `https://{service}-{vmid}.sandbox.yourdomain.com`

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

# PVE LXC
pct clone 9000 200 --hostname cmux-200 --full 0
pct start 200
pct exec 200 -- systemctl status cmux-execd

# Test public URL
curl -I https://vscode-200.sandbox.yourdomain.com
```

---

## Related Files

- `apps/www/lib/utils/pve-lxc-client.ts` - PVE LXC client
- `apps/www/lib/utils/sandbox-instance.ts` - Unified sandbox interface
- `scripts/snapshot-pvelxc.py` - PVE template builder

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Cloudflare Zero Trust Access](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [Cloudflare Wildcard DNS](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/)
- [Homelab with Cloudflare Tunnels](https://itsfoss.com/cloudflare-tunnels/)
- [Zero Trust Homelab Setup](https://netsecops.blog/2024/12/20/zero-trust-homelab-setup-with-cloudflare/)
- [Cloudflare vs Tailscale vs ngrok](https://dev.to/mechcloud_academy/cloudflare-tunnel-vs-ngrok-vs-tailscale-choosing-the-right-secure-tunneling-solution-4inm)
- [PVE LXC Documentation](https://pve.proxmox.com/pve-docs/chapter-pct.html)
- [Morph Cloud HTTP Services](https://cloud.morph.so/docs/documentation/instances/http-services)
