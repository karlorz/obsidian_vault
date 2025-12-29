# Kata Containers + Firecracker Setup Guide

> **Goal**: Build a Morph Cloud-like VM API with RAM snapshot support
> **Last Updated**: 2025-12-29
> **Verified via**: Context7 MCP, DeepWiki MCP
> **Target Environment**: Ubuntu 24.04, K3s v1.33.6

---

## Overview

This guide covers setting up Kata Containers with Firecracker hypervisor to achieve Morph Cloud-like functionality:

| Morph Cloud Feature | Firecracker Equivalent | Implementation |
|---------------------|----------------------|----------------|
| `instance.pause()` | `PATCH /vm {"state": "Paused"}` | Firecracker API |
| `instance.resume()` | `PATCH /vm {"state": "Resumed"}` | Firecracker API |
| `instance.snapshot()` | `PUT /snapshot/create` | Full memory + state |
| `expose_http_service()` | CNI + port mapping | Network config |
| Wake-on-HTTP | Custom controller | Needs implementation |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     Kubernetes (K3s)                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  containerd + devmapper snapshotter                        │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  Kata Runtime (kata-fc)                              │  │  │
│  │  │  ┌────────────────────────────────────────────────┐  │  │  │
│  │  │  │  Firecracker MicroVM                           │  │  │  │
│  │  │  │  ├─ Guest Kernel (vmlinux)                     │  │  │  │
│  │  │  │  ├─ Root Filesystem                            │  │  │  │
│  │  │  │  ├─ kata-agent (manages containers)            │  │  │  │
│  │  │  │  └─ Your Container Workload                    │  │  │  │
│  │  │  └────────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Hardware Requirements
- **CPU**: x86_64 with VT-x/AMD-V support
- **KVM**: Must be available (`/dev/kvm`)
- **Memory**: Minimum 4GB RAM (8GB+ recommended)
- **Disk**: 50GB+ free space

### Verify KVM Support

```bash
# Check KVM availability
ls -la /dev/kvm

# If missing, load modules
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd

# Verify
lsmod | grep kvm
```

---

## Part 1: Install Kata Containers with Firecracker

### Option A: Using kata-deploy (Recommended for K8s)

```bash
# Apply RBAC
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml

# Deploy Kata
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-deploy/base/kata-deploy.yaml

# Wait for deployment
kubectl -n kube-system wait --timeout=10m --for=condition=Ready -l name=kata-deploy pod

# Verify RuntimeClasses created
kubectl get runtimeclass
```

Expected RuntimeClasses:
```
NAME              HANDLER           AGE
kata-fc           kata-fc           1m    # Firecracker
kata-qemu         kata-qemu         1m    # QEMU (alternative)
kata-clh          kata-clh          1m    # Cloud-Hypervisor
```

### Option B: Manual Installation (For Custom Setup)

```bash
# Download Kata release
KATA_VERSION="3.2.0"
wget https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-x86_64.tar.xz

# Extract to /opt/kata
sudo mkdir -p /opt/kata
sudo tar -xvf kata-static-${KATA_VERSION}-x86_64.tar.xz -C /

# Verify installation
/opt/kata/bin/kata-runtime --version
/opt/kata/bin/containerd-shim-kata-v2 --version

# Check Firecracker binary
ls -la /opt/kata/bin/firecracker
```

---

## Part 2: Configure Devmapper Snapshotter

Firecracker requires block device snapshotter (devmapper). Overlayfs won't work!

### Create Devmapper Setup Script

```bash
sudo mkdir -p ~/scripts/devmapper
cat << 'EOF' | sudo tee ~/scripts/devmapper/create.sh
#!/bin/bash
set -ex

DATA_DIR=/var/lib/containerd/devmapper
POOL_NAME=devpool

mkdir -p ${DATA_DIR}

# Create data file (100GB sparse)
sudo touch "${DATA_DIR}/data"
sudo truncate -s 100G "${DATA_DIR}/data"

# Create metadata file (10GB sparse)
sudo touch "${DATA_DIR}/meta"
sudo truncate -s 10G "${DATA_DIR}/meta"

# Allocate loop devices
DATA_DEV=$(sudo losetup --find --show "${DATA_DIR}/data")
META_DEV=$(sudo losetup --find --show "${DATA_DIR}/meta")

# Calculate thin-pool parameters
SECTOR_SIZE=512
DATA_SIZE="$(sudo blockdev --getsize64 -q ${DATA_DEV})"
LENGTH_IN_SECTORS=$(bc <<< "${DATA_SIZE}/${SECTOR_SIZE}")
DATA_BLOCK_SIZE=128
LOW_WATER_MARK=32768

# Create thin-pool device
sudo dmsetup create "${POOL_NAME}" \
    --table "0 ${LENGTH_IN_SECTORS} thin-pool ${META_DEV} ${DATA_DEV} ${DATA_BLOCK_SIZE} ${LOW_WATER_MARK}"

echo "Devmapper thin-pool '${POOL_NAME}' created successfully!"
echo ""
echo "Add this to /etc/containerd/config.toml:"
echo ""
cat << TOML
[plugins."io.containerd.snapshotter.v1.devmapper"]
  pool_name = "${POOL_NAME}"
  root_path = "${DATA_DIR}"
  base_image_size = "10GB"
  discard_blocks = true
TOML
EOF

sudo chmod +x ~/scripts/devmapper/create.sh
```

### Run Devmapper Setup

```bash
# Execute setup script
cd ~/scripts/devmapper/
sudo ./create.sh

# Verify thin-pool created
sudo dmsetup ls
# Should show: devpool (253:0)
```

### Configure containerd for Devmapper

Edit `/etc/containerd/config.toml`:

```toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".containerd]
    default_runtime_name = "runc"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
      # Default runc runtime
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"

      # Kata with Firecracker
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]
        runtime_type = "io.containerd.kata-fc.v2"
        snapshotter = "devmapper"

# Devmapper snapshotter config
[plugins."io.containerd.snapshotter.v1.devmapper"]
  pool_name = "devpool"
  root_path = "/var/lib/containerd/devmapper"
  base_image_size = "10GB"
  discard_blocks = true
```

### Restart containerd

```bash
sudo systemctl restart containerd
sudo systemctl status containerd

# Verify devmapper plugin loaded
sudo ctr plugins ls | grep devmapper
# Should show: io.containerd.snapshotter.v1    devmapper    ok
```

---

## Part 3: Create Kata-Firecracker Shim

```bash
# Create shim wrapper script
cat << 'EOF' | sudo tee /usr/local/bin/containerd-shim-kata-fc-v2
#!/bin/bash
KATA_CONF_FILE=/opt/kata/share/defaults/kata-containers/configuration-fc.toml \
  /opt/kata/bin/containerd-shim-kata-v2 "$@"
EOF

sudo chmod +x /usr/local/bin/containerd-shim-kata-fc-v2

# Verify shim is accessible
which containerd-shim-kata-fc-v2
```

---

## Part 4: Create Kubernetes RuntimeClass

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
overhead:
  podFixed:
    memory: "160Mi"
    cpu: "250m"
scheduling:
  nodeSelector:
    katacontainers.io/kata-runtime: "true"
EOF
```

---

## Part 5: Test Kata-Firecracker

### Basic Container Test

```bash
# Pull image with devmapper snapshotter
sudo ctr images pull --snapshotter devmapper docker.io/library/ubuntu:latest

# Run container with Kata-Firecracker
sudo ctr run \
  --snapshotter devmapper \
  --runtime io.containerd.kata-fc.v2 \
  -t --rm \
  docker.io/library/ubuntu:latest \
  test-kata \
  uname -a
```

Expected output shows Kata kernel, not host:
```
Linux clr-xxxxxxxx 5.15.x-kata #1 SMP ... x86_64 GNU/Linux
```

### Kubernetes Pod Test

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kata-fc-test
spec:
  runtimeClassName: kata-fc
  containers:
  - name: ubuntu
    image: ubuntu:latest
    command: ["sleep", "infinity"]
EOF

# Verify pod running
kubectl get pod kata-fc-test

# Check kernel inside pod (should be Kata kernel)
kubectl exec kata-fc-test -- uname -a

# Cleanup
kubectl delete pod kata-fc-test
```

---

## Part 6: Firecracker API for Snapshots

### Understanding the Firecracker API

Firecracker exposes a REST API via Unix socket. Key endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/vm` | `PATCH` | Pause/Resume VM |
| `/snapshot/create` | `PUT` | Create snapshot |
| `/snapshot/load` | `PUT` | Load snapshot |
| `/drives/{id}` | `PUT/PATCH` | Configure drives |
| `/network-interfaces/{id}` | `PUT/PATCH` | Configure network |
| `/machine-config` | `PUT` | Set vCPU, memory |
| `/actions` | `PUT` | Start VM, send keys |

### Pause VM

```bash
# Find Firecracker socket (inside Kata runtime)
SOCKET="/run/vc/firecracker/<vm-id>/api.socket"

# Pause
curl -X PATCH --unix-socket ${SOCKET} \
  -H "Content-Type: application/json" \
  -d '{"state": "Paused"}' \
  http://localhost/vm
```

### Resume VM

```bash
curl -X PATCH --unix-socket ${SOCKET} \
  -H "Content-Type: application/json" \
  -d '{"state": "Resumed"}' \
  http://localhost/vm
```

### Create Snapshot

```bash
# VM must be paused first!
curl -X PUT --unix-socket ${SOCKET} \
  -H "Content-Type: application/json" \
  -d '{
    "snapshot_type": "Full",
    "snapshot_path": "/path/to/vmstate.snap",
    "mem_file_path": "/path/to/memory.snap"
  }' \
  http://localhost/snapshot/create
```

### Load Snapshot

```bash
# Must be fresh Firecracker instance!
curl -X PUT --unix-socket ${SOCKET} \
  -H "Content-Type: application/json" \
  -d '{
    "snapshot_path": "/path/to/vmstate.snap",
    "mem_backend": {
      "backend_type": "File",
      "backend_path": "/path/to/memory.snap"
    },
    "resume_vm": true
  }' \
  http://localhost/snapshot/load
```

---

## Part 7: Building a Morph-like API Service

To replicate Morph Cloud functionality, create a wrapper service:

### Go Implementation (using firecracker-go-sdk)

```go
package main

import (
    "context"
    "fmt"
    "net/http"

    firecracker "github.com/firecracker-microvm/firecracker-go-sdk"
)

type VMManager struct {
    machines map[string]*firecracker.Machine
}

// Create new VM
func (vm *VMManager) CreateInstance(ctx context.Context, cfg InstanceConfig) (*Instance, error) {
    fcCfg := firecracker.Config{
        SocketPath:      fmt.Sprintf("/tmp/firecracker-%s.sock", cfg.ID),
        KernelImagePath: "/opt/kata/share/kata-containers/vmlinux.container",
        Drives: []models.Drive{{
            DriveID:      firecracker.String("rootfs"),
            PathOnHost:   firecracker.String(cfg.RootfsPath),
            IsRootDevice: firecracker.Bool(true),
            IsReadOnly:   firecracker.Bool(false),
        }},
        NetworkInterfaces: []firecracker.NetworkInterface{{
            CNIConfiguration: &firecracker.CNIConfiguration{
                NetworkName: "fcnet",
                IfName:      "veth0",
            },
        }},
        MachineCfg: models.MachineConfiguration{
            VcpuCount:  firecracker.Int64(cfg.VCPUs),
            MemSizeMib: firecracker.Int64(cfg.MemoryMB),
        },
    }

    m, err := firecracker.NewMachine(ctx, fcCfg)
    if err != nil {
        return nil, err
    }

    if err := m.Start(ctx); err != nil {
        return nil, err
    }

    vm.machines[cfg.ID] = m
    return &Instance{ID: cfg.ID, Status: "running"}, nil
}

// Pause instance (preserves RAM state)
func (vm *VMManager) PauseInstance(ctx context.Context, id string) error {
    m, ok := vm.machines[id]
    if !ok {
        return fmt.Errorf("instance not found: %s", id)
    }
    return m.PauseVM(ctx)
}

// Resume instance
func (vm *VMManager) ResumeInstance(ctx context.Context, id string) error {
    m, ok := vm.machines[id]
    if !ok {
        return fmt.Errorf("instance not found: %s", id)
    }
    return m.ResumeVM(ctx)
}

// Create snapshot
func (vm *VMManager) CreateSnapshot(ctx context.Context, id, memPath, snapPath string) error {
    m, ok := vm.machines[id]
    if !ok {
        return fmt.Errorf("instance not found: %s", id)
    }

    // Must pause first
    if err := m.PauseVM(ctx); err != nil {
        return err
    }

    return m.CreateSnapshot(ctx, memPath, snapPath)
}

// Load from snapshot
func (vm *VMManager) LoadSnapshot(ctx context.Context, id, memPath, snapPath string) (*Instance, error) {
    cfg := firecracker.Config{
        SocketPath: fmt.Sprintf("/tmp/firecracker-%s.sock", id),
    }

    m, err := firecracker.NewMachine(ctx, cfg,
        firecracker.WithSnapshot(memPath, snapPath))
    if err != nil {
        return nil, err
    }

    if err := m.Start(ctx); err != nil {
        return nil, err
    }

    if err := m.ResumeVM(ctx); err != nil {
        return nil, err
    }

    vm.machines[id] = m
    return &Instance{ID: id, Status: "running"}, nil
}
```

### HTTP API Endpoints

```go
// POST /instances - Create instance
// GET /instances/{id} - Get instance status
// POST /instances/{id}/pause - Pause instance
// POST /instances/{id}/resume - Resume instance
// POST /instances/{id}/snapshot - Create snapshot
// POST /instances/{id}/restore - Restore from snapshot
// DELETE /instances/{id} - Stop and delete instance
```

---

## Part 8: Networking Setup

### CNI Configuration for Firecracker

Create `/etc/cni/net.d/fcnet.conflist`:

```json
{
  "name": "fcnet",
  "cniVersion": "0.4.0",
  "plugins": [
    {
      "type": "ptp",
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.127.0/24",
        "resolvConf": "/etc/resolv.conf"
      }
    },
    {
      "type": "firewall"
    },
    {
      "type": "tc-redirect-tap"
    }
  ]
}
```

### Install CNI Plugins

```bash
# Download CNI plugins
CNI_VERSION="v1.3.0"
wget https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz

sudo mkdir -p /opt/cni/bin
sudo tar -xzf cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin

# Install tc-redirect-tap (from firecracker-containerd)
git clone https://github.com/firecracker-microvm/firecracker-containerd
cd firecracker-containerd
make tc-redirect-tap
sudo cp tc-redirect-tap /opt/cni/bin/
```

---

## Part 9: Expose HTTP Services

### Using Kubernetes Services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-sandbox-service
spec:
  type: NodePort
  selector:
    app: my-sandbox
  ports:
  - name: vscode
    port: 39378
    targetPort: 39378
    nodePort: 30378
  - name: vnc
    port: 39380
    targetPort: 39380
    nodePort: 30380
```

### Using Ingress for Dynamic Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sandbox-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  rules:
  - host: "*.sandbox.local"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sandbox-router
            port:
              number: 80
```

---

## Comparison: Morph Cloud vs Self-Hosted

| Feature | Morph Cloud | Self-Hosted Firecracker |
|---------|-------------|-------------------------|
| Pause/Resume | `instance.pause()` | `m.PauseVM()` / `m.ResumeVM()` |
| RAM Snapshot | `instance.snapshot()` | `m.CreateSnapshot()` |
| Restore | `client.instances.start(snapshot_id)` | `WithSnapshot()` option |
| HTTP Expose | `expose_http_service()` | K8s Service + Ingress |
| Wake-on-HTTP | Built-in | Custom controller needed |
| TTL/Auto-stop | Built-in | Custom scheduler needed |
| Multi-tenant | Built-in | Namespace isolation |
| API | REST + SDK | Build your own |

---

## Troubleshooting

### Common Issues

**1. KVM not available**
```bash
# Check KVM device
ls -la /dev/kvm
# If permission denied:
sudo chmod 666 /dev/kvm
# Or add user to kvm group:
sudo usermod -aG kvm $USER
```

**2. Devmapper not working**
```bash
# Check thin-pool exists
sudo dmsetup ls
# Recreate if missing
sudo dmsetup remove devpool
cd ~/scripts/devmapper && sudo ./create.sh
```

**3. Kata runtime not found**
```bash
# Verify shim exists
ls -la /usr/local/bin/containerd-shim-kata-fc-v2
# Check containerd config
sudo cat /etc/containerd/config.toml | grep kata
```

**4. Container fails to start**
```bash
# Check Kata logs
sudo journalctl -u containerd -f
# Check Firecracker logs
cat /var/log/kata-runtime.log
```

---

## References

- [Kata Containers Documentation](https://github.com/kata-containers/kata-containers/tree/main/docs)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker/tree/main/docs)
- [Firecracker Go SDK](https://github.com/firecracker-microvm/firecracker-go-sdk)
- [Morph Cloud API](https://cloud.morph.so/docs)
- [E2B Sandbox SDK](https://github.com/e2b-dev/e2b) (similar approach)

---

#kubernetes #kata-containers #firecracker #microvm #snapshot #virtualization
