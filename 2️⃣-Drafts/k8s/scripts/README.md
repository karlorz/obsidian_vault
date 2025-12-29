# Kata Containers Installation Scripts

Scripts for installing Kata Containers with Firecracker support.

## Scripts Overview

| Script | Source | Purpose |
|--------|--------|---------|
| `kata-manager.sh` | [Official](https://github.com/kata-containers/kata-containers/blob/main/utils/kata-manager.sh) | Full-featured official installer |
| `kata-quickstart.sh` | Derived | Simplified one-script setup |
| `kata-k8s-deploy.sh` | Derived | Kubernetes/K3s deployment |

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

## References

- [Official Installation Docs](https://github.com/kata-containers/kata-containers/tree/main/docs/install)
- [kata-deploy Documentation](https://github.com/kata-containers/kata-containers/tree/main/tools/packaging/kata-deploy)
- [Firecracker Configuration](https://github.com/kata-containers/kata-containers/blob/main/docs/hypervisors.md)
