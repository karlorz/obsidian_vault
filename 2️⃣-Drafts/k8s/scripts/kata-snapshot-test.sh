#!/bin/bash
#
# Kata Containers Snapshot Test Script
# Tests pause/snapshot/resume with Cloud Hypervisor (kata-clh)
#
# Usage:
#   ./kata-snapshot-test.sh create     # Create test pod
#   ./kata-snapshot-test.sh pause      # Pause VM
#   ./kata-snapshot-test.sh snapshot   # Create snapshot (must pause first)
#   ./kata-snapshot-test.sh resume     # Resume VM
#   ./kata-snapshot-test.sh status     # Check VM status
#   ./kata-snapshot-test.sh cleanup    # Delete pod and snapshots
#   ./kata-snapshot-test.sh demo       # Run full demo
#
set -euo pipefail

# Configuration
POD_NAME="${POD_NAME:-kata-snapshot-test}"
NAMESPACE="${NAMESPACE:-default}"
RUNTIME_CLASS="${RUNTIME_CLASS:-kata-clh}"  # kata-clh supports snapshots with overlayfs
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/tmp/kata-snapshots}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header() { echo -e "\n${BLUE}=== $* ===${NC}"; }

#######################################
# Get Cloud Hypervisor API socket path
#######################################
get_clh_socket() {
    local vm_id
    vm_id=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' 2>/dev/null | tr -d '-')

    if [[ -z "$vm_id" ]]; then
        # Try to find by listing
        local socket
        socket=$(find /run/vc/vm -name "clh-api.sock" 2>/dev/null | head -1)
        if [[ -n "$socket" ]]; then
            echo "$socket"
            return 0
        fi
        error "Pod $POD_NAME not found or not running with Kata"
        return 1
    fi

    # Find socket by VM directory
    local socket
    socket=$(find /run/vc/vm -name "clh-api.sock" 2>/dev/null | head -1)

    if [[ -z "$socket" ]]; then
        error "Cloud Hypervisor socket not found. Is the pod running with kata-clh?"
        return 1
    fi

    echo "$socket"
}

#######################################
# Create test pod
#######################################
create_pod() {
    header "Creating Test Pod"

    if kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
        warn "Pod $POD_NAME already exists"
        kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o wide
        return 0
    fi

    info "Creating pod with RuntimeClass: $RUNTIME_CLASS"

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
  labels:
    app: kata-snapshot-test
spec:
  runtimeClassName: $RUNTIME_CLASS
  containers:
  - name: test
    image: alpine:latest
    command:
    - /bin/sh
    - -c
    - |
      echo "Started at: \$(date)" > /tmp/start_time.txt
      counter=0
      while true; do
        echo "Counter: \$counter at \$(date)" >> /tmp/counter.log
        counter=\$((counter + 1))
        sleep 1
      done
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF

    info "Waiting for pod to be ready..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=120s

    info "Pod created successfully"
    kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o wide

    echo ""
    info "Verifying Kata VM kernel:"
    echo "  Host kernel:     $(uname -r)"
    echo "  Container kernel: $(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- uname -r)"
}

#######################################
# Get VM status
#######################################
get_status() {
    header "VM Status"

    local socket
    socket=$(get_clh_socket) || return 1

    info "Socket: $socket"

    local state
    state=$(curl -s --unix-socket "$socket" http://localhost/api/v1/vm.info | jq -r '.state')

    echo ""
    echo "VM State: $state"
    echo ""

    if [[ "$state" == "Running" ]]; then
        info "Container counter log (last 5 lines):"
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- tail -5 /tmp/counter.log 2>/dev/null || true
    fi
}

#######################################
# Pause VM
#######################################
pause_vm() {
    header "Pausing VM"

    local socket
    socket=$(get_clh_socket) || return 1

    local state
    state=$(curl -s --unix-socket "$socket" http://localhost/api/v1/vm.info | jq -r '.state')

    if [[ "$state" == "Paused" ]]; then
        warn "VM is already paused"
        return 0
    fi

    info "Current state: $state"
    info "Sending pause command..."

    curl -s --unix-socket "$socket" -X PUT http://localhost/api/v1/vm.pause

    sleep 1

    state=$(curl -s --unix-socket "$socket" http://localhost/api/v1/vm.info | jq -r '.state')

    if [[ "$state" == "Paused" ]]; then
        info "VM paused successfully"
    else
        error "Failed to pause VM. State: $state"
        return 1
    fi
}

#######################################
# Resume VM
#######################################
resume_vm() {
    header "Resuming VM"

    local socket
    socket=$(get_clh_socket) || return 1

    local state
    state=$(curl -s --unix-socket "$socket" http://localhost/api/v1/vm.info | jq -r '.state')

    if [[ "$state" == "Running" ]]; then
        warn "VM is already running"
        return 0
    fi

    info "Current state: $state"
    info "Sending resume command..."

    curl -s --unix-socket "$socket" -X PUT http://localhost/api/v1/vm.resume

    sleep 1

    state=$(curl -s --unix-socket "$socket" http://localhost/api/v1/vm.info | jq -r '.state')

    if [[ "$state" == "Running" ]]; then
        info "VM resumed successfully"
    else
        error "Failed to resume VM. State: $state"
        return 1
    fi
}

#######################################
# Create snapshot
#######################################
create_snapshot() {
    header "Creating Snapshot"

    local socket
    socket=$(get_clh_socket) || return 1

    local state
    state=$(curl -s --unix-socket "$socket" http://localhost/api/v1/vm.info | jq -r '.state')

    if [[ "$state" != "Paused" ]]; then
        warn "VM must be paused before snapshot. Current state: $state"
        info "Pausing VM first..."
        pause_vm
    fi

    # Create snapshot directory with timestamp
    local snapshot_name="snapshot-$(date +%Y%m%d-%H%M%S)"
    local snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}"

    mkdir -p "$snapshot_path"

    info "Creating snapshot at: $snapshot_path"

    local response
    response=$(curl -s --unix-socket "$socket" -X PUT \
        -H "Content-Type: application/json" \
        -d "{\"destination_url\": \"file://${snapshot_path}\"}" \
        http://localhost/api/v1/vm.snapshot)

    if [[ -n "$response" ]]; then
        error "Snapshot failed: $response"
        return 1
    fi

    info "Snapshot created successfully!"
    echo ""
    echo "Snapshot files:"
    ls -lah "$snapshot_path"
    echo ""

    local total_size
    total_size=$(du -sh "$snapshot_path" | cut -f1)
    info "Total snapshot size: $total_size"

    # Save metadata
    cat > "${snapshot_path}/metadata.json" <<EOF
{
    "pod_name": "$POD_NAME",
    "namespace": "$NAMESPACE",
    "runtime_class": "$RUNTIME_CLASS",
    "timestamp": "$(date -Iseconds)",
    "snapshot_path": "$snapshot_path"
}
EOF

    echo ""
    info "Snapshot saved to: $snapshot_path"
}

#######################################
# List snapshots
#######################################
list_snapshots() {
    header "Available Snapshots"

    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        warn "No snapshots directory found at $SNAPSHOT_DIR"
        return 0
    fi

    local count=0
    for snap_dir in "$SNAPSHOT_DIR"/snapshot-*; do
        if [[ -d "$snap_dir" ]]; then
            count=$((count + 1))
            local name=$(basename "$snap_dir")
            local size=$(du -sh "$snap_dir" 2>/dev/null | cut -f1)
            local timestamp=""

            if [[ -f "${snap_dir}/metadata.json" ]]; then
                timestamp=$(jq -r '.timestamp' "${snap_dir}/metadata.json" 2>/dev/null || echo "unknown")
            fi

            echo "  $count. $name ($size) - $timestamp"
        fi
    done

    if [[ $count -eq 0 ]]; then
        warn "No snapshots found"
    else
        echo ""
        info "Total: $count snapshot(s)"
    fi
}

#######################################
# Cleanup
#######################################
cleanup() {
    header "Cleanup"

    info "Deleting pod $POD_NAME..."
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true

    if [[ -d "$SNAPSHOT_DIR" ]]; then
        read -p "Delete all snapshots in $SNAPSHOT_DIR? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$SNAPSHOT_DIR"
            info "Snapshots deleted"
        fi
    fi

    info "Cleanup complete"
}

#######################################
# Run full demo
#######################################
run_demo() {
    header "Kata Containers Snapshot Demo"
    echo "Runtime: $RUNTIME_CLASS"
    echo ""

    # Step 1: Create pod
    create_pod
    sleep 3

    # Step 2: Show initial state
    header "Step 1: Initial State"
    get_status

    # Wait for counter to increment
    info "Waiting 5 seconds for counter to increment..."
    sleep 5

    header "Step 2: Counter After 5 Seconds"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- tail -3 /tmp/counter.log

    # Step 3: Pause
    header "Step 3: Pause VM"
    pause_vm

    # Step 4: Create snapshot
    header "Step 4: Create Snapshot"
    create_snapshot

    # Step 5: Resume
    header "Step 5: Resume VM"
    resume_vm

    # Wait and verify counter continues
    info "Waiting 3 seconds..."
    sleep 3

    header "Step 6: Verify Counter Continued"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- tail -5 /tmp/counter.log

    header "Demo Complete!"
    echo ""
    echo "Summary:"
    echo "  - Pod created with $RUNTIME_CLASS runtime"
    echo "  - VM paused (freezes all processes)"
    echo "  - Full memory snapshot saved to disk"
    echo "  - VM resumed (processes continue from exact state)"
    echo ""
    list_snapshots
}

#######################################
# Main
#######################################
case "${1:-help}" in
    create)
        create_pod
        ;;
    pause)
        pause_vm
        ;;
    resume)
        resume_vm
        ;;
    snapshot)
        create_snapshot
        ;;
    status)
        get_status
        ;;
    list)
        list_snapshots
        ;;
    cleanup)
        cleanup
        ;;
    demo)
        run_demo
        ;;
    help|*)
        cat <<EOF
Kata Containers Snapshot Test Script

Usage: $0 <command>

Commands:
  create     Create test pod with kata-clh runtime
  pause      Pause the VM (freeze all processes)
  resume     Resume the VM (continue from paused state)
  snapshot   Create full memory + state snapshot (VM must be paused)
  status     Show current VM status
  list       List available snapshots
  cleanup    Delete pod and optionally snapshots
  demo       Run full demonstration

Environment Variables:
  POD_NAME       Pod name (default: kata-snapshot-test)
  NAMESPACE      Kubernetes namespace (default: default)
  RUNTIME_CLASS  RuntimeClass to use (default: kata-clh)
  SNAPSHOT_DIR   Directory for snapshots (default: /tmp/kata-snapshots)

Examples:
  $0 demo                          # Run full demo
  $0 create && sleep 10 && $0 pause && $0 snapshot && $0 resume
  RUNTIME_CLASS=kata-qemu $0 create  # Use QEMU instead

Note: This script must be run on the Kubernetes node where the pod is scheduled.
EOF
        ;;
esac
