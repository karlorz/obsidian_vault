# Self-Hosted Sandbox/MicroVM Platforms Comparison

> **Goal**: Find Morph Cloud-like solution with Web UI, Snapshots, Easy Deploy
> **Last Updated**: 2025-12-29
> **Verified via**: DeepWiki MCP, Web Search

---

## Executive Summary

| Platform | Self-Host | Web UI | Snapshot | Pause/Resume | License | Deploy Ease | Recommendation |
|----------|-----------|--------|----------|--------------|---------|-------------|----------------|
| **Daytona** | ✅ | ✅ Full | ✅ | ✅ | AGPL-3.0 | ⭐⭐⭐⭐ | **Best Overall** |
| **E2B** | ✅ (GCP) | ❌ | ✅ | ✅ | Apache-2.0 | ⭐⭐ | Complex self-host |
| **Microsandbox** | ✅ | ❌ CLI | ✅ Build | ❌ | Apache-2.0 | ⭐⭐⭐⭐⭐ | Simplest setup |
| **OpenNebula** | ✅ | ✅ Sunstone | ✅ | ✅ | Apache-2.0 | ⭐⭐ | Enterprise |
| **Kata + K8s** | ✅ | ❌ | ✅ CLH | ✅ | Apache-2.0 | ⭐⭐⭐ | K8s native |

**Winner for your use case: Daytona** - Full Web UI, Snapshots, Auto-lifecycle, Docker Compose deploy

---

## Detailed Comparison

### 1. Daytona ⭐ RECOMMENDED

> Secure Infrastructure for Running AI-Generated Code

**GitHub**: [daytonaio/daytona](https://github.com/daytonaio/daytona) (21k+ stars)

#### Features
| Feature | Support | Notes |
|---------|---------|-------|
| Self-Hosted | ✅ | Docker Compose deployment |
| Web UI | ✅ | Full dashboard with sandbox table |
| Snapshots | ✅ | Pre-built templates from OCI images |
| Pause/Resume | ✅ | Stop (clears memory) / Start |
| Archive | ✅ | Move to object storage |
| Auto-lifecycle | ✅ | Auto-stop, auto-archive, auto-delete |
| SDK | ✅ | Python, TypeScript |
| MCP Integration | ✅ | AI workflow support |

#### Sandbox States
```
STARTED → STOPPED → ARCHIVED → DELETED
    ↑         ↓
    └─────────┘
```

#### Self-Host Deployment
```bash
git clone https://github.com/daytonaio/daytona
cd daytona
docker compose up -d
```

Services included:
- API Server
- Proxy
- Runner
- SSH Gateway
- Database (PostgreSQL)
- Redis

#### Pros
- Full-featured Web UI
- Automated lifecycle management
- OCI/Docker compatible
- Active development (21k stars)

#### Cons
- **AGPL-3.0 license** (enterprise friction - modifications must be open-sourced)
- Uses containers, not microVMs (weaker isolation than Firecracker)

---

### 2. E2B

> Open-source secure sandbox for AI agents (Firecracker-based)

**GitHub**: [e2b-dev/E2B](https://github.com/e2b-dev/E2B)

#### Features
| Feature | Support | Notes |
|---------|---------|-------|
| Self-Hosted | ✅ | Terraform on GCP (AWS coming) |
| Web UI | ❌ | SaaS dashboard only |
| Snapshots | ✅ | Via pause/resume (`betaPause()`) |
| Pause/Resume | ✅ | Memory preserved |
| Firecracker | ✅ | True microVM isolation |
| SDK | ✅ | Python, JavaScript, TypeScript |

#### Self-Host Requirements
- Google Cloud Platform (GCP)
- Terraform
- Infrastructure repo: [e2b-dev/infra](https://github.com/e2b-dev/infra)

#### Architecture
```
┌─────────────────┐     ┌─────────────────┐
│  Control Plane  │────▶│   Data Plane    │
│   (REST API)    │     │    (gRPC)       │
└─────────────────┘     └─────────────────┘
        │                       │
        ▼                       ▼
   Sandbox Lifecycle      Sandbox Operations
```

#### Pros
- Firecracker microVMs (strong isolation)
- Used by 88% of Fortune 100
- Apache-2.0 license
- True memory snapshots

#### Cons
- **No self-hosted Web UI**
- Complex infrastructure (Terraform + GCP)
- Primarily SaaS-focused ($150/mo+)

---

### 3. Microsandbox

> Open-source self-hosted sandboxes for AI agents

**GitHub**: [zerocore-ai/microsandbox](https://github.com/zerocore-ai/microsandbox) (4.1k stars)

#### Features
| Feature | Support | Notes |
|---------|---------|-------|
| Self-Hosted | ✅ | Single binary |
| Web UI | ❌ | CLI + SDK only |
| Snapshots | ✅ | Build-time only (`msb build --snapshot`) |
| Pause/Resume | ❌ | Not yet |
| MicroVM | ✅ | libkrun (KVM-based) |
| MCP Integration | ✅ | Native support |
| SDK | ✅ | Python, JavaScript, Rust |

#### Architecture
```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│  SDK Client  │────▶│  msb server     │────▶│   MicroVM    │
│  (JSON-RPC)  │     │  (libkrun)      │     │   (sandbox)  │
└──────────────┘     └─────────────────┘     └──────────────┘
```

#### Installation
```bash
# One-liner install
curl -sSL https://get.microsandbox.dev | sh

# Start server
msb server start

# Generate API key
msb server keygen
```

#### Sandboxfile Example
```toml
[sandbox]
image = "python:3.11-slim"
cpus = 2
memory = "2GB"

[sandbox.env]
PYTHONUNBUFFERED = "1"
```

#### Pros
- **Easiest deployment** (single binary)
- Hardware-level isolation (microVM)
- <200ms boot time
- Apache-2.0 license
- Native MCP support

#### Cons
- **No Web UI** (CLI only)
- No runtime pause/resume
- Still experimental
- Build-time snapshots only

---

### 4. OpenNebula + Firecracker

> Enterprise cloud platform with Firecracker support

**Website**: [opennebula.io/firecracker](https://opennebula.io/firecracker/)

#### Features
| Feature | Support | Notes |
|---------|---------|-------|
| Self-Hosted | ✅ | Full control |
| Web UI | ✅ | Sunstone dashboard |
| Snapshots | ✅ | Full VM snapshots |
| Pause/Resume | ✅ | VM state management |
| Firecracker | ✅ | Native integration |
| Docker Hub | ✅ | Direct image import |

#### Quick Deploy (miniONE)
```bash
curl -fsSL https://downloads.opennebula.io/packages/opennebula-6.8/minione | \
  sudo bash -s -- --firecracker
```

#### Sunstone Web UI Features
- VM management dashboard
- Docker Hub marketplace integration
- VNC console access
- Resource monitoring

#### Pros
- Mature enterprise platform
- Full Web UI (Sunstone)
- Firecracker + KVM + LXD support
- Apache-2.0 license

#### Cons
- **Heavy/complex** for simple use cases
- Designed for full cloud deployment
- Steeper learning curve

---

### 5. Kata Containers + Kubernetes

> Your current setup on K3s

#### Features
| Feature | Support | Notes |
|---------|---------|-------|
| Self-Hosted | ✅ | K8s native |
| Web UI | ❌ | K8s Dashboard (limited) |
| Snapshots | ✅ | Cloud Hypervisor API |
| Pause/Resume | ✅ | CLH/FC API |
| K8s Integration | ✅ | RuntimeClass |

#### Tested on Your K3s
```bash
# Pause VM
curl --unix-socket /run/vc/vm/<id>/clh-api.sock \
  -X PUT http://localhost/api/v1/vm.pause

# Snapshot (2GB memory dump)
curl --unix-socket /run/vc/vm/<id>/clh-api.sock \
  -X PUT -d '{"destination_url":"file:///path"}' \
  http://localhost/api/v1/vm.snapshot

# Resume
curl --unix-socket /run/vc/vm/<id>/clh-api.sock \
  -X PUT http://localhost/api/v1/vm.resume
```

#### Pros
- Already working on your K3s
- K8s native integration
- Multiple hypervisors (QEMU, CLH, FC)
- Apache-2.0 license

#### Cons
- **No Web UI** for VM operations
- Need custom API for management
- K8s Dashboard can't pause/snapshot

---

## Feature Matrix

| Feature | Daytona | E2B | Microsandbox | OpenNebula | Kata+K8s |
|---------|---------|-----|--------------|------------|----------|
| **Isolation** | Container | MicroVM | MicroVM | MicroVM | MicroVM |
| **Boot Time** | <90ms | <200ms | <200ms | ~1s | ~300ms |
| **Web UI** | ✅ Full | ❌ | ❌ | ✅ Full | ❌ |
| **Snapshot** | ✅ | ✅ | Build only | ✅ | ✅ |
| **Pause/Resume** | ✅ | ✅ | ❌ | ✅ | ✅ |
| **Auto-lifecycle** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **SDK** | Py/TS | Py/JS/TS | Py/JS/Rust | API | API |
| **MCP Support** | ✅ | ✅ | ✅ Native | ❌ | ❌ |
| **K8s Native** | ❌ | ❌ | ❌ | ❌ | ✅ |
| **License** | AGPL-3.0 | Apache-2.0 | Apache-2.0 | Apache-2.0 | Apache-2.0 |
| **Deploy Effort** | Low | High | Very Low | Medium | Medium |

---

## Recommendation by Use Case

### For Morph Cloud-like Experience
**→ Daytona**
- Web UI ✅
- Snapshots ✅
- Auto-lifecycle ✅
- Easy deploy ✅

### For Simplest AI Sandbox
**→ Microsandbox**
- One binary install
- MCP native
- <200ms boot

### For Enterprise Private Cloud
**→ OpenNebula**
- Full cloud platform
- Firecracker support
- Mature & stable

### For Kubernetes-Native
**→ Kata Containers (current setup)**
- Already working
- Add custom API for management

### For Strongest Isolation + Snapshots
**→ E2B (self-hosted)**
- Firecracker microVMs
- True memory snapshots
- Complex to self-host

---

## Quick Start Commands

### Daytona
```bash
git clone https://github.com/daytonaio/daytona
cd daytona
docker compose up -d
# Access Web UI at http://localhost:3000
```

### Microsandbox
```bash
curl -sSL https://get.microsandbox.dev | sh
msb server start
msb server keygen
```

### OpenNebula (miniONE)
```bash
curl -fsSL https://downloads.opennebula.io/packages/opennebula-6.8/minione | \
  sudo bash -s -- --firecracker
# Access Sunstone at http://localhost:9869
```

---

## References

- [Daytona GitHub](https://github.com/daytonaio/daytona)
- [E2B GitHub](https://github.com/e2b-dev/E2B)
- [E2B Infrastructure](https://github.com/e2b-dev/infra)
- [Microsandbox GitHub](https://github.com/zerocore-ai/microsandbox)
- [Microsandbox Docs](https://docs.microsandbox.dev/)
- [OpenNebula Firecracker](https://opennebula.io/firecracker/)
- [Kata Containers](https://katacontainers.io/)
- [Best Sandbox Runners 2025](https://betterstack.com/community/comparisons/best-sandbox-runners/)
- [E2B Alternatives - Beam](https://www.beam.cloud/blog/best-e2b-alternatives)

---

#sandbox #microvm #self-hosted #daytona #e2b #microsandbox #kata-containers #firecracker
