# cmux Cost Reduction Roadmap

> **Target**: 70-85% cost reduction, aiming for <$300/mo total
> **Timeline**: 2-4 months phased approach
> **Last Updated**: 2025-12-30
>
> [!warning] Critical Correction (Dec 2025)
> Previous versions incorrectly claimed Proxmox LXC supports CRIU checkpoint/restore. **This is NOT true** - see "RAM Snapshot Support" section for corrected information.

---

## Executive Summary

| Priority | Service | Current | Alternative | Est. Alt Cost | Savings | Risks | Code Changes |
|----------|---------|---------|-------------|---------------|---------|-------|--------------|
| 1 | Morph Sandboxes | $$$$ (~$200-500/mo) | **Multi-Provider**: Proxmox (primary) + Morph (fallback) | $50-300/mo | 70-90% | Setup complexity; RAM snapshot parity | Medium-High |
| 2 | AI Provider APIs | $$$ (token-heavy) | OpenRouter, Together AI, Ollama/vLLM | $0-150/mo | 60-95% | Model quality drop with locals; latency | Low |
| 3 | Convex Database | $$ | Self-host Docker (already supported) | $20-60/mo | 60-80% | Data migration; real-time sync testing | Minimal |
| 4 | Edge Router | $ | Nginx/Caddy, Traefik | $10-30/mo | 50-70% | WebSocket support for VNC/CDP | Medium |
| 5 | Frontend Hosting | Free/$ | Cloudflare Pages, Netlify | $0-20/mo | Minimal | CI/CD integration | Minimal |
| 6 | Backend Server | $$ | Docker on VPS, Fly.io, Railway | $20-100/mo | 40-60% | Scalability for traffic spikes | Minimal |

---

## Detailed Cost Analysis

### 1. Morph Cloud Sandboxes (HIGH COST - Priority 1)

**Current**: `MORPH_API_KEY` - https://cloud.morph.so/web/subscribe
- Provisions isolated dev environments for coding agents
- Each instance: CPU, memory, disk allocation
- Exposed ports: OpenVSCode (39378), worker (39377), proxy (39379), VNC (39380), CDP (39381)
- TTL-based billing with pause/stop actions
- Snapshot management for different presets
- **Est. Cost**: $200-500+/mo for 5-10 concurrent sandboxes @ $0.05-0.10/hour

**Self-Host Alternatives (Evaluated Dec 2025)**:

> **CRITICAL REQUIREMENT: RAM Snapshot / VM Suspend-Resume**
> Morph Cloud's RAM snapshot capability is essential for cmux workflows - preserving running processes, loaded variables, and memory state across pause/resume cycles. Any replacement MUST support this.

| Option | Isolation | Startup | RAM Snapshot | Self-Deploy | Est. Cost | Recommendation |
|--------|-----------|---------|--------------|-------------|-----------|----------------|
| **Proxmox VE/VM (KVM)** | Full VM | ~2-5s | **Yes (`qm suspend --todisk`)** | Medium | $50-200/mo | **PRIMARY - proven RAM snapshot** |
| **Firecracker/Kata** | MicroVM | ~125-200ms | **Yes (native)** | High | $50-200/mo | Alternative for K8s integration |
| **Morph Cloud** | MicroVM | ~10-20s | **Yes (native)** | N/A (SaaS) | $200-500/mo | **FALLBACK - keep enabled** |
| Proxmox LXC | Container | ~100ms | **No (disk only)** | Medium | $50-200/mo | Fast startup, no RAM snapshot |
| Local Docker | Container | <50ms | No (CRIU experimental) | High | $0 (dev only) | Dev/testing only |

> **Note**: e2b, microsandbox, Daytona evaluated but not in implementation plan. See Appendix for comparison.

---

### RAM Snapshot Support Comparison (CRITICAL)

> [!danger] Proxmox LXC + CRIU Correction
> **`pct checkpoint` and `pct restore` commands DO NOT EXIST in Proxmox VE.**
> CRIU integration with Proxmox LXC is experimental only, not production-ready.
> See [Proxmox Forum](https://forum.proxmox.com/tags/criu/) and [CRIU GitHub Issue #1430](https://github.com/checkpoint-restore/criu/issues/1430).

| Platform               | RAM Snapshot Method     | Process Resume | API Support                      |
| ---------------------- | ----------------------- | -------------- | -------------------------------- |
| **Morph Cloud**        | Native VM snapshot      | **Yes**        | `pause()` / `resume()`           |
| **Proxmox VM (KVM)**   | QEMU suspend-to-disk    | **Yes**        | `qm suspend ID --todisk` / `qm resume ID` |
| **Firecracker**        | Memory file snapshot    | **Yes**        | `/snapshot/create` / `/snapshot/load` |
| **Kata Containers**    | Cloud-Hypervisor/QEMU   | **Yes**        | `VmSnapshotPut` / `VmRestorePut` |
| **e2b**                | Firecracker snapshot    | **Yes**        | `betaPause()` / `connect()`      |
| Proxmox LXC            | Disk snapshot only      | **No**         | `pct snapshot` (NO RAM)          |
| microsandbox           | None                    | **No**         | start/stop only                  |
| Docker + CRIU          | Experimental            | Unreliable     | `docker checkpoint` (not production-ready) |

---

### Option A: Proxmox KVM/QEMU VMs (RECOMMENDED for Self-Host)

> [!info] Why KVM VMs instead of LXC?
> **Proxmox LXC does NOT support CRIU checkpoint/restore** - the `pct checkpoint` command does not exist.
> Only Proxmox KVM/QEMU VMs support RAM snapshots via `qm suspend --todisk`.

**Why Proxmox KVM is the best self-hosted choice:**
1. **RAM snapshot via QEMU suspend-to-disk** - Saves full memory state to disk, resumes processes
2. **Mature & battle-tested** - You have good experience with Proxmox
3. **Full isolation** - Hardware-level VM isolation (more secure than containers)
4. **Full Linux compatibility** - No compatibility issues
5. **Cost effective** - Hetzner/DO VPS $20-50/mo (requires nested virt support)
6. **Rich API** - Proxmox REST API for automation

**RAM Snapshot Commands (VERIFIED):**
```bash
# Suspend VM (saves RAM to disk) - VERIFIED COMMAND
qm suspend <vmid> --todisk

# Resume VM (loads RAM from disk, processes continue)
qm resume <vmid>

# Note: LXC snapshots do NOT preserve RAM
pct snapshot <vmid> <name>    # Disk only, NO RAM state
pct rollback <vmid> <name>    # Restores disk, processes don't resume
```

**Proxmox API for cmux integration:**
```typescript
// packages/shared/src/sandbox-providers/proxmox.ts
export class ProxmoxProvider implements SandboxProvider {
  async pauseInstance(id: string): Promise<void> {
    // KVM suspend-to-disk - preserves RAM state
    await this.api.post(`/nodes/${node}/qemu/${id}/status/suspend`, {
      todisk: true
    });
  }

  async resumeInstance(id: string): Promise<void> {
    // KVM resume - loads RAM from disk, processes continue
    await this.api.post(`/nodes/${node}/qemu/${id}/status/resume`);
  }
}
```

**Trade-off: Startup Time**
- KVM VMs: ~2-5s startup (slower than LXC ~100ms)
- RAM resume: ~2-5s (loads memory from disk)
- For faster startup without RAM snapshot: Use LXC (but lose process state)

---

### Resilient Multi-Provider Architecture

> **Design Goal**: Keep Morph as original provider, add Proxmox KVM as self-hosted replacement, support fallback and hybrid routing.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SandboxProviderManager                           │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Routing Strategy:                                            │  │
│  │  - primary: "pve-lxc" | "morph"                               │  │
│  │  - fallback: ["morph"]                                        │  │
│  │  - workloadRouting: { dev: "pve-lxc", prod: "morph" }         │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│              ┌───────────────┴───────────────┐                      │
│              ▼                               ▼                      │
│       ┌─────────────┐                 ┌─────────────┐               │
│       │MorphProvider│                 │ProxmoxProv. │               │
│       │ (original)  │                 │ (KVM VMs)   │               │
│       └─────────────┘                 └─────────────┘               │
└─────────────────────────────────────────────────────────────────────┘
```

**Provider Interface (unified for all providers):**
```typescript
// packages/shared/src/sandbox-providers/types.ts
export interface SandboxProvider {
  readonly name: string;
  readonly supportsRamSnapshot: boolean;

  // Lifecycle
  startInstance(config: SandboxConfig): Promise<SandboxInstance>;
  stopInstance(id: string): Promise<void>;

  // RAM Snapshot (CRITICAL)
  pauseInstance(id: string): Promise<void>;   // Save RAM state
  resumeInstance(id: string): Promise<void>;  // Restore RAM state

  // Status
  getInstanceStatus(id: string): Promise<SandboxStatus>;
  listInstances(): Promise<SandboxInstance[]>;

  // Health check for fallback
  healthCheck(): Promise<boolean>;
}

export interface SandboxConfig {
  preset: string;
  workloadType?: "dev" | "prod" | "ephemeral";
  preferredProvider?: string;  // Override routing
}
```

**Multi-Provider Manager with Fallback:**
```typescript
// packages/shared/src/sandbox-providers/manager.ts
export class SandboxProviderManager {
  private providers: Map<string, SandboxProvider> = new Map();
  private config: ProviderConfig;

  constructor(config: ProviderConfig) {
    this.config = config;

    // Register available providers (Proxmox + Morph only)
    if (config.morph?.enabled) {
      this.providers.set("morph", new MorphProvider(config.morph));
    }
    if (config.proxmox?.enabled) {
      this.providers.set("pve-lxc", new ProxmoxProvider(config.proxmox));
    }
  }

  async getProvider(config: SandboxConfig): Promise<SandboxProvider> {
    // 1. Check explicit override
    if (config.preferredProvider) {
      const provider = this.providers.get(config.preferredProvider);
      if (provider && await provider.healthCheck()) {
        return provider;
      }
    }

    // 2. Route by workload type
    const routedProvider = this.config.workloadRouting?.[config.workloadType];
    if (routedProvider) {
      const provider = this.providers.get(routedProvider);
      if (provider && await provider.healthCheck()) {
        return provider;
      }
    }

    // 3. Try primary provider
    const primary = this.providers.get(this.config.primary);
    if (primary && await primary.healthCheck()) {
      return primary;
    }

    // 4. Fallback chain
    for (const fallbackName of this.config.fallback) {
      const fallback = this.providers.get(fallbackName);
      if (fallback && await fallback.healthCheck()) {
        console.warn(`Primary provider unavailable, using fallback: ${fallbackName}`);
        return fallback;
      }
    }

    throw new Error("No healthy sandbox provider available");
  }

  // Unified API - delegates to appropriate provider
  async startInstance(config: SandboxConfig): Promise<SandboxInstance> {
    const provider = await this.getProvider(config);
    const instance = await provider.startInstance(config);
    return { ...instance, provider: provider.name };
  }

  async pauseInstance(id: string, provider?: string): Promise<void> {
    const p = this.providers.get(provider || this.getProviderForInstance(id));
    if (!p?.supportsRamSnapshot) {
      throw new Error(`Provider ${p?.name} does not support RAM snapshots`);
    }
    await p.pauseInstance(id);
  }
}
```

**Environment Configuration (Current vs Planned):**
```env
# Current (implemented)
SANDBOX_PROVIDER=pve-lxc   # or morph
MORPH_API_KEY=xxx
PVE_API_URL=https://pve.example.com:8006
PVE_API_TOKEN=xxx
PVE_NODE=pve1

# Planned (not implemented yet)
# SANDBOX_PRIMARY_PROVIDER=proxmox
# SANDBOX_FALLBACK_PROVIDERS=morph
# SANDBOX_ROUTE_DEV=proxmox
# SANDBOX_ROUTE_PROD=morph
# PROXMOX_USE_KVM=true
```

**Migration Strategy (Proxmox + Morph):**
```
Phase 1: Morph only (current)
  SANDBOX_PRIMARY_PROVIDER=morph
  SANDBOX_FALLBACK_PROVIDERS=

Phase 2: Proxmox primary, Morph fallback
  SANDBOX_PRIMARY_PROVIDER=proxmox
  SANDBOX_FALLBACK_PROVIDERS=morph
  SANDBOX_ROUTE_PROD=morph  # Keep prod on Morph initially

Phase 3: Proxmox for all, Morph for emergency
  SANDBOX_PRIMARY_PROVIDER=proxmox
  SANDBOX_FALLBACK_PROVIDERS=morph
  SANDBOX_ROUTE_PROD=proxmox

Phase 4: Proxmox primary + Morph resilience (final state)
  SANDBOX_PRIMARY_PROVIDER=proxmox
  SANDBOX_FALLBACK_PROVIDERS=morph  # Keep forever for resilience
```

**Security Note** (from sandboxing research):
- KVM VMs provide hardware-level isolation (more secure than containers)
- Containers share kernel = potential escape vulnerabilities (69% of incidents are misconfigs)
- LXC with proper seccomp/AppArmor provides strong isolation for trusted environments (but NO RAM snapshot)
- For untrusted code requiring MicroVM isolation, see comparison table in Appendix

**Improvements**:
- **Primary**: Implement Proxmox provider with KVM VMs for self-hosted production
- **Hybrid approach**: Proxmox KVM primary + Morph fallback for resilience
- Target RAM resume latency: ~2-5s with KVM suspend-to-disk
- Create `SandboxProvider` abstraction layer supporting Proxmox + Morph
- RAM snapshots: `qm suspend --todisk` for full process state preservation

**Code Changes Required**: Medium-High (API integration + provider abstraction)

---

### 2. AI Provider APIs (HIGH COST - Priority 2)

**Current Keys**:
- `ANTHROPIC_API_KEY` - Claude for coding agents (main cost driver)
- `OPENAI_API_KEY` - PR heatmap reviews, code analysis
- `GOOGLE_API_KEY` - Gemini CLI support

**Why High Cost**: Coding agents consume massive tokens per session (context windows, multi-turn conversations, code generation)

**Third-Party API Proxies (Claude/OpenAI Compatible)**:

| Provider | Claude Support | OpenAI Compat | Pricing | Notes |
|----------|---------------|---------------|---------|-------|
| OpenRouter | Yes | Yes | 10-30% cheaper | Multi-provider routing |
| Together AI | No | Yes | Competitive | Strong open models |
| Fireworks AI | No | Yes | Fast inference | Good for coding |
| Groq | No | Yes | Ultra-fast | Limited model selection |
| DeepInfra | No | Yes | Cheap | Open model hosting |
| Mistral AI | No | Yes | EU-compliant | Strong coding models (2025) |
| Perplexity Labs | No | Yes | Knowledge-grounded | Fast responses |

**Self-Hosted / Local LLMs**:
- Ollama + DeepSeek/Qwen - Zero cost after hardware
- vLLM cluster - Production-grade self-hosted
- llama.cpp - CPU fallback
- GPU instance: AWS g4dn ~$100-200/mo if no local hardware

**Implementation: Base URL Override**
```env
# Override API endpoints to use third-party providers
ANTHROPIC_BASE_URL=https://openrouter.ai/api/v1
OPENAI_BASE_URL=https://api.together.xyz/v1
OLLAMA_BASE_URL=http://localhost:11434/v1
```

**Improvements**:
- **Hybrid routing**: Route based on task complexity
  - Local: commit messages, branch names, simple reviews
  - Cloud: agent sessions, complex multi-file reviews
- **Token optimization**: Implement prompt compression (LLMLingua) for 30-50% reduction
- **Response caching**: Redis integration for common queries
- **Fallback logic**: Extend `getModelAndProvider` to fallback cloud if local fails
- **Token budgeting**: Cap spends per session via LangChain-style limits
- Test Qwen 3 (2025 release) for improved local performance

**Code Changes Required**: Low (base URL env vars + hybrid logic)

---

### 3. Convex Database (MEDIUM COST - Priority 3)

**Current**: `CONVEX_DEPLOY_KEY` - Convex Cloud
- Stores: repos, teams, users, environments, PRs, provider connections
- Real-time subscriptions
- Optimistic updates

**Self-Host Alternative** (already supported!):
```yaml
services:
  convex-backend:
    image: ghcr.io/get-convex/convex-backend
  convex-dashboard:
    image: ghcr.io/get-convex/convex-dashboard
```

**Improvements**:
- Add backup automation (cron to S3-compatible storage like Backblaze, $5/TB)
- For high traffic: cluster Convex backend (multi-container)
- Use Convex export/import tools for zero-downtime migration
- Monitor real-time sync performance for 1 week before full switch

**Production Deployment**:
1. Deploy Docker Compose to VPS/cloud VM
2. Configure persistent volumes for data
3. Set up backup strategy (daily snapshots)
4. Update `CONVEX_DEPLOY_KEY` to point to self-hosted instance
5. Configure SSL/TLS termination

**Code Changes Required**: Minimal - infrastructure config only

---

### 4. Cloudflare Workers / Edge Router (LOW COST - Priority 4)

**Current**: `apps/edge-router` - handles `*.cmux.sh` and `*.cmux.app` wildcard proxying
- Routes `port-<port>-<vmSlug>.cmux.sh` to Morph instances
- CORS and header management
- Loop prevention with `X-Cmux-*` headers

**Self-Host Alternatives**:

| Option | WebSocket Support | Complexity | Notes |
|--------|-------------------|------------|-------|
| Nginx + Lua | Yes (with module) | Medium | Most mature |
| Caddy | Native | Low | Easiest config |
| Traefik | Native | Medium | K8s-friendly |
| Envoy Proxy | Native | High | Advanced routing |

**Improvements**:
- Confirm WebSocket requirement for VNC/CDP (likely yes)
- Keep Cloudflare for DNS/wildcards to minimize changes
- Integrate Prometheus monitoring for loop detection
- Add Envoy as option for advanced routing needs

**Nginx config example:**
```nginx
server {
    listen 443 ssl;
    server_name ~^port-(?<port>\d+)-(?<vmSlug>[^.]+)\.cmux\.sh$;

    location / {
        proxy_pass http://$vmSlug.internal:$port;
        proxy_set_header X-Cmux-Original-Host $host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        # CORS headers...
    }
}
```

**Code Changes Required**: Medium - rewrite edge router logic

---

### 5. Frontend Hosting (FREE/LOW COST - Priority 5)

**Current**: Vercel
- `cmux-client` - frontend
- `cmux-www` - marketing/docs

**Self-Host Alternatives**:
- Cloudflare Pages (free tier generous, dynamic support)
- GitHub Pages (if static)
- Netlify
- Self-hosted Nginx

**Improvements**: Ensure CI/CD integration maintained

**Code Changes Required**: Minimal - static export or Node.js server

---

### 6. Backend Server (MEDIUM COST - Priority 6)

**Current**: `NEXT_PUBLIC_SERVER_ORIGIN` - apps/server (Hono backend)

**Self-Host Alternatives**:
- Docker container on VPS ($20-50/mo)
- Fly.io (cheaper than Vercel for API-heavy)
- Railway
- Render (interim option)

**Improvements**: Add auto-scaling for traffic spikes

**Code Changes Required**: Minimal - containerized already

---

## Implementation Roadmap

### Phase 1: Quick Wins (1-3 weeks)
| Step | Task | Owner | Status |
|------|------|-------|--------|
| 1.1 | Self-host Convex; test data sync; monitor 1 week | - | [ ] |
| 1.2 | Enable local Docker mode for dev; document setup | - | [ ] |
| 1.3 | Implement AI base URL overrides (`ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`) | - | [ ] |
| 1.4 | Test OpenRouter for 20-30% immediate AI savings | - | [ ] |
| 1.5 | Add AI optimizations (caching, token limits) | - | [ ] |
| 1.6 | **Gather metrics**: Answer open questions via logs/dashboards | - | [ ] |

### Phase 2: Medium Effort (3-6 weeks)
| Step | Task | Owner | Status |
|------|------|-------|--------|
| 2.1 | Set up local AI (Ollama + DeepSeek/Qwen models) | - | [ ] |
| 2.2 | Implement hybrid AI routing (local simple, cloud complex) | - | [ ] |
| 2.3 | Replace edge router with Nginx/Caddy; test WebSockets/CORS | - | [ ] |
| 2.4 | **Deploy Proxmox VE** on Hetzner VPS; configure KVM VMs | - | [ ] |
| 2.5 | Create `SandboxProvider` abstraction layer in cmux | - | [ ] |
| 2.6 | Test KVM `qm suspend --todisk` / `qm resume` with cmux services | - | [ ] |

### Phase 3: Core Migrations (6-10 weeks)
| Step | Task | Owner | Status |
|------|------|-------|--------|
| 3.1 | Implement `ProxmoxProvider` with KVM suspend/resume API parity | - | [ ] |
| 3.2 | Create cmux base KVM VM template (all services pre-installed) | - | [ ] |
| 3.3 | Test RAM snapshot: verify running processes resume correctly | - | [ ] |
| 3.4 | Migrate 20% -> 50% of sandbox workloads to Proxmox KVM | - | [ ] |
| 3.5 | Optimize frontend/backend hosting (Cloudflare Pages + VPS) | - | [ ] |

### Phase 4: Full Optimization & Monitoring (10-12 weeks)
| Step | Task | Owner | Status |
|------|------|-------|--------|
| 4.1 | Complete all migrations; rollback plans ready | - | [ ] |
| 4.2 | Set up monitoring (Prometheus/Grafana) and cost alerts | - | [ ] |
| 4.3 | ROI review: Track monthly savings; adjust based on actuals | - | [ ] |
| 4.4 | Documentation and runbooks for self-hosted infra | - | [ ] |

---

## Detailed Implementation Notes

### Morph Replacement with Proxmox KVM (Primary) or Firecracker/Kata (Alternative)

**Services to replicate inside each sandbox:**
1. `cmux-openvscode.service` - Web-based VS Code (port 39378)
2. `cmux-worker.service` - Core cmux worker
3. `cmux-proxy.service` - Proxy service (port 39379)
4. `cmux-dockerd.service` - Docker daemon (Docker-in-Docker or socket mount)
5. `cmux-devtools.service` - Development tools
6. `cmux-xvfb.service` - X virtual framebuffer (headless graphics)
7. `cmux-tigervnc.service` - VNC server (port 39380)
8. `cmux-vnc-proxy.service` - VNC proxy
9. `cmux-cdp-proxy.service` - Chrome DevTools Protocol proxy (port 39381)
10. `cmux-xterm.service` - Terminal access
11. `cmux-memory-setup.service` - Memory/swap configuration

**Key files to reference:**
- `scripts/snapshot.py` - Main snapshot automation (task graph approach)
- `scripts/morph_dockerfile.py` - Dockerfile-to-Morph translation
- `packages/shared/src/morph-snapshots.json` - Snapshot manifest

---

#### Option A: Proxmox KVM VMs (For RAM Snapshot / Full Workspace Resume)

**Use KVM VMs when:**
- Long-running tasks that need workspace pause/resume
- RAM snapshot is required (preserve running processes)
- Full isolation needed

**Proxmox KVM Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│  Host Server (Proxmox VE on Hetzner/DigitalOcean)          │
│  ├─ Proxmox API (:8006)                                    │
│  │   ├─ KVM/QEMU hypervisor                                │
│  │   └─ VM management (start, stop, suspend, resume)       │
│  └─ /var/lib/vz/ (VM disk images + suspend state)          │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  KVM VM Sandbox Instance                                    │
│  ├─ cmux-openvscode.service (port 39378)                   │
│  ├─ cmux-worker.service (port 39377)                       │
│  ├─ cmux-proxy.service (port 39379)                        │
│  ├─ cmux-tigervnc.service (port 39380)                     │
│  └─ cmux-cdp-proxy.service (port 39381)                    │
└─────────────────────────────────────────────────────────────┘
```

**KVM RAM Snapshot (VERIFIED):**
```bash
# Suspend VM (saves RAM to disk) - VERIFIED COMMAND
qm suspend <vmid> --todisk

# Resume VM (loads RAM from disk, processes continue)
qm resume <vmid>
```

**KVM Provider Implementation:**
```typescript
// packages/shared/src/sandbox-providers/proxmox-kvm.ts
export class ProxmoxKvmProvider implements SandboxProvider {
  readonly supportsRamSnapshot = true;  // KVM supports RAM snapshot

  async pauseInstance(id: string): Promise<void> {
    // Suspend VM to disk - saves full RAM state
    await this.api.post(`/nodes/${node}/qemu/${id}/status/suspend`, {
      todisk: true
    });
  }

  async resumeInstance(id: string): Promise<void> {
    // Resume VM - loads RAM from disk, processes continue
    await this.api.post(`/nodes/${node}/qemu/${id}/status/resume`);
  }
}
```

**Trade-offs:**
- Startup: ~2-5s (slower than LXC)
- RAM resume: ~2-5s (loading memory from disk)
- More resource overhead than containers

---

#### Option B: Proxmox LXC (For Short-Lived / Ephemeral Tasks)

> [!warning] LXC does NOT support RAM snapshots
> **`pct checkpoint` and `pct restore` commands DO NOT EXIST in Proxmox VE.**
> Use LXC only for short-lived tasks that don't require workspace resume.

**Use LXC when:**
- Short-lived tasks (no need to pause/resume)
- Fast startup is critical (~100ms)
- Ephemeral agent runs
- Cost optimization for high-volume, quick tasks

**What LXC CAN do:**
```bash
pct snapshot <vmid> <name>    # Disk snapshot only (NO RAM)
pct rollback <vmid> <name>    # Restore disk state (processes restart from scratch)
pct start/stop <vmid>         # Container lifecycle
pct clone <vmid> <newid>      # Clone from template
```

**What LXC CANNOT do:**
- `pct checkpoint` - DOES NOT EXIST
- `pct restore --state-file` - DOES NOT EXIST
- CRIU integration - NOT supported in Proxmox VE

**LXC Provider Implementation:**
```typescript
// packages/shared/src/sandbox-providers/proxmox-lxc.ts
export class ProxmoxLxcProvider implements SandboxProvider {
  readonly supportsRamSnapshot = false;  // LXC does NOT support RAM snapshot

  async startInstance(config: SandboxConfig): Promise<SandboxInstance> {
    // Clone from template for fast startup (~100ms)
    const newId = await this.api.post(`/nodes/${node}/lxc/${templateId}/clone`);
    await this.api.post(`/nodes/${node}/lxc/${newId}/status/start`);
    return { id: newId, ... };
  }

  async pauseInstance(id: string): Promise<void> {
    // LXC cannot preserve RAM - just stop the container
    // Processes will restart from scratch on resume
    await this.api.post(`/nodes/${node}/lxc/${id}/status/stop`);
    console.warn("LXC pause: RAM state NOT preserved. Processes will restart.");
  }

  async resumeInstance(id: string): Promise<void> {
    // Just restart the container - processes start fresh
    await this.api.post(`/nodes/${node}/lxc/${id}/status/start`);
  }
}
```

**Proxmox LXC Implementation Steps:**
1. Create base Ubuntu LXC template
2. Install dependencies: docker.io, docker-compose, git, curl, node, bun, uv
3. Build and install cmux services (worker, proxy binaries)
4. Install OpenVSCode server
5. Configure TigerVNC + xvfb
6. Create systemd units mirroring Morph setup
7. Configure networking (expose ports 39377-39381)
8. Convert to template: `pct template <vmid>`
9. Implement `ProxmoxLxcProvider` in cmux codebase

---

#### Hybrid Routing: KVM + LXC

**Route tasks to appropriate provider based on requirements:**

```typescript
// packages/shared/src/sandbox-providers/manager.ts
export class SandboxProviderManager {
  async getProvider(config: SandboxConfig): Promise<SandboxProvider> {
    // Route based on task type
    if (config.requiresRamSnapshot || config.workloadType === "long-running") {
      // Use KVM for tasks needing pause/resume
      return this.providers.get("proxmox-kvm");
    }

    if (config.workloadType === "ephemeral" || config.workloadType === "quick-task") {
      // Use LXC for fast startup, short-lived tasks
      return this.providers.get("proxmox-lxc");
    }

    // Default: KVM for safety (supports RAM snapshot)
    return this.providers.get("proxmox-kvm");
  }
}
```

**Environment Configuration:**
```env
# Hybrid Proxmox setup
PROXMOX_KVM_ENABLED=true     # For RAM snapshot tasks
PROXMOX_LXC_ENABLED=true     # For ephemeral/quick tasks
PROXMOX_DEFAULT=kvm          # Default to KVM (safer)

# Routing rules
SANDBOX_ROUTE_LONG_RUNNING=proxmox-kvm
SANDBOX_ROUTE_EPHEMERAL=proxmox-lxc
```

---

#### Provider Abstraction Layer

**Required API Changes:**
```typescript
// packages/shared/src/sandbox-providers/types.ts
export interface SandboxProvider {
  readonly name: string;
  readonly supportsRamSnapshot: boolean;  // Critical distinction!

  startInstance(config: SandboxConfig): Promise<SandboxInstance>;
  stopInstance(id: string): Promise<void>;
  pauseInstance(id: string): Promise<void>;
  resumeInstance(id: string): Promise<void>;
  getInstanceStatus(id: string): Promise<SandboxStatus>;
  listInstances(): Promise<SandboxInstance[]>;
}

// packages/shared/src/sandbox-providers/index.ts
export function getSandboxProvider(config?: SandboxConfig): SandboxProvider {
  const provider = config?.preferredProvider || process.env.SANDBOX_PROVIDER || "morph";

  switch (provider) {
    case "proxmox-kvm": return new ProxmoxKvmProvider();   // RAM snapshot: YES
    case "proxmox-lxc": return new ProxmoxLxcProvider();   // RAM snapshot: NO
    case "docker": return new DockerProvider();             // RAM snapshot: NO
    case "morph":
    default: return new MorphProvider();                    // RAM snapshot: YES
  }
}
```

**Migration Strategy:**
1. Create abstraction layer with `MorphProvider` as default
2. Implement `ProxmoxKvmProvider` (RAM snapshot) + `ProxmoxLxcProvider` (fast ephemeral)
3. Test in staging with `SANDBOX_PROVIDER=proxmox-kvm`
4. Gradual rollout: 20% -> 50% -> 80% of workloads
5. Keep Morph as fallback for edge cases
6. Route ephemeral tasks to LXC for cost optimization

---

### AI Provider Cost Reduction

**Current Architecture:**
- Uses `@ai-sdk` library as abstraction layer
- `createOpenAI`, `createAnthropic`, `createGoogleGenerativeAI` functions
- API calls routed through Cloudflare (`CLOUDFLARE_OPENAI_BASE_URL`)

**Key files to modify:**
- `apps/www/lib/services/code-review/model-config.ts` - Model configurations
- `packages/shared/src/agentConfig.ts` - Agent configs with API keys
- `apps/server/src/utils/commitMessageGenerator.ts` - `getModelAndProvider()`
- `apps/www/lib/utils/branch-name-generator.ts` - Branch name generation
- `apps/www/lib/services/code-review/run-heatmap-review.ts` - PR review

**Adding Ollama/Local LLM Support:**

1. Create new model config:
```typescript
// In model-config.ts
export const ollamaModels: ModelConfig[] = [
  {
    provider: "ollama",
    modelId: "deepseek-coder-v2:16b",
    name: "DeepSeek Coder (Local)",
  },
  {
    provider: "ollama",
    modelId: "qwen2.5-coder:14b",
    name: "Qwen 2.5 Coder (Local)",
  }
];
```

2. Add createOllama function:
```typescript
import { createOpenAI } from "@ai-sdk/openai";

// Ollama uses OpenAI-compatible API
const ollama = createOpenAI({
  baseURL: process.env.OLLAMA_BASE_URL || "http://localhost:11434/v1",
  apiKey: "ollama", // Ollama doesn't need real key
});
```

3. Update `getModelAndProvider` with fallback:
```typescript
// Try local first, fallback to cloud
if (process.env.OLLAMA_BASE_URL) {
  try {
    return { model: ollama(modelId), provider: "ollama" };
  } catch (e) {
    console.warn("Local LLM failed, falling back to cloud");
  }
}
// ... existing cloud provider logic
```

---

## Open Questions & Guidance

| Question | How to Answer | Estimated Answer |
|----------|---------------|------------------|
| Actual Morph spend per month? | Check Morph billing dashboard or API logs | ~$200-500/mo for 5-10 concurrent |
| How many concurrent sandboxes? | Query Convex `environments` table or server logs | 2-5 per user session typical |
| WebSocket support needed? | Inspect VNC/OpenVSCode network traffic | Yes (VNC, CDP real-time) |
| Morph RAM snapshots critical? | Test workflow without; check if CRIU works | microsandbox uses persistent `./menv` dirs instead |
| Latency requirements? | Survey team; measure current Morph startup | microsandbox: <200ms (meets target) |
| microsandbox maturity? | Monitor GitHub issues, test in staging | New (May 2025) but active; keep Morph fallback |
| KVM/hardware virtualization? | Check VPS provider support | Hetzner/DigitalOcean support KVM; verify before purchase |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Self-hosting increases ops burden | Start with managed VPS (Hetzner); add monitoring early |
| Local LLM quality drop | Hybrid strategy; cloud fallback for complex tasks |
| Data migration issues | Use staging env; rollback plans; Convex export/import |
| WebSocket edge router bugs | Thorough testing; keep Cloudflare DNS as fallback |
| **RAM snapshot is CRITICAL** | Use Proxmox KVM (not LXC) for tasks needing pause/resume + Morph fallback |
| LXC does NOT support CRIU | Do NOT expect `pct checkpoint` - use LXC only for ephemeral tasks |
| Proxmox setup complexity | Leverage existing Proxmox experience; use Ansible/Terraform for automation |
| KVM not available on VPS | Verify KVM support before purchasing; Hetzner/DO both support nested virt |
| KVM suspend-to-disk latency | Test restore times; expect ~2-5s vs Morph's faster resume |
| Network interruption on resume | Clients need reconnect logic after KVM resume; test WebSocket reconnection |

---

## Final Recommendations

1. **Start with Phase 1** - immediate 20-30% savings with minimal risk
2. **Assign owners** to each open question; resolve before Phase 2
3. **Use staging environments** for all migrations; maintain rollback capability
4. **Integrate monitoring early** (Prometheus/Grafana + Sentry) for real-time cost tracking
5. **Review ROI monthly** and adjust priorities based on actual savings
6. **For sandbox migration**: **Hybrid KVM + LXC** - KVM for RAM snapshots, LXC for fast ephemeral tasks

**Sandbox Provider Architecture (Hybrid Proxmox + Morph):**
1. **Long-running tasks: Proxmox KVM** - `qm suspend --todisk` provides RAM snapshot
2. **Ephemeral tasks: Proxmox LXC** - Fast startup (~100ms), no RAM snapshot needed
3. **Fallback: Morph Cloud** - Keep enabled forever for resilience, automatic failover

> [!danger] Critical Correction
> **Proxmox LXC does NOT support CRIU checkpoint/restore.**
> The `pct checkpoint` command does not exist. Use KVM VMs for RAM snapshots.

**Key Benefit**: Never fully dependent on one provider - graceful degradation if Proxmox fails, Morph as proven reliable fallback. LXC provides cost optimization for high-volume ephemeral tasks.

**Total Potential Savings: 70-85% ($300/mo target from current $1000-2000/mo)**

---

## Appendix: Sandbox Solution Comparison (Dec 2025 Research)

> **Verified via Context7 documentation lookup**

### Technology Spectrum (RAM Snapshot Support Verified)

| Technology | Isolation Level | Startup | Security | RAM Snapshot | Source |
|------------|-----------------|---------|----------|--------------|--------|
| V8 Isolates | Runtime | ~1ms | Low | **No** | - |
| WebAssembly | Runtime | ~10ms | Medium | **No** | - |
| Docker/OCI | Namespace | ~10-50ms | Medium | **CRIU experimental** | - |
| **Proxmox LXC** | Container | ~100ms | Medium | **No** (disk only) | Proxmox docs |
| gVisor | App Kernel | ~100ms | High | **No** | - |
| nsjail | Process | ~50ms | Medium-High | **No** | - |
| **Firecracker** | MicroVM | ~125ms | Very High | **Yes** | GitHub docs |
| **libkrun** (microsandbox) | MicroVM | ~200ms | Very High | **No** | Context7 |
| **KVM/QEMU** | Full VM | ~2-5s | Very High | **Yes** | Proxmox docs |

### Platform Comparison - RAM Snapshot Verified (CRITICAL)

> [!danger] Correction: Proxmox LXC + CRIU
> **Previous versions incorrectly claimed Proxmox LXC supports CRIU.**
> `pct checkpoint` and `pct restore` commands DO NOT EXIST in Proxmox VE.
> CRIU integration is experimental only, NOT production-ready.

| Platform | Technology | RAM Snapshot | Verified Source | cmux Fit |
|----------|------------|--------------|-----------------|----------|
| **Morph Cloud** | Proprietary | **Yes** | Production use | **Current** |
| **Proxmox VM** | KVM/QEMU | **Yes** | `qm suspend --todisk` saves memory to disk | **Excellent** |
| **Proxmox LXC** | LXC | **No** (disk only) | `pct snapshot` - NO RAM state | Fast ephemeral only |
| **e2b** | Firecracker | **Yes** | `betaPause()`/`connect()` - full memory file | Good (not in plan) |
| **Firecracker** | MicroVM | **Yes** | "full copy of guest memory" - verified | Good (not in plan) |
| **Kata Containers** | Cloud-Hypervisor | **Yes** | `VmSnapshotPut` / `VmRestorePut` | K8s integration |
| **microsandbox** | libkrun | **No** | Only in-session state persistence | **Not suitable** |
| **Daytona** | Containers | **No** | Filesystem only | **Not suitable** |
| Docker + CRIU | Docker | **Experimental** | Requires CRIU setup, unreliable | Not recommended |

### Verified: Solutions WITHOUT RAM Snapshot (Filtered Out)

These solutions **do NOT support snapshotting complete guest memory**:

| Solution | What They DO Support | What They DON'T Support |
|----------|---------------------|------------------------|
| **Proxmox LXC** | Disk snapshots (`pct snapshot`), fast startup | RAM snapshot, process resume (NO CRIU) |
| **microsandbox** | Filesystem persistence (`./menv`), in-session variable state | RAM snapshot, process resume after stop |
| **Daytona** | Filesystem archiving, container stop/start | RAM snapshot, running process preservation |
| **nsjail** | Process isolation, resource limits | Any state persistence |
| **gVisor** | Container checkpoint (limited) | Full RAM snapshot |

### Verified: Solutions WITH RAM Snapshot (Implementation Candidates)

| Solution | RAM Snapshot Method | Verified By |
|----------|---------------------|-------------|
| **Proxmox VM (KVM)** | `qm suspend ID --todisk` - "VM's memory content saved to disk" | Proxmox docs |
| **Firecracker** | Memory-mapped snapshot files - "full copy of guest memory" | Firecracker GitHub |
| **Kata Containers** | Cloud-Hypervisor/QEMU snapshot | Kata docs |
| **e2b** | Firecracker snapshot - "full copy of guest memory" | e2b docs Context7 |
| **Morph Cloud** | Native VM snapshot | Production verified |

### Firecracker Snapshot Capability (from GitHub docs)
```
Firecracker snapshots preserve:
- "the guest memory"
- "the emulated HW state (both KVM and Firecracker emulated HW)"

Creates "a full copy of the guest memory" during full snapshots.
Uses MAP_PRIVATE mapping for "very fast snapshot loading times".
```

### Proxmox VM Suspend (from Context7 docs)
```shell
# Suspends VM to disk - memory content saved, VM stopped
# Upon restart, memory is loaded, VM resumes from previous state
qm suspend ID --todisk
```

### References
- [Proxmox VE Docs](https://pve.proxmox.com/pve-docs/) - verified via Context7
- [Proxmox Forum - CRIU](https://forum.proxmox.com/tags/criu/) - CRIU not supported in Proxmox LXC
- [CRIU GitHub Issue #1430](https://github.com/checkpoint-restore/criu/issues/1430) - LXC integration issues
- [Proxmox Roadmap](https://pve.proxmox.com/wiki/Roadmap) - CRIU not on roadmap
- [Firecracker Snapshot Support](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/snapshot-support.md)
- [Kata Containers](https://github.com/kata-containers/kata-containers) - K8s-native MicroVM
- [e2b Persistence Docs](https://github.com/e2b-dev/E2B) - verified via Context7
- [microsandbox](https://github.com/microsandbox/microsandbox) - verified NO RAM snapshot via Context7
- [CRIU](https://criu.org/) - Checkpoint/Restore In Userspace (NOT integrated with Proxmox)

---

## Implementation Notes

### Provider Naming Standardization (Dec 30, 2025)

Standardized provider naming across cmux codebase to use only three canonical names:
- `morph` - Morph Cloud provider (original)
- `pve-lxc` - Proxmox VE LXC containers (fast ephemeral tasks, no RAM snapshot)
- `pve-vm` - Proxmox VE KVM VMs (RAM snapshot support via `qm suspend --todisk`)
