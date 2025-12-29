# Kata Containers Installation Scripts

Scripts for installing Kata Containers with Firecracker/Cloud Hypervisor support.

> **See also**: [[../Self-Hosted-Sandbox-Platforms-Comparison]] for alternatives like Daytona, E2B, Microsandbox

## Scripts Overview

| Script | Source | Purpose |
|--------|--------|---------|
| `kata-manager.sh` | [Official](https://github.com/kata-containers/kata-containers/blob/main/utils/kata-manager.sh) | Full-featured official installer |
| `kata-quickstart.sh` | Derived | Simplified one-script setup |
| `kata-k8s-deploy.sh` | Derived | Kubernetes/K3s deployment |
| `kata-snapshot-test.sh` | Custom | Snapshot demo & testing |
| `kata-api-server.py` | Custom | REST API for VM management |
| `kata-api-daemonset.yaml` | Custom | K8s DaemonSet for API server |
| `check-podman-prerequisites.sh` | Custom | Check Podman/CRIU requirements |
| `test-podman-checkpoint.sh` | Custom | Test Podman checkpoint/restore |

---

## Quick Start Commands

### Standalone Linux Host (Non-Kubernetes)

**Option 1: Official kata-manager.sh (recommended)**
```bash
# Install Kata + containerd (latest)
sudo ./kata-manager.sh -o

# List available hypervisors
./kata-manager.sh -L

# Switch to Firecracker
sudo ./kata-manager.sh -S fc
```

**Option 2: Simplified quickstart**
```bash
# Basic install
sudo ./kata-quickstart.sh

# With Firecracker + devmapper
sudo ./kata-quickstart.sh --firecracker

# For K3s clusters
sudo ./kata-quickstart.sh --k3s --firecracker
```

### Kubernetes Cluster

**Standard Kubernetes:**
```bash
./kata-k8s-deploy.sh install
```

**K3s:**
```bash
./kata-k8s-deploy.sh install-k3s
```

**One-liner (standard K8s):**
```bash
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml && \
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-deploy/base/kata-deploy.yaml
```

---

## Testing

```bash
# Test with ctr (standalone)
sudo ctr run --runtime io.containerd.kata.v2 --rm -t docker.io/library/alpine:latest test sh

# Test with Firecracker (needs devmapper)
sudo ctr run --snapshotter devmapper --runtime io.containerd.kata-fc.v2 --rm -t docker.io/library/alpine:latest test sh

# Test in Kubernetes
kubectl run kata-test --image=alpine --restart=Never --rm -it \
  --overrides='{"spec":{"runtimeClassName":"kata"}}' -- uname -a
```

---

## RuntimeClasses Created

After installation, these RuntimeClasses are available:

| RuntimeClass | Hypervisor | Use Case |
|-------------|------------|----------|
| `kata` | QEMU (default) | General purpose |
| `kata-fc` | Firecracker | Fast boot, snapshots |
| `kata-clh` | Cloud Hypervisor | Alternative to QEMU |
| `kata-qemu` | QEMU | Explicit QEMU |

---

## Snapshot Testing (Cloud Hypervisor)

```bash
# On K3s node - full demo
./kata-snapshot-test.sh demo

# Individual commands
./kata-snapshot-test.sh create     # Create test pod
./kata-snapshot-test.sh pause      # Pause VM
./kata-snapshot-test.sh snapshot   # Create snapshot (~2GB)
./kata-snapshot-test.sh resume     # Resume VM
./kata-snapshot-test.sh cleanup    # Delete pod
```

---

## Kata API Server (Optional)

Deploy REST API for managing Kata VMs:

```bash
kubectl apply -f kata-api-daemonset.yaml

# API endpoints (NodePort 30808)
curl http://<node>:30808/vms              # List VMs
curl http://<node>:30808/vms/<id>/pause   # Pause
curl http://<node>:30808/vms/<id>/resume  # Resume
curl http://<node>:30808/snapshots        # List snapshots
```

---

## Podman Checkpoint Testing (CRIU-based Snapshots)

Podman supports container checkpointing via CRIU, similar to VM snapshots but for containers.

### Prerequisites Check

```bash
# Check if system meets requirements
sudo ./check-podman-prerequisites.sh

# Auto-install missing packages
sudo ./check-podman-prerequisites.sh --install
```

### Run Checkpoint Test

```bash
# Full checkpoint/restore test suite
sudo ./test-podman-checkpoint.sh
```

### Key Requirements (Tested on Ubuntu 24.04)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Podman 4.x+ | ✅ | `apt install podman` |
| CRIU 4.x+ | ✅ | Via PPA: `ppa:criu/ppa` |
| runc runtime | ✅ | `apt install runc` - **required** (crun doesn't support checkpoint) |
| Root/sudo | ✅ | Checkpoint requires root privileges |

### Quick Test Commands

```bash
# Create container with runc (required for checkpoint)
sudo podman run -d --name test --runtime=runc alpine sleep infinity

# Create checkpoint (stops container)
sudo podman container checkpoint test --export=/tmp/checkpoint.tar.gz

# Restore from checkpoint
sudo podman rm test
sudo podman container restore --import=/tmp/checkpoint.tar.gz --name test-restored

# Create checkpoint while keeping container running
sudo podman container checkpoint test --export=/tmp/snapshot.tar.gz --leave-running
```

> **Note**: Default crun runtime does NOT support checkpoint/restore. Always use `--runtime=runc`

---

## References

- [Official Installation Docs](https://github.com/kata-containers/kata-containers/tree/main/docs/install)
- [kata-deploy Documentation](https://github.com/kata-containers/kata-containers/tree/main/tools/packaging/kata-deploy)
- [Firecracker Configuration](https://github.com/kata-containers/kata-containers/blob/main/docs/hypervisors.md)
- [[../Self-Hosted-Sandbox-Platforms-Comparison]] - Daytona, E2B, Microsandbox alternatives
- [[Kata-Firecracker-Setup-Guide]] - Full setup guide
