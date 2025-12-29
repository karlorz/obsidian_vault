# Self-Hosted Sandbox/MicroVM Platforms Comparison

> **Goal**: Find Morph Cloud-like solution with Web UI, Snapshots, Easy Deploy
> **Last Updated**: 2025-12-29
> **Verified via**: DeepWiki MCP, Web Search

---

## Executive Summary

### AI Sandbox / MicroVM Platforms

| Platform | Self-Host | Web UI | Snapshot | Pause/Resume | License | Deploy Ease | Recommendation |
|----------|-----------|--------|----------|--------------|---------|-------------|----------------|
| **Daytona** | ✅ | ✅ Full | ✅ | ✅ | AGPL-3.0 | ⭐⭐⭐⭐ | **Best Overall** |
| **E2B** | ✅ (GCP) | ❌ | ✅ | ✅ | Apache-2.0 | ⭐⭐ | Complex self-host |
| **Microsandbox** | ✅ | ❌ CLI | ✅ Build | ❌ | Apache-2.0 | ⭐⭐⭐⭐⭐ | Simplest setup |
| **OpenNebula** | ✅ | ✅ Sunstone | ✅ | ✅ | Apache-2.0 | ⭐⭐ | Enterprise |
| **Kata + K8s** | ✅ | ❌ | ✅ CLH | ✅ | Apache-2.0 | ⭐⭐⭐ | K8s native |

**Winner for AI sandbox use case: Daytona** - Full Web UI, Snapshots, Auto-lifecycle, Docker Compose deploy

### Complementary Technologies (Different Purpose)

| Platform | Primary Use | Technology | Web UI | Snapshot | License | When to Use |
|----------|-------------|------------|--------|----------|---------|-------------|
| **Podman** | Container runtime | OCI containers | ❌ (Desktop app) | ✅ CRIU | Apache-2.0 | Docker replacement, rootless |
| **Proxmox VE** | Virtualization | KVM + LXC | ✅ Full | ✅ | AGPL-3.0 | Homelab, enterprise VMs |

> **Note**: Podman and Proxmox VE serve **fundamentally different purposes** than the AI sandbox platforms above. They are complementary—many users run Podman inside Proxmox LXC containers, or K3s+Kata inside Proxmox KVM VMs. See detailed sections below.

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

| Feature            | Daytona   | E2B        | Microsandbox | OpenNebula | Kata+K8s   |
| ------------------ | --------- | ---------- | ------------ | ---------- | ---------- |
| **Isolation**      | Container | MicroVM    | MicroVM      | MicroVM    | MicroVM    |
| **Boot Time**      | <90ms     | <200ms     | <200ms       | ~1s        | ~300ms     |
| **Web UI**         | ✅ Full    | ❌          | ❌            | ✅ Full     | ❌          |
| **Snapshot**       | ✅         | ✅          | Build only   | ✅          | ✅          |
| **Pause/Resume**   | ✅         | ✅          | ❌            | ✅          | ✅          |
| **Auto-lifecycle** | ✅         | ❌          | ❌            | ✅          | ❌          |
| **SDK**            | Py/TS     | Py/JS/TS   | Py/JS/Rust   | API        | API        |
| **MCP Support**    | ✅         | ✅          | ✅ Native     | ❌          | ❌          |
| **K8s Native**     | ❌         | ❌          | ❌            | ❌          | ✅          |
| **License**        | AGPL-3.0  | Apache-2.0 | Apache-2.0   | Apache-2.0 | Apache-2.0 |
| **Deploy Effort**  | Low       | High       | Very Low     | Medium     | Medium     |

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

## Complementary Technologies: Podman & Proxmox VE

> **Important Note**: Podman and Proxmox VE serve **fundamentally different purposes** in the virtualization/containerization landscape. They are **not direct competitors**—many users combine them effectively. This section helps clarify where each fits in a self-hosted infrastructure.

### Comparison Overview

| Aspect | Podman | Proxmox VE |
|--------|--------|------------|
| **Primary Purpose** | Container runtime engine | Full virtualization platform |
| **Technology** | OCI containers (daemonless) | KVM VMs + LXC containers |
| **Scope** | Application containers | Infrastructure/datacenter management |
| **Isolation Level** | Container (namespace/cgroups) | Full VM (hardware) or LXC (OS-level) |
| **Use Case** | Dev environments, microservices | Homelab, enterprise VMs, multi-tenant |
| **License** | Apache-2.0 | AGPL-3.0 (free tier available) |

---

### 6. Podman

> Daemonless, rootless container engine - Docker alternative

**GitHub**: [containers/podman](https://github.com/containers/podman) (25k+ stars)
**Website**: [podman.io](https://podman.io)

#### What is Podman?

Podman (POD MANager) is a daemonless container management tool for managing OCI containers, images, volumes, and pods on Linux systems. Unlike Docker, Podman does not require a daemon to run containers, providing improved security and lower resource utilization at idle.

#### Architecture: Daemonless Design

```
Docker Architecture:              Podman Architecture:
┌─────────────────────┐          ┌─────────────────────┐
│   Docker CLI        │          │   Podman CLI        │
└─────────┬───────────┘          └─────────┬───────────┘
          │                                │
          ▼                                ▼
┌─────────────────────┐          ┌─────────────────────┐
│   Docker Daemon     │          │   Fork/Exec         │
│   (always running)  │          │   (no daemon)       │
└─────────┬───────────┘          └─────────┬───────────┘
          │                                │
          ▼                                ▼
┌─────────────────────┐          ┌─────────────────────┐
│   containerd        │          │   conmon + runc     │
└─────────┬───────────┘          └─────────┬───────────┘
          │                                │
          ▼                                ▼
┌─────────────────────┐          ┌─────────────────────┐
│   Container         │          │   Container         │
└─────────────────────┘          └─────────────────────┘
```

**Key Difference**: If Docker daemon crashes, all containers go down. In Podman, each container runs as a child process - no single point of failure.

#### Features

| Feature | Support | Notes |
|---------|---------|-------|
| Rootless | ✅ Native | Built from ground up for rootless |
| Daemonless | ✅ | No background daemon required |
| Docker Compatible | ✅ | `alias docker=podman` works |
| Pods | ✅ | Native pod support (like K8s pods) |
| Compose | ✅ | podman-compose or docker-compose |
| Checkpointing | ✅ | CRIU-based container snapshots |
| Systemd Integration | ✅ | Quadlet for systemd units |
| Desktop GUI | ✅ | Podman Desktop (cross-platform) |

#### Rootless Security Model

```bash
# Docker (traditional) - requires root/daemon
sudo docker run nginx

# Podman rootless - runs as regular user
podman run nginx
```

**Security Benefits**:
- Containers inherit user privileges (not root)
- Reduced kernel capabilities (11 vs Docker's 14)
- Out-of-the-box SELinux enforcement
- No daemon = smaller attack surface

#### Container Checkpointing (Snapshots)

Podman supports CRIU-based checkpointing for container state preservation:

```bash
# Checkpoint a running container (saves state to disk)
sudo podman container checkpoint mycontainer

# Restore the container (continues from exact state)
sudo podman container restore mycontainer

# Checkpoint and export to file
sudo podman container checkpoint mycontainer --export=/tmp/checkpoint.tar.gz

# Restore on different machine
sudo podman container restore --import=/tmp/checkpoint.tar.gz
```

> **Note**: Checkpointing requires root privileges and CRIU 3.11+

#### Quick Start

```bash
# Install (Fedora/RHEL/CentOS)
sudo dnf install podman

# Install (Ubuntu/Debian)
sudo apt install podman

# Run container (Docker-compatible)
podman run -d --name web -p 8080:80 nginx

# Create a pod (K8s-style)
podman pod create --name mypod -p 8080:80
podman run -d --pod mypod nginx
podman run -d --pod mypod redis

# Generate Kubernetes YAML from running pod
podman generate kube mypod > mypod.yaml

# Generate systemd unit files
podman generate systemd --new --name web > web.service
```

#### Podman Desktop

Cross-platform GUI for managing containers:

```bash
# Install on macOS
brew install podman-desktop

# Install on Windows
winget install RedHat.PodmanDesktop
```

Features:
- Manage containers, images, pods, volumes
- Kubernetes integration
- Extension support
- No licensing restrictions (unlike Docker Desktop)

#### Pros
- **Rootless by default** - superior security model
- **Daemonless** - no single point of failure
- **Docker CLI compatible** - easy migration
- **Native pod support** - K8s-like grouping
- **Checkpointing** - true state snapshots (with CRIU)
- **No licensing fees** - Apache-2.0

#### Cons
- **Checkpointing requires root** - not available rootless
- **Ecosystem maturity** - some tools still Docker-focused
- **No built-in Web UI** - need Podman Desktop or Cockpit
- **Container isolation only** - not VM-level security

#### When to Use Podman

| Use Case | Recommendation |
|----------|----------------|
| Local development | ✅ Excellent Docker replacement |
| CI/CD pipelines | ✅ Security-focused builds |
| Kubernetes prep | ✅ Native pod/YAML generation |
| Production microservices | ✅ With systemd integration |
| **MicroVM isolation** | ❌ Use Kata/Firecracker instead |
| **Full VM management** | ❌ Use Proxmox VE |

---

### 7. Proxmox VE

> Enterprise-grade open-source virtualization platform

**Website**: [proxmox.com](https://www.proxmox.com/en/products/proxmox-virtual-environment)
**GitHub**: [proxmox/pve-docs](https://github.com/proxmox/pve-docs)

#### What is Proxmox VE?

Proxmox Virtual Environment (PVE) is a powerful open-source server virtualization platform that manages two virtualization technologies with a single web-based interface:
- **KVM** (Kernel-based Virtual Machine) - Full hardware virtualization
- **LXC** (Linux Containers) - OS-level containerization

#### Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Proxmox VE Web UI                        │
│                    (Sunstone-like)                          │
└─────────────────────────┬──────────────────────────────────┘
                          │
┌─────────────────────────▼──────────────────────────────────┐
│                    Proxmox VE API                           │
│              (REST API + CLI tools)                         │
└────────┬───────────────────────────────────────┬───────────┘
         │                                       │
┌────────▼────────┐                   ┌──────────▼──────────┐
│    KVM/QEMU     │                   │       LXC           │
│  (Full VMs)     │                   │   (Containers)      │
│                 │                   │                     │
│ • Any OS        │                   │ • Linux only        │
│ • Full isolation│                   │ • Shared kernel     │
│ • More overhead │                   │ • Low overhead      │
│ • Snapshots ✅  │                   │ • Snapshots ✅      │
└─────────────────┘                   └─────────────────────┘
         │                                       │
         └───────────────────┬───────────────────┘
                             │
┌────────────────────────────▼───────────────────────────────┐
│                    Storage Layer                            │
│  ZFS | Ceph | NFS | iSCSI | LVM | Local                    │
└────────────────────────────────────────────────────────────┘
```

#### Features

| Feature | Support | Notes |
|---------|---------|-------|
| Web UI | ✅ Full | Comprehensive management interface |
| KVM VMs | ✅ | Full virtualization (Windows, Linux, BSD) |
| LXC Containers | ✅ | Lightweight Linux containers |
| OCI Containers | ✅ (9.1+) | New: Run Docker images via LXC |
| Live Migration | ✅ | Move running VMs between nodes |
| Snapshots | ✅ | VM and container snapshots |
| HA Clustering | ✅ | Automatic failover |
| Backup/Restore | ✅ | vzdump + Proxmox Backup Server |
| Software-Defined Storage | ✅ | ZFS, Ceph, iSCSI integration |
| API | ✅ | Full REST API + Terraform provider |

#### KVM vs LXC Performance

| Metric | KVM (Full VM) | LXC (Container) |
|--------|---------------|-----------------|
| CPU Performance | ~95-98% native | ~99% native |
| Memory Overhead | ~200-500MB | ~10-50MB |
| Disk I/O | Slower (virtio) | Near-native |
| Boot Time | 10-60 seconds | 1-5 seconds |
| Isolation | Full hardware | OS-level |
| Guest OS | Any (Win/Linux/BSD) | Linux only |
| Use Case | Full VMs, Windows | Services, lightweight |

#### New in Proxmox 9.1: OCI Container Support

```bash
# Pull and run Docker image directly on Proxmox node
# (Uses LXC under the hood)
pct pull docker.io/library/nginx:latest
pct create 100 local:vztmpl/nginx.tar.xz
```

This bridges the gap between traditional LXC and OCI/Docker ecosystems.

#### Snapshot & Backup Features

```bash
# Create VM snapshot (includes RAM state if running)
qm snapshot 100 snap1 --vmstate

# Restore from snapshot
qm rollback 100 snap1

# Live backup of running VM
vzdump 100 --mode snapshot --storage local

# Restore from backup
qmrestore /var/lib/vz/dump/vzdump-qemu-100.vma local
```

#### Live Migration

```bash
# Migrate VM 100 to node "pve2" (online/live)
qm migrate 100 pve2 --online

# Migrate container
pct migrate 101 pve2 --online
```

**Requirements for Live Migration**:
- Shared storage or local storage with migration
- Same CPU type or compatible CPU flags
- Network connectivity between nodes

#### Quick Start (Single Node)

```bash
# Download ISO from proxmox.com and install

# Or install on existing Debian 12:
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve.list
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
apt update && apt install proxmox-ve

# Access Web UI at https://<ip>:8006
```

#### Terraform Integration

```hcl
# Proxmox provider for infrastructure as code
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.46.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "example" {
  name      = "example-vm"
  node_name = "pve"

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 20
  }
}
```

#### Pros
- **Full Web UI** - complete management interface
- **Dual virtualization** - KVM + LXC in one platform
- **Enterprise features** - HA, clustering, live migration
- **Strong storage** - ZFS, Ceph, NFS native integration
- **Mature & stable** - 15+ years of development
- **Free tier available** - no subscription required for core features

#### Cons
- **Heavy footprint** - not for simple container workloads
- **AGPL-3.0 license** - enterprise considerations
- **Learning curve** - full platform complexity
- **No microVM support** - KVM/LXC only (no Firecracker)
- **x86-64 focused** - limited ARM support

#### When to Use Proxmox VE

| Use Case | Recommendation |
|----------|----------------|
| Homelab virtualization | ✅ Excellent choice |
| Multi-tenant hosting | ✅ With clustering |
| Windows VMs | ✅ Full KVM support |
| Development environments | ✅ VM templates + LXC |
| Enterprise private cloud | ✅ With subscription |
| **AI sandbox microVMs** | ⚠️ Overkill - use Kata/Microsandbox |
| **Container orchestration** | ⚠️ Use K8s/K3s instead |

---

## Podman + Proxmox VE: Complementary Setup

Many users combine these technologies effectively:

```
┌─────────────────────────────────────────────────────────────┐
│                    Proxmox VE Host                          │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   KVM VM        │  │   LXC Container │  │  KVM VM     │ │
│  │   (Windows)     │  │   (Podman)      │  │  (K3s)      │ │
│  │                 │  │                 │  │             │ │
│  │                 │  │  ┌───────────┐  │  │ ┌─────────┐ │ │
│  │                 │  │  │ Container │  │  │ │Kata Pod │ │ │
│  │                 │  │  │ Container │  │  │ │Kata Pod │ │ │
│  │                 │  │  │ Container │  │  │ │         │ │ │
│  │                 │  │  └───────────┘  │  │ └─────────┘ │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Example Architecture**:
- **Proxmox VE**: Manages the physical infrastructure
- **LXC Container**: Runs Podman for lightweight microservices
- **KVM VM**: Runs K3s with Kata Containers for AI sandboxes
- **KVM VM**: Windows workloads that need full isolation

---

## Updated Feature Matrix

| Feature            | Daytona   | E2B        | Microsandbox | OpenNebula | Kata+K8s   | **Podman** | **Proxmox VE** |
| ------------------ | --------- | ---------- | ------------ | ---------- | ---------- | ---------- | -------------- |
| **Primary Use**    | AI Sandbox| AI Sandbox | AI Sandbox   | Cloud      | K8s Sandbox| Containers | Virtualization |
| **Isolation**      | Container | MicroVM    | MicroVM      | MicroVM    | MicroVM    | Container  | VM/LXC         |
| **Boot Time**      | <90ms     | <200ms     | <200ms       | ~1s        | ~300ms     | <100ms     | 10-60s (VM)    |
| **Web UI**         | ✅ Full   | ❌         | ❌           | ✅ Full    | ❌         | ❌ (Desktop)| ✅ Full       |
| **Snapshot**       | ✅        | ✅         | Build only   | ✅         | ✅         | ✅ (CRIU)  | ✅             |
| **Pause/Resume**   | ✅        | ✅         | ❌           | ✅         | ✅         | ✅ (CRIU)  | ✅             |
| **Live Migration** | ❌        | ❌         | ❌           | ✅         | ❌         | ❌         | ✅             |
| **Auto-lifecycle** | ✅        | ❌         | ❌           | ✅         | ❌         | ❌         | ✅ (HA)        |
| **K8s Native**     | ❌        | ❌         | ❌           | ❌         | ✅         | ⚠️ Pods    | ❌             |
| **Rootless**       | ❌        | ❌         | ❌           | ❌         | ❌         | ✅ Native  | N/A            |
| **Windows Support**| ❌        | ❌         | ❌           | ✅         | ❌         | ❌         | ✅ Full        |
| **License**        | AGPL-3.0  | Apache-2.0 | Apache-2.0   | Apache-2.0 | Apache-2.0 | Apache-2.0 | AGPL-3.0       |
| **Deploy Effort**  | Low       | High       | Very Low     | Medium     | Medium     | Very Low   | Medium         |

---

## Updated Recommendations by Use Case

### For Morph Cloud-like Experience
**→ Daytona** (unchanged)
- Web UI ✅, Snapshots ✅, Auto-lifecycle ✅

### For Simplest AI Sandbox
**→ Microsandbox** (unchanged)
- One binary, MCP native, <200ms boot

### For Enterprise Private Cloud
**→ Proxmox VE** ⭐ NEW
- Full Web UI with KVM + LXC
- Live migration, HA clustering
- ZFS/Ceph storage integration

### For Kubernetes-Native
**→ Kata Containers** (unchanged)
- Your existing K3s setup

### For Docker Replacement (Dev/CI)
**→ Podman** ⭐ NEW
- Rootless, daemonless, Docker-compatible
- Superior security model
- No licensing fees

### For Homelab Virtualization
**→ Proxmox VE** ⭐ NEW
- Manage VMs, containers, storage
- Run Podman inside LXC
- Run K3s inside KVM

### For Strongest Isolation + Snapshots
**→ E2B** (unchanged)
- Firecracker microVMs

---

## References (Updated)

### Original Platforms
- [Daytona GitHub](https://github.com/daytonaio/daytona)
- [E2B GitHub](https://github.com/e2b-dev/E2B)
- [Microsandbox GitHub](https://github.com/zerocore-ai/microsandbox)
- [OpenNebula Firecracker](https://opennebula.io/firecracker/)
- [Kata Containers](https://katacontainers.io/)

### Podman
- [Podman Official Site](https://podman.io)
- [Podman GitHub](https://github.com/containers/podman)
- [Podman Desktop](https://podman-desktop.io/)
- [Podman vs Docker 2025](https://www.linuxjournal.com/content/containers-2025-docker-vs-podman-modern-developers)
- [Podman Rootless Guide](https://dev.to/mechcloud_academy/docker-vs-podman-an-in-depth-comparison-2025-2eia)

### Proxmox VE
- [Proxmox VE Official](https://www.proxmox.com/en/products/proxmox-virtual-environment)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox VE Wiki](https://pve.proxmox.com/wiki/Main_Page)
- [Proxmox Containers Guide 2025](https://www.virtualizationhowto.com/2025/11/complete-guide-to-proxmox-containers-in-2025-docker-vms-lxc-and-new-oci-support/)
- [Terraform Provider for Proxmox](https://github.com/bpg/terraform-provider-proxmox)

### Comparisons
- [Best Sandbox Runners 2025](https://betterstack.com/community/comparisons/best-sandbox-runners/)
- [KVM vs LXC Performance](https://ikus-soft.com/en_CA/blog/techies-10/proxmox-ve-performance-of-kvm-vs-lxc-75)

---

#sandbox #microvm #self-hosted #daytona #e2b #microsandbox #kata-containers #firecracker #podman #proxmox #virtualization #containers
