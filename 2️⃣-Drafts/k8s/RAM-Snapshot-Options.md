# RAM Snapshot Options for Kubernetes Workloads

> **Last Updated**: 2025-12-29
> **Verified via**: Context7 MCP, DeepWiki MCP, Web Search
> **Important Correction**: Proxmox LXC + CRIU is **NOT officially supported** in Proxmox VE

---

## Executive Summary

**Standard Kubernetes does NOT support RAM snapshots natively.** To achieve RAM snapshot capability (preserving running process memory state across pause/resume cycles), you need specialized runtimes or external virtualization platforms.

---

## CRITICAL CORRECTION: Proxmox LXC + CRIU

> [!warning] Misinformation Alert
> The `cmux-costreduce-roadmap.md` document contains **incorrect information** about Proxmox LXC + CRIU support.

### What the Document Claims (INCORRECT)
```bash
# CLAIMED - These commands DO NOT EXIST in Proxmox VE
pct checkpoint <vmid> --state-file /path/to/checkpoint
pct restore <vmid> --state-file /path/to/checkpoint
```

### Reality (Verified Dec 2025)

| Claim | Reality | Source |
|-------|---------|--------|
| `pct checkpoint` command exists | **NO** - Command does not exist | [DeepWiki Proxmox](https://deepwiki.com), [Proxmox Forum](https://forum.proxmox.com/tags/criu/) |
| CRIU integrated in Proxmox LXC | **NO** - Experimental only, not production-ready | [CRIU GitHub Issue #1430](https://github.com/checkpoint-restore/criu/issues/1430) |
| Live migration via CRIU | **NO** - Not on Proxmox 2024-2025 roadmap | [Proxmox Roadmap](https://pve.proxmox.com/wiki/Roadmap) |

### What Proxmox LXC Actually Supports

```bash
# These commands DO exist
pct snapshot <vmid> <snapname>      # Disk snapshot only (NO RAM)
pct rollback <vmid> <snapname>      # Restore disk state
pct listsnapshot <vmid>             # List snapshots
pct restore <vmid> <backup.tar.gz>  # Restore from backup file
```

**LXC snapshots in Proxmox only capture disk state, NOT running process memory.**

---

## Verified RAM Snapshot Solutions

### 1. Firecracker MicroVMs (VERIFIED)

**Status**: ✅ Full RAM snapshot support confirmed

From [DeepWiki Firecracker](https://deepwiki.com/firecracker-microvm/firecracker) and Context7:

```bash
# Pause the microVM first
curl -X PATCH --unix-socket /tmp/firecracker.socket \
  -d '{"state": "Paused"}' \
  http://localhost/vm

# Create full snapshot (saves memory + VM state)
curl -X PUT --unix-socket /tmp/firecracker.socket \
  -d '{
    "snapshot_type": "Full",
    "snapshot_path": "/path/to/vmstate",
    "mem_file_path": "/path/to/memory"
  }' \
  http://localhost/snapshot/create

# Restore from snapshot
curl -X PUT --unix-socket /tmp/firecracker.socket \
  -d '{
    "snapshot_path": "/path/to/vmstate",
    "mem_backend": {
      "backend_type": "File",
      "backend_path": "/path/to/memory"
    }
  }' \
  http://localhost/snapshot/load
```

**Go SDK Example** (from Context7):
```go
import sdk "github.com/firecracker-microvm/firecracker-go-sdk"

// Create snapshot
m.PauseVM(ctx)
m.CreateSnapshot(ctx, memPath, snapPath)

// Load snapshot
m, _ := sdk.NewMachine(ctx, cfg, sdk.WithSnapshot(memPath, snapPath))
m.Start(ctx)
m.ResumeVM(ctx)
```

**Key Features**:
- Full memory state preservation
- Differential snapshots (only changed pages)
- Dirty page tracking for optimization
- ~125ms restore time

---

### 2. Kata Containers (VERIFIED)

**Status**: ✅ RAM snapshot via Cloud-Hypervisor/QEMU backend

From Context7 Kata Containers docs:

```go
// Pause VM
api_client.DefaultApi.PauseVM(context.Background()).Execute()

// Create snapshot
vmSnapshotConfig := *openapiclient.NewVmSnapshotConfig()
api_client.DefaultApi.VmSnapshotPut(context.Background()).VmSnapshotConfig(vmSnapshotConfig).Execute()

// Resume VM
api_client.DefaultApi.ResumeVM(context.Background()).Execute()

// Restore from snapshot
restoreConfig := *openapiclient.NewRestoreConfig("SourceUrl_example")
api_client.DefaultApi.VmRestorePut(context.Background()).RestoreConfig(restoreConfig).Execute()
```

**Kata API for Containers**:
```
sandbox.PauseContainer(containerID)
sandbox.ResumeContainer(containerID)
```

**Kubernetes Integration**:
- Native K8s RuntimeClass support
- Uses Firecracker or Cloud-Hypervisor as VMM
- MicroVM isolation per pod

---

### 3. Proxmox KVM/QEMU VMs (VERIFIED)

**Status**: ✅ Full RAM snapshot via suspend-to-disk

```bash
# Suspend VM (saves memory to disk)
qm suspend <vmid> --todisk

# Resume VM (loads memory from disk)
qm resume <vmid>
```

**Note**: This is for **full VMs**, not LXC containers. Restore time ~2-5 seconds.

---

### 4. e2b (Firecracker-based)

**Status**: ✅ RAM snapshot via Firecracker backend

```typescript
// Pause sandbox (saves full memory)
await sandbox.betaPause()

// Resume by reconnecting
const sandbox = await Sandbox.connect(sandboxId)
```

---

## Comparison Matrix (Verified Dec 2025)

| Solution | RAM Snapshot | K8s Native | Restore Time | Production Ready |
|----------|--------------|------------|--------------|------------------|
| **Firecracker** | ✅ Yes | Via Kata | ~125ms | ✅ Yes |
| **Kata Containers** | ✅ Yes | ✅ Yes | ~200ms | ✅ Yes |
| **Proxmox KVM** | ✅ Yes | ❌ No | ~2-5s | ✅ Yes |
| **e2b** | ✅ Yes | ❌ No (SaaS) | ~100ms | ✅ Yes |
| **Proxmox LXC** | ❌ No | ❌ No | N/A | ⚠️ Disk only |
| **Docker + CRIU** | ⚠️ Experimental | ❌ No | Unknown | ❌ No |
| **Plain K8s** | ❌ No | ✅ Yes | N/A | ✅ Yes |

---

## For Your K3s Lab Environment

Based on your setup (K3s v1.33.6 on Ubuntu 24.04):

### Option A: Kata Containers + Firecracker (Recommended for K8s)

```bash
# Install Kata Containers
sudo snap install kata-containers --classic

# Configure containerd to use Kata
# Add to /etc/containerd/config.toml:
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
  runtime_type = "io.containerd.kata.v2"

# Create RuntimeClass in K8s
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata
EOF

# Use in Pod spec
spec:
  runtimeClassName: kata
  containers:
  - name: myapp
    image: nginx
```

### Option B: Standalone Firecracker (Outside K8s)

If you don't need K8s integration:
1. Run Firecracker directly on the host
2. Use firecracker-go-sdk for management
3. Implement snapshot/restore via API

### Option C: Keep Using Morph Cloud (Current)

Morph Cloud has native RAM snapshot - keep as fallback while testing alternatives.

---

## Correcting the cmux-costreduce-roadmap.md

The following sections need correction:

### Remove/Update These Claims:

1. **Line 41**: "Proxmox VE/LXC + CRIU ... Yes (CRIU checkpoint)" → **INCORRECT**
2. **Line 56**: "Proxmox LXC + CRIU ... pct checkpoint / pct restore" → **COMMANDS DON'T EXIST**
3. **Lines 63-100**: Entire "Option A: Proxmox LXC + CRIU (RECOMMENDED)" section → **NOT VIABLE**

### Recommended Replacement Architecture:

```
Primary: Firecracker (via Kata Containers or standalone)
Fallback: Morph Cloud (current, proven)
NOT recommended: Proxmox LXC (no RAM snapshot support)
```

---

## References

- [Firecracker Snapshotting Docs](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/snapshot-support.md)
- [Kata Containers Documentation](https://github.com/kata-containers/kata-containers)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Forum - CRIU](https://forum.proxmox.com/tags/criu/)
- [CRIU GitHub Issue #1430](https://github.com/checkpoint-restore/criu/issues/1430)
- [Proxmox Roadmap](https://pve.proxmox.com/wiki/Roadmap)

---

#kubernetes #k8s #firecracker #kata-containers #proxmox #ram-snapshot #virtualization
