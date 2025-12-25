# cmux Cost Reduction Roadmap

## Current Deployment Costs Overview

### 1. Morph Cloud Sandboxes (HIGH COST)
**Current**: `MORPH_API_KEY` - https://cloud.morph.so/web/subscribe
- Provisions isolated dev environments for coding agents
- Each instance: CPU, memory, disk allocation
- Exposed ports: OpenVSCode (39378), worker (39377), proxy (39379), VNC (39380), CDP (39381)
- TTL-based billing with pause/stop actions
- Snapshot management for different presets

**Self-Host Alternatives**:
- [ ] Proxmox VE with LXC containers
- [ ] Local Docker (already supported - "ideal for iterative work")
- [ ] Kubernetes cluster
- [ ] ECS on AWS
- [ ] Render
- [ ] Bare metal

**Code Changes Required**: Medium - cmux already mentions "bring your own environment" mode

---

### 2. AI Provider APIs (HIGH COST - 2nd highest)
**Current Keys**:
- `ANTHROPIC_API_KEY` - Claude for coding agents (main driver)
- `OPENAI_API_KEY` - PR heatmap reviews, code analysis
- `GOOGLE_API_KEY` - Gemini CLI support

**Why High Cost**: Coding agents consume massive tokens per session (context windows, multi-turn conversations, code generation)

**Cost Reduction Options**:

**Option A: Third-Party API Proxies (Claude/OpenAI Compatible)**
- [ ] **OpenRouter** - https://openrouter.ai - Multi-provider routing, often cheaper
- [ ] **Together AI** - https://together.ai - OpenAI-compatible, open models
- [ ] **Fireworks AI** - https://fireworks.ai - Fast inference, competitive pricing
- [ ] **Groq** - https://groq.com - Ultra-fast, limited models
- [ ] **DeepInfra** - https://deepinfra.com - Open model hosting
- [ ] **Anyscale** - https://anyscale.com - Enterprise open models

**Option B: Self-Hosted / Local LLMs**
- [ ] Ollama + DeepSeek/Qwen - Zero cost after hardware
- [ ] vLLM cluster - Production-grade self-hosted
- [ ] llama.cpp - CPU fallback

**Implementation: Base URL Override**
```env
# Override API endpoints to use third-party providers
ANTHROPIC_BASE_URL=https://openrouter.ai/api/v1
OPENAI_BASE_URL=https://api.together.xyz/v1
OLLAMA_BASE_URL=http://localhost:11434/v1
```

**Code Changes Required**: Low - add base URL env vars to existing provider setup

---

### 3. Convex Database (MEDIUM COST)
**Current**: `CONVEX_DEPLOY_KEY` - Convex Cloud
- Stores: repos, teams, users, environments, PRs, provider connections
- Real-time subscriptions
- Optimistic updates

**Self-Host Alternative**:
- [ ] Already supported! Docker images available:
  - `ghcr.io/get-convex/convex-backend`
  - `ghcr.io/get-convex/convex-dashboard`
- Local dev already uses self-hosted Convex via Docker Compose

**Code Changes Required**: Minimal - infrastructure config only

---

### 4. Cloudflare Workers / Edge Router (LOW COST - keep as is)
**Current**: `apps/edge-router` - handles `*.cmux.sh` and `*.cmux.app` wildcard proxying
- Routes `port-<port>-<vmSlug>.cmux.sh` to Morph instances
- CORS and header management
- Loop prevention with `X-Cmux-*` headers

**Self-Host Alternatives**:
- [ ] Nginx with Lua scripting
- [ ] Caddy with custom plugins
- [ ] Traefik with middleware
- [ ] HAProxy
- [ ] Node.js reverse proxy

**Code Changes Required**: Medium - rewrite edge router logic

---

### 5. Frontend Hosting (FREE/LOW COST)
**Current**: Vercel
- `cmux-client` - frontend
- `cmux-www` - marketing/docs

**Self-Host Alternatives**:
- [ ] Cloudflare Pages (free tier generous)
- [ ] Netlify
- [ ] Self-hosted Node.js/Nginx
- [ ] Docker container

**Code Changes Required**: Minimal - static export or Node.js server

---

### 6. Backend Server (MEDIUM COST)
**Current**: `NEXT_PUBLIC_SERVER_ORIGIN` - apps/server (Hono backend)

**Self-Host Alternatives**:
- [ ] Docker container on VPS
- [ ] Kubernetes deployment
- [ ] Fly.io
- [ ] Railway

**Code Changes Required**: Minimal - containerized already

---

## Priority Roadmap

### Phase 1: Quick Wins (Low Effort)
1. **Self-host Convex** - Docker Compose already works
2. **Use local Docker mode** - Already implemented, just configure
3. **Optimize AI usage** - Add caching, rate limits

### Phase 2: Medium Effort
4. **Replace Morph with Proxmox/LXC** - Main cost driver
5. **Self-host edge router** - Nginx/Caddy replacement

### Phase 3: Full Self-Host
6. **Complete infrastructure migration**
7. **Custom snapshot system** - Replace Morph snapshots

---

## Detailed Implementation Notes

### Morph Replacement with Proxmox LXC

**Services to replicate inside each container:**
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

**Proxmox LXC Implementation Steps:**
1. Create base Ubuntu LXC template
2. Install dependencies: docker.io, docker-compose, git, curl, node, bun, uv
3. Build and install cmux services (worker, proxy binaries)
4. Install OpenVSCode server
5. Configure TigerVNC + xvfb
6. Create systemd units mirroring Morph setup
7. Configure networking (expose ports 39377-39381)
8. Create template/snapshot from configured container
9. Modify cmux to spawn LXC via Proxmox API instead of Morph API

**API Changes Required:**
- Replace `MorphCloudClient` calls with Proxmox API client
- Implement `startInstance()`, `stopInstance()`, `pauseInstance()` for Proxmox
- Map port exposure to Proxmox networking
- Implement snapshot management for Proxmox

---

### Convex Self-Host Implementation

**Already working for local dev!**

Docker Compose services:
```yaml
services:
  convex-backend:
    image: ghcr.io/get-convex/convex-backend
  convex-dashboard:
    image: ghcr.io/get-convex/convex-dashboard
```

**Production deployment:**
1. Deploy Docker Compose to VPS/cloud VM
2. Configure persistent volumes for data
3. Set up backup strategy
4. Update `CONVEX_DEPLOY_KEY` to point to self-hosted instance
5. Configure SSL/TLS termination

---

### Edge Router Replacement (Nginx/Caddy)

**Current Cloudflare Worker logic to replicate:**
- Wildcard domain handling: `*.cmux.sh`, `*.cmux.app`
- URL pattern: `port-<port>-<vmSlug>.cmux.sh` -> Morph instance
- CORS header injection
- `X-Cmux-*` internal headers
- Loop prevention

**Nginx config example:**
```nginx
server {
    listen 443 ssl;
    server_name ~^port-(?<port>\d+)-(?<vmSlug>[^.]+)\.cmux\.sh$;

    location / {
        proxy_pass http://$vmSlug.internal:$port;
        proxy_set_header X-Cmux-Original-Host $host;
        # CORS headers...
    }
}
```

**Caddy alternative:**
```
*.cmux.sh {
    @portvm header_regexp host Host port-(\d+)-([^.]+)\.cmux\.sh
    reverse_proxy @portvm {args.1}.internal:{args.0}
}
```

---

### Local Docker Mode (Already Implemented)

**Location in codebase:** Check "bring your own environment" / local Docker mode

**Benefits:**
- Zero cloud costs
- Faster iteration
- No network latency
- Full control

**Limitations:**
- Single machine only
- No persistence across restarts (without custom volumes)
- Resource constrained by local machine

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

3. Update `getModelAndProvider`:
```typescript
if (process.env.OLLAMA_BASE_URL) {
  return {
    model: ollama(modelId),
    provider: "ollama",
  };
}
```

**Cost-Free Local Options:**
- Ollama + DeepSeek Coder V2 (16B) - Good code understanding
- Ollama + Qwen 2.5 Coder (14B-32B) - Strong coding
- vLLM + any open model - Production-grade inference
- llama.cpp - CPU inference fallback

**Hybrid Strategy:**
- Use local LLMs for: commit messages, branch names, simple reviews
- Use cloud APIs for: complex multi-file reviews, agent orchestration

---

### Cost Estimation Summary

| Priority | Service | Current Cost | Alt Cost | Savings |
|----------|---------|-------------|----------|---------|
| 1 | Morph Sandboxes | $$$$ | $50-200/mo (Proxmox) | 60-90% |
| 2 | AI APIs (Claude/OpenAI) | $$$ | $0-100/mo (3rd party/local) | 50-90% |
| 3 | Convex Cloud | $$ | $20-50/mo (self-host) | 50-80% |
| 4 | Cloudflare Workers | $ | $10-20/mo (Nginx) | Variable |
| 5 | Vercel Frontend | Free | $5-10/mo | $0 |

**Third-Party AI Provider Comparison:**
| Provider | Claude Support | OpenAI Compat | Pricing |
|----------|---------------|---------------|---------|
| OpenRouter | Yes | Yes | Pay-per-token, often 10-30% cheaper |
| Together AI | No | Yes | Competitive, open models |
| Fireworks | No | Yes | Fast, good for coding |
| Groq | No | Yes | Ultra-fast, limited selection |

**Total Potential Savings: 60-80% of cloud costs**

---

### Implementation Order (Recommended)

**Phase 1: Quick Wins (1-2 weeks)**
1. Add `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` env var support
2. Test with OpenRouter for immediate cost savings
3. Self-host Convex (Docker Compose already works)

**Phase 2: Local AI Setup (2-4 weeks)**
4. Add Ollama base URL support for local LLMs
5. Configure hybrid strategy (local for simple tasks, cloud for complex)
6. Implement response caching for repeated queries

**Phase 3: Morph Replacement (4-8 weeks)**
7. Build Proxmox LXC template mirroring Morph services
8. Implement Proxmox API integration in cmux
9. Test snapshot/restore workflow

**Phase 4: Full Self-Host (8-12 weeks)**
10. Replace edge router with Nginx/Caddy
11. Production deployment of all self-hosted services
12. Monitoring and optimization

---

### Open Questions

- [ ] What is the actual Morph spend per month currently?
- [ ] How many concurrent sandboxes are typical?
- [ ] Is WebSocket support needed for edge router?
- [ ] Any Morph-specific features (RAM snapshots) critical to workflow?
- [ ] Latency requirements for sandbox startup?
