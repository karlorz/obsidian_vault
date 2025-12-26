# cmux Cost Reduction Roadmap

> **Target**: 70-85% cost reduction, aiming for <$300/mo total
> **Timeline**: 2-4 months phased approach
> **Last Updated**: 2025-12-26

---

## Executive Summary

| Priority | Service | Current | Alternative | Est. Alt Cost | Savings | Risks | Code Changes |
|----------|---------|---------|-------------|---------------|---------|-------|--------------|
| 1 | Morph Sandboxes | $$$$ (~$200-500/mo) | Proxmox VE/LXC, K8s, Local Docker | $50-300/mo | 70-90% | High setup; ensure port/snapshot parity | Medium-High |
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

| Option | Isolation | Startup | Self-Deploy Ease | Est. Cost | Recommendation |
|--------|-----------|---------|------------------|-----------|----------------|
| **microsandbox** (RECOMMENDED) | MicroVM (libkrun) | <200ms | High - single binary | $20-100/mo | Best fit for cmux |
| **e2b self-hosted** | MicroVM (Firecracker) | ~150ms | Medium - Terraform | $50-150/mo | Good if need SaaS fallback |
| **Daytona** | Container (OCI) | <90ms | High - good docs | $30-100/mo | AGPL license concern |
| **Kata Containers** | MicroVM + Container | ~200ms | Medium - needs K8s | $50-200/mo | Enterprise-grade |
| Proxmox VE/LXC | Container (LXC) | ~100ms | Medium - setup work | $50-200/mo | Fallback option |
| Local Docker | Container | <50ms | High | $0 (dev only) | Dev/testing only |

**Why microsandbox is the top choice:**
1. **Self-hosted by design** - No SaaS dependency, Apache-2.0 license (no AGPL concerns)
2. **MicroVM security** - Hardware-level isolation via libkrun, not just container namespaces
3. **Fast startup** - Sub-200ms comparable to Morph's performance
4. **Persistent project mode** - `msr` command maps to cmux's need for stateful dev environments
5. **Simple architecture** - Single `msb` server binary + SDK clients (Python, JS, Rust)
6. **New but promising** - Launched May 2025, ~3.3k GitHub stars, active development

**Security Trade-off Context** (from sandboxing research):
- Containers share kernel = potential escape vulnerabilities (69% of incidents are misconfigs)
- MicroVMs (microsandbox, e2b, Firecracker) provide hardware-enforced isolation
- For untrusted agent code execution, MicroVM isolation is strongly preferred

**Improvements**:
- **Primary**: Implement microsandbox provider for self-hosted production
- **Hybrid approach**: Morph for edge cases/bursts, microsandbox for 80%+ workloads
- Target startup latency: <200ms (microsandbox matches this)
- Create `SandboxProvider` abstraction layer for future provider switches
- For RAM snapshots: Use microsandbox persistent `./menv` dirs instead

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
| 2.4 | **Deploy microsandbox server** on Hetzner VPS; benchmark latency | - | [ ] |
| 2.5 | Create `SandboxProvider` abstraction layer in cmux | - | [ ] |

### Phase 3: Core Migrations (6-10 weeks)
| Step | Task | Owner | Status |
|------|------|-------|--------|
| 3.1 | Implement `MicrosandboxProvider` with full API parity | - | [ ] |
| 3.2 | Create cmux base image for microsandbox (all services) | - | [ ] |
| 3.3 | Migrate 20% -> 50% of sandbox workloads to microsandbox | - | [ ] |
| 3.4 | Test persistent mode (`msr`) for stateful dev environments | - | [ ] |
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

### Morph Replacement with microsandbox (Primary) or Proxmox LXC (Fallback)

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

#### Option A: microsandbox Implementation (RECOMMENDED)

**Why microsandbox over Proxmox:**
- MicroVM isolation (hardware-level) vs LXC (container namespace)
- Simpler deployment: single `msb` binary vs Proxmox cluster setup
- Built-in persistent project mode (`msr`) vs manual LXC snapshot management
- Apache-2.0 license, purpose-built for code sandboxing

**microsandbox Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│  Host Server (Hetzner/DigitalOcean $20-50/mo)              │
│  ├─ msb server (microsandbox daemon)                       │
│  │   ├─ libkrun (MicroVM hypervisor)                       │
│  │   └─ Networking (port mapping 39377-39381)              │
│  └─ ./menv/ (persistent sandbox filesystems)               │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  MicroVM Sandbox Instance                                   │
│  ├─ cmux-openvscode.service (port 39378)                   │
│  ├─ cmux-worker.service (port 39377)                       │
│  ├─ cmux-proxy.service (port 39379)                        │
│  ├─ cmux-tigervnc.service (port 39380)                     │
│  └─ cmux-cdp-proxy.service (port 39381)                    │
└─────────────────────────────────────────────────────────────┘
```

**microsandbox Implementation Steps:**
1. Deploy `msb` server on Hetzner/DigitalOcean VPS
   ```bash
   curl -fsSL https://get.microsandbox.dev | sh
   msb server start --port 8080
   ```
2. Create cmux base image with all services pre-installed
3. Configure networking for port range 39377-39381
4. Use `msr` (persistent mode) for stateful dev environments
5. Use `msx` (ephemeral mode) for one-off agent tasks
6. Implement `MicrosandboxProvider` in cmux codebase

**microsandbox SDK Integration:**
```typescript
// packages/shared/src/sandbox-providers/microsandbox.ts
import { Sandbox } from "microsandbox";

export class MicrosandboxProvider implements SandboxProvider {
  async startInstance(config: SandboxConfig): Promise<SandboxInstance> {
    const sandbox = await Sandbox.create({
      image: "cmux-base",
      persistent: config.persistent ?? true,
      ports: [39377, 39378, 39379, 39380, 39381],
    });
    return { id: sandbox.id, ports: sandbox.ports };
  }

  async stopInstance(id: string): Promise<void> {
    await Sandbox.stop(id);
  }

  async pauseInstance(id: string): Promise<void> {
    // microsandbox: stop preserves state in ./menv
    await Sandbox.stop(id);
  }
}
```

---

#### Option B: Proxmox LXC Implementation (Fallback)

**Use Proxmox LXC if:**
- Need more mature/battle-tested infrastructure
- Already have Proxmox expertise
- Need true RAM snapshot support (CRIU)

**Proxmox LXC Implementation Steps:**
1. Create base Ubuntu LXC template
2. Install dependencies: docker.io, docker-compose, git, curl, node, bun, uv
3. Build and install cmux services (worker, proxy binaries)
4. Install OpenVSCode server
5. Configure TigerVNC + xvfb
6. Create systemd units mirroring Morph setup
7. Configure networking (expose ports 39377-39381)
8. Create template/snapshot from configured container
9. Implement `ProxmoxProvider` in cmux codebase

---

#### Provider Abstraction Layer

**Required API Changes:**
```typescript
// packages/shared/src/sandbox-providers/types.ts
export interface SandboxProvider {
  startInstance(config: SandboxConfig): Promise<SandboxInstance>;
  stopInstance(id: string): Promise<void>;
  pauseInstance(id: string): Promise<void>;
  getInstanceStatus(id: string): Promise<SandboxStatus>;
  listInstances(): Promise<SandboxInstance[]>;
}

// packages/shared/src/sandbox-providers/index.ts
export function getSandboxProvider(): SandboxProvider {
  const provider = process.env.SANDBOX_PROVIDER || "morph";
  switch (provider) {
    case "microsandbox": return new MicrosandboxProvider();
    case "proxmox": return new ProxmoxProvider();
    case "docker": return new DockerProvider();
    case "morph":
    default: return new MorphProvider();
  }
}
```

**Migration Strategy:**
1. Create abstraction layer with `MorphProvider` as default
2. Implement `MicrosandboxProvider` for self-hosted
3. Test in staging with `SANDBOX_PROVIDER=microsandbox`
4. Gradual rollout: 20% -> 50% -> 80% of workloads
5. Keep Morph as fallback for edge cases

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
| microsandbox is new (May 2025) | Hybrid approach: keep Morph for production bursts; gradual migration |
| microsandbox lacks RAM snapshots | Use persistent `./menv` dirs; test if workflow acceptable |
| KVM not available on VPS | Verify KVM support before purchasing; Hetzner/DO both support |
| microsandbox networking complexity | Test port mapping 39377-39381 in staging first |

---

## Final Recommendations

1. **Start with Phase 1** - immediate 20-30% savings with minimal risk
2. **Assign owners** to each open question; resolve before Phase 2
3. **Use staging environments** for all migrations; maintain rollback capability
4. **Integrate monitoring early** (Prometheus/Grafana + Sentry) for real-time cost tracking
5. **Review ROI monthly** and adjust priorities based on actual savings
6. **For sandbox migration**: Prioritize microsandbox over Proxmox for easier self-deploy + MicroVM security

**Total Potential Savings: 70-85% ($300/mo target from current $1000-2000/mo)**

---

## Appendix: Sandbox Solution Comparison (Dec 2025 Research)

### Technology Spectrum

| Technology | Isolation Level | Startup | Security | Compatibility |
|------------|-----------------|---------|----------|---------------|
| V8 Isolates | Runtime | ~1ms | Low | JS only |
| WebAssembly | Runtime | ~10ms | Medium | WASM modules |
| Docker/OCI | Namespace | ~10-50ms | Medium | Full Linux |
| gVisor | App Kernel | ~100ms | High | Linux subset |
| nsjail | Process | ~50ms | Medium-High | Filtered syscalls |
| **Firecracker** | MicroVM | ~125ms | **Very High** | Full Linux |
| **libkrun** | MicroVM | ~container | **Very High** | Full Linux |

### Platform Comparison for cmux Use Case

| Platform | Technology | Self-Host | License | cmux Fit |
|----------|------------|-----------|---------|----------|
| **microsandbox** | libkrun MicroVM | Primary | Apache-2.0 | Excellent |
| **e2b** | Firecracker | Yes (GCP/AWS) | Apache-2.0 | Good |
| Daytona | Containers | Yes | AGPL-3.0 | Good (license concern) |
| Kata Containers | MicroVM | Yes | Apache-2.0 | Good (K8s overhead) |
| Fly.io | Firecracker | No (SaaS only) | Proprietary | N/A |
| Cloudflare Workers | V8 Isolates | No | Proprietary | N/A (JS only) |

### Key Insight: Security vs Performance Trade-off

For cmux (running untrusted agent code):
- **Container isolation is insufficient** - 94% of orgs report container security incidents
- **MicroVM provides hardware-enforced boundaries** - dedicated kernel per sandbox
- **microsandbox/e2b offer MicroVM with container-like startup** (<200ms)

### References
- [microsandbox GitHub](https://github.com/microsandbox/microsandbox)
- [e2b GitHub](https://github.com/e2b-dev/E2B)
- [Firecracker](https://firecracker-microvm.github.io/)
- [libkrun](https://github.com/containers/libkrun)
