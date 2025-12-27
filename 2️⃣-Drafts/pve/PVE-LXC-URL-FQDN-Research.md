# PVE LXC URL & FQDN Research

> Research on how to use hostnames/FQDNs instead of IP addresses for PVE LXC sandbox URLs in cmux.

## Problem

When spawning PVE LXC containers as sandboxes, service URLs were using raw IP addresses:
- `http://10.10.0.199:39378` (vscode)
- `http://10.10.0.199:39377` (worker)

Best practice is to use FQDNs for:
- Better readability
- DNS-based service discovery
- Easier production deployment with public domains

## Solution: Auto-detect Domain Suffix from PVE API

### PVE DNS API Endpoint

PVE provides DNS configuration via the API:

```bash
GET /api2/json/nodes/{node}/dns
```

Response:
```json
{
  "data": {
    "dns1": "10.10.0.1",
    "dns2": "1.1.1.1",
    "search": "lan"
  }
}
```

The `search` field contains the domain suffix (e.g., `lan`).

### Implementation

The `PveLxcClient` now:
1. Auto-fetches DNS config from PVE API on first use
2. Caches the domain suffix (lazy initialization)
3. Builds service URLs using hostname + domain suffix when available
4. Falls back to IP addresses if no search domain configured

**URL patterns:**
- With domain suffix: `http://cmux-200.lan:39378`
- Without (fallback): `http://10.10.0.199:39378`

**Hostname convention:** `cmux-{vmid}` (e.g., `cmux-200`)

### Key Code Changes (pve-lxc-client.ts)

```typescript
interface PveDnsConfig {
  search?: string;
  dns1?: string;
  dns2?: string;
  dns3?: string;
}

// In PveLxcClient class:
private domainSuffix: string | null = null;
private domainSuffixFetched: boolean = false;

private async getDomainSuffix(): Promise<string | null> {
  if (this.domainSuffixFetched) {
    return this.domainSuffix;
  }
  try {
    const node = await this.getNode();
    const dnsConfig = await this.apiRequest<PveDnsConfig>(
      "GET",
      `/api2/json/nodes/${node}/dns`
    );
    if (dnsConfig?.search) {
      this.domainSuffix = `.${dnsConfig.search}`;
    }
  } catch (error) {
    console.error("[PveLxcClient] Failed to fetch DNS config:", error);
  }
  this.domainSuffixFetched = true;
  return this.domainSuffix;
}
```

---

## PVE v8/v9 LXC Production Setup Guide

### PVE Version Differences

| Feature | PVE 7.x | PVE 8.x (Debian 12) | PVE 9.x |
|---------|---------|---------------------|---------|
| **cgroups** | v1/v2/hybrid | v2 (default) | v2 only |
| **cpuunits default** | 1024 | 100 (cgroup v2) | 100 |
| **File system quotas** | Supported | Limited | Not supported |
| **OCI containers** | No | Tech preview | Supported |
| **systemd min version** | 219+ | 231+ | 231+ |

### cgroups v2 Changes (PVE 8+)

PVE 8 uses cgroups v2 by default. Key differences:

```bash
# Memory and swap are now controlled independently
# In cgroup v1: only memory.limit_in_bytes and memory.memsw.limit_in_bytes
# In cgroup v2: memory.max and memory.swap.max (direct mapping)

# Check current cgroup mode
cat /sys/fs/cgroup/cgroup.controllers

# Container systemd version requirements for cgroup v2:
# - systemd >= 231 required
# - CentOS 7, Ubuntu 16.10 and older are NOT compatible
```

### Container Types

#### Unprivileged Containers (Recommended for Production)

```bash
# Create unprivileged container from template
pct create 200 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --hostname cmux-200 \
  --unprivileged 1 \
  --features nesting=1 \
  --cores 4 \
  --memory 6144 \
  --swap 512 \
  --rootfs local-zfs:32 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --ostype debian

# Security benefits:
# - Root UID 0 inside maps to unprivileged user outside
# - AppArmor profiles enforced
# - Kernel namespace isolation
# - Reduced attack surface
```

#### Privileged Containers (Only for Trusted Environments)

```bash
# Create privileged container (NOT recommended for production)
pct create 201 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --hostname cmux-201 \
  --unprivileged 0 \
  --cores 4 \
  --memory 4096 \
  --rootfs local-zfs:16

# Use cases:
# - Running Docker inside LXC (requires nesting)
# - Legacy applications requiring root
# - File system quotas (ext4 only)
```

### Resource Management

#### CPU Configuration

```bash
# Set CPU cores (visible CPUs via cpuset cgroup)
pct set 200 --cores 4

# Set CPU limit (percentage of assigned cores)
pct set 200 --cpulimit 2  # Max 200% of single core

# Set CPU weight (relative priority)
# cgroup v2: 1-10000, default 100
# Higher = more priority
pct set 200 --cpuunits 200
```

#### Memory Configuration

```bash
# Set memory limit (MB)
pct set 200 --memory 6144

# Set swap limit (MB) - independent in cgroup v2
pct set 200 --swap 512

# Example: 6GB RAM + 512MB swap
pct set 200 --memory 6144 --swap 512
```

### Storage Configuration

#### Root Filesystem

```bash
# Thin-provisioned on ZFS
pct set 200 --rootfs local-zfs:32

# Or on LVM-thin
pct set 200 --rootfs local-lvm:32

# Example config line in /etc/pve/lxc/200.conf:
rootfs: local-zfs:subvol-200-disk-0,size=32G
```

#### Mount Points

```bash
# Storage-backed mount point (managed by PVE)
pct set 200 -mp0 local-zfs:10,mp=/data

# Bind mount (host directory -> container)
pct set 200 -mp0 /mnt/shared,mp=/shared

# Device mount (block device)
pct set 200 -mp0 /dev/sdb1,mp=/mnt/disk
```

### Networking Configuration

```bash
# DHCP
pct set 200 --net0 name=eth0,bridge=vmbr0,ip=dhcp

# Static IP
pct set 200 --net0 name=eth0,bridge=vmbr0,ip=10.10.0.200/24,gw=10.10.0.1

# With VLAN tag
pct set 200 --net0 name=eth0,bridge=vmbr0,tag=100,ip=dhcp

# With rate limiting (Mbps)
pct set 200 --net0 name=eth0,bridge=vmbr0,ip=dhcp,rate=100

# With firewall enabled
pct set 200 --net0 name=eth0,bridge=vmbr0,ip=dhcp,firewall=1

# Full network config format:
# net[n]: name=<string>[,bridge=<bridge>][,firewall=<1|0>]
#         [,gw=<GatewayIPv4>][,gw6=<GatewayIPv6>]
#         [,hwaddr=<XX:XX:XX:XX:XX:XX>][,ip=<IPv4/CIDR|dhcp|manual>]
#         [,ip6=<IPv6/CIDR|auto|dhcp|manual>][,mtu=<integer>]
#         [,rate=<mbps>][,tag=<integer>][,type=<veth>]
```

### Container Templates

#### Creating a Template

```bash
# 1. Create and configure a container
pct create 9000 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --hostname template-base \
  --unprivileged 1 \
  --features nesting=1 \
  --cores 4 \
  --memory 4096 \
  --rootfs local-zfs:16 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp

# 2. Start and customize
pct start 9000
pct enter 9000
# ... install packages, configure services ...
exit

# 3. Stop and convert to template
pct stop 9000
pct template 9000

# Template config flag in /etc/pve/lxc/9000.conf:
template: 1
```

#### Cloning from Template

```bash
# Linked clone (fast, copy-on-write, requires ZFS/LVM-thin)
pct clone 9000 200 --hostname cmux-200 --full 0

# Full clone (independent copy)
pct clone 9000 200 --hostname cmux-200 --full 1

# Clone with target storage
pct clone 9000 200 --hostname cmux-200 --storage local-zfs

# Clone to different node (requires shared storage)
pct clone 9000 200 --hostname cmux-200 --target node2

# Clone from snapshot
pct clone 9000 200 --hostname cmux-200 --snapname base-snapshot
```

#### Clone API (REST)

```http
POST /api2/json/nodes/{node}/lxc/{vmid}/clone

Parameters:
- newid: integer (required) - New VMID
- hostname: string - New hostname
- full: boolean - Full clone (default: false for templates)
- storage: string - Target storage
- target: string - Target node
- snapname: string - Source snapshot name
- pool: string - Resource pool
- description: string - Container description
- bwlimit: number - I/O bandwidth limit (KiB/s)
```

### Container Lifecycle Commands

```bash
# Create from template
pct create 200 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst

# Start/Stop/Restart
pct start 200
pct stop 200
pct restart 200
pct shutdown 200  # Graceful shutdown

# Suspend/Resume (freeze)
pct suspend 200
pct resume 200

# Enter container namespace
pct enter 200

# Execute command in container
pct exec 200 -- bash -c 'apt update && apt upgrade -y'

# Delete container
pct destroy 200

# List containers
pct list

# Show config
pct config 200

# Clone
pct clone 200 201 --hostname cmux-201

# Migrate (offline only for LXC)
pct migrate 200 node2

# Create snapshot
pct snapshot 200 snap1 --description "Before upgrade"

# Restore snapshot
pct rollback 200 snap1

# Delete snapshot
pct delsnapshot 200 snap1
```

### Startup Configuration

```bash
# Enable auto-start on boot
pct set 200 --onboot 1

# Set startup order and delays
pct set 200 --startup order=10,up=60,down=30

# Format: order=<N>,up=<seconds>,down=<seconds>
# - order: Boot priority (lower = earlier)
# - up: Delay after starting (seconds)
# - down: Delay before stopping (seconds)
```

### Security Best Practices

```bash
# 1. Use unprivileged containers
--unprivileged 1

# 2. Enable AppArmor (default, don't disable)
# AppArmor profile: /etc/apparmor.d/lxc/lxc-default-cgns

# 3. Limit features
--features nesting=0,keyctl=0,fuse=0

# 4. Enable firewall
--net0 ...,firewall=1

# 5. Resource limits
--cpulimit 4 --memory 8192

# 6. Avoid bind mounts to system directories
# BAD: -mp0 /etc,mp=/host-etc
# GOOD: -mp0 /mnt/data,mp=/data

# 7. For Docker inside LXC (if needed)
--unprivileged 1 --features nesting=1,keyctl=1
```

### Example Container Config (/etc/pve/lxc/200.conf)

```ini
arch: amd64
cores: 4
features: nesting=1
hostname: cmux-200
memory: 6144
net0: name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:XX:XX:XX,ip=dhcp,type=veth
onboot: 1
ostype: debian
rootfs: local-zfs:subvol-200-disk-0,size=32G
startup: order=10,up=30
swap: 512
unprivileged: 1
```

---

## Deep Comparison: Morph Cloud vs PVE LXC

### Architecture Overview

| Feature | Morph Cloud | PVE LXC |
|---------|-------------|---------|
| **Isolation** | Full VM (morphvm) | LXC Container |
| **Snapshot** | RAM state capture | Filesystem snapshot (linked-clone) |
| **Provider** | Cloud-hosted SaaS | Self-hosted on-premise |
| **Networking** | Managed overlay network | Bridge network (vmbr0) |
| **cgroups** | Managed | cgroups v2 (PVE 8+) |

### URL & Service Exposure

#### Morph Cloud (Cloud-hosted)

Morph provides **automatic public subdomain URLs** per exposed port via the `exposeHttpService()` API:

```typescript
// Morph SDK
const service = await instance.exposeHttpService("my-service", 8080);
console.log(service.url);
// Output: https://my-service-morphvm-abc123.http.cloud.morph.so
```

**URL Pattern:**
```
https://{service-name}-morphvm-{instanceId}.http.cloud.morph.so
```

**Key Features:**
- Automatic public domain per service
- HTTPS with SSL termination (managed certificates)
- Built-in reverse proxy
- No DNS configuration needed
- API key authentication support (`--auth-mode api_key`)
- Wake-on-HTTP: Instance can auto-resume when URL is accessed

**API Methods:**
```typescript
// Expose service
instance.exposeHttpService(name: string, port: number): Promise<HttpService>

// List services
instance.networking.http_services.forEach(service => {
  console.log(service.name, service.url, service.port);
});

// Hide service
instance.hideHttpService(name: string): Promise<void>
```

#### PVE LXC (Self-hosted)

Current implementation uses **direct hostname:port access**:

```typescript
// PVE LXC Client
await instance.exposeHttpService("vscode", 39378);
console.log(instance.networking.httpServices[0].url);
// Output: http://cmux-200.lan:39378
```

**URL Pattern:**
```
http://cmux-{vmid}.{domain-suffix}:{port}
```

**Key Features:**
- Direct container access (no reverse proxy)
- Requires DNS resolution (mDNS, local DNS, or /etc/hosts)
- HTTP only (no automatic SSL)
- LAN access only by default
- No authentication layer
- No wake-on functionality

**Current Implementation:**
```typescript
// pve-lxc-client.ts
async exposeHttpService(name: string, port: number): Promise<void> {
  const host = this.networking.fqdn || this.networking.ipAddress;
  const url = `http://${host}:${port}`;
  this.networking.httpServices.push({ name, port, url });
}
```

### Comparison Table: Service Exposure

| Feature | Morph Cloud | PVE LXC |
|---------|-------------|---------|
| **URL Format** | `https://{name}-morphvm-{id}.http.cloud.morph.so` | `http://cmux-{vmid}.lan:{port}` |
| **Protocol** | HTTPS (automatic SSL) | HTTP only |
| **DNS** | Managed (*.http.cloud.morph.so) | Local DNS/mDNS required |
| **Access** | Public internet | LAN only |
| **Auth** | API key, public, or none | None |
| **Reverse Proxy** | Built-in | None |
| **Wake-on-HTTP** | Yes | No |
| **Multiple Ports** | Multiple subdomains | Direct port access |

### Instance Lifecycle Comparison

| Operation | Morph Cloud | PVE LXC |
|-----------|-------------|---------|
| **Create** | `client.instances.start({ snapshotId })` | `client.instances.start({ snapshotId })` |
| **Stop** | `instance.stop()` | `instance.stop()` |
| **Pause** | `instance.pause()` | `instance.pause()` (freeze) |
| **Resume** | `instance.resume()` | `instance.resume()` |
| **Snapshot** | `instance.snapshot()` (captures RAM) | Linked-clone from template |
| **Branch** | `instance.branch(count)` | Not implemented |
| **Exec** | `instance.exec(command)` | `instance.exec(command)` |

### Exec Command Comparison

**Morph Cloud:**
```typescript
const result = await instance.exec("cat /root/counter.txt");
console.log(result.stdout);
```

**PVE LXC:**
```typescript
// Tries HTTP exec (cmux-execd on port 39375) first, falls back to SSH+pct
const result = await instance.exec("cat /root/counter.txt");
console.log(result.stdout);
```

PVE LXC uses a two-tier execution strategy:
1. **HTTP exec** via `cmux-execd` daemon (port 39375) - fast, direct
2. **SSH fallback** via `pct exec` - slower, requires SSH access to PVE host

---

## Future: Public URL Support for PVE LXC

To achieve Morph-like public URLs for PVE LXC, you would need:

### Option A: Reverse Proxy with Dynamic Subdomains

1. **Wildcard DNS**: `*.sandbox.yourdomain.com` -> PVE host
2. **Reverse proxy** (Caddy/Traefik) with pattern matching:
   ```
   {service}-{vmid}.sandbox.yourdomain.com -> cmux-{vmid}.lan:{port}
   ```
3. **Automatic SSL** via Let's Encrypt

**Example Caddy configuration:**
```caddyfile
*.sandbox.yourdomain.com {
  tls {
    dns cloudflare {env.CF_API_TOKEN}
  }

  @vscode host vscode-*.sandbox.yourdomain.com
  handle @vscode {
    reverse_proxy cmux-{re.vscode.1}.lan:39378
  }

  @worker host worker-*.sandbox.yourdomain.com
  handle @worker {
    reverse_proxy cmux-{re.worker.1}.lan:39377
  }
}
```

**Resulting URLs:**
```
https://vscode-200.sandbox.yourdomain.com -> cmux-200.lan:39378
https://worker-200.sandbox.yourdomain.com -> cmux-200.lan:39377
```

### Option B: Cloudflare Tunnel / SSH Tunnel

Use `cloudflared` or similar to expose containers without opening firewall ports:

```bash
cloudflared tunnel --url http://cmux-200.lan:39378
# Returns: https://random-words.trycloudflare.com
```

For persistent tunnels:
```yaml
# cloudflared config
tunnel: my-tunnel
credentials-file: /root/.cloudflared/credentials.json
ingress:
  - hostname: vscode-200.sandbox.yourdomain.com
    service: http://cmux-200.lan:39378
  - hostname: worker-200.sandbox.yourdomain.com
    service: http://cmux-200.lan:39377
  - service: http_status:404
```

### Option C: Tailscale / ZeroTier

Use a mesh VPN for secure access without public exposure:
```bash
# On PVE host
tailscale up --accept-routes --advertise-routes=10.10.0.0/24

# Access from any device on tailnet
curl http://cmux-200.lan:39378
```

### Implementation Considerations

For cmux, adding public URL support would require:

1. **New environment variables:**
   ```
   PVE_PUBLIC_DOMAIN=sandbox.yourdomain.com
   PVE_URL_PATTERN={service}-{vmid}.{domain}
   PVE_PROXY_TYPE=caddy|cloudflare|none
   ```

2. **Update `buildServiceUrl()` in pve-lxc-client.ts:**
   ```typescript
   private buildServiceUrl(
     hostname: string | undefined,
     ipAddress: string | undefined,
     port: number,
     domainSuffix: string | null,
     serviceName?: string
   ): string {
     // Check for public domain configuration
     if (env.PVE_PUBLIC_DOMAIN && serviceName) {
       const vmid = hostname?.replace('cmux-', '');
       return `https://${serviceName}-${vmid}.${env.PVE_PUBLIC_DOMAIN}`;
     }

     // Fall back to local access
     if (hostname && domainSuffix) {
       return `http://${hostname}${domainSuffix}:${port}`;
     }
     if (ipAddress) {
       return `http://${ipAddress}:${port}`;
     }
     throw new Error("No hostname or IP address available");
   }
   ```

3. **SSL/TLS consideration:**
   - Browser security context requires HTTPS for many features
   - Service workers, clipboard API, etc. require secure context
   - Morph handles this automatically; PVE requires manual setup

---

## Related Files

- `apps/www/lib/utils/pve-lxc-client.ts` - Main PVE LXC client implementation
- `apps/www/lib/utils/www-env.ts` - Environment configuration
- `apps/www/lib/routes/sandboxes.route.ts` - Sandbox API routes
- `apps/www/lib/utils/sandbox-instance.ts` - Unified sandbox interface
- `apps/client/src/lib/workspace-url.ts` - Client-side URL handling

## References

- [PVE API Docs](https://pve.proxmox.com/pve-docs/api-viewer/)
- [PVE API Wiki](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- [PVE LXC Container Documentation](https://pve.proxmox.com/pve-docs/chapter-pct.html)
- [PVE pct Command Reference](https://pve.proxmox.com/pve-docs/pct.1.html)
- [PVE Container Configuration](https://pve.proxmox.com/pve-docs/pct.conf.5.html)
- [Morph Cloud Docs - HTTP Services](https://cloud.morph.so/docs/documentation/instances/http-services)
- [Morph Cloud Docs - Instance Lifecycle](https://cloud.morph.so/docs/documentation/instances/basic-lifecycle)
- [Morph Cloud Docs - Wake-on](https://cloud.morph.so/docs/documentation/instances/wake-on)
- [Caddy Reverse Proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
