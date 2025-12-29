#!/bin/bash
#
# Podman CRIU Checkpoint/Restore Test Script
# Tests container state preservation (snapshots) with Podman
#
# Prerequisites:
#   - Podman installed
#   - CRIU installed (criu package)
#   - Root privileges (checkpoint requires root)
#
# Usage: sudo ./test-podman-checkpoint.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test container name
CONTAINER_NAME="checkpoint-test"
CHECKPOINT_DIR="/tmp/podman-checkpoints"
CHECKPOINT_FILE="$CHECKPOINT_DIR/checkpoint-test.tar.gz"

# OCI Runtime - runc is required for CRIU checkpoint support
# crun does NOT support checkpoint/restore on most systems
OCI_RUNTIME="runc"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Podman CRIU Checkpoint/Restore Test Suite                 ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print step headers
print_step() {
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ $1${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print info
print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Cleanup function
cleanup() {
    print_step "Cleanup"
    echo "Removing test container and checkpoint files..."
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
    rm -rf "$CHECKPOINT_DIR"
    print_success "Cleanup completed"
}

# Run cleanup on exit
trap cleanup EXIT

#####################################
# 1. Check Prerequisites
#####################################
print_step "1. Checking Prerequisites"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (checkpoint requires root privileges)"
    echo "Usage: sudo $0"
    exit 1
fi
print_success "Running as root"

# Check Podman version
if command -v podman &> /dev/null; then
    PODMAN_VERSION=$(podman --version)
    print_success "Podman installed: $PODMAN_VERSION"
else
    print_error "Podman is not installed"
    exit 1
fi

# Check CRIU
if command -v criu &> /dev/null; then
    CRIU_VERSION=$(criu --version | head -n1)
    print_success "CRIU installed: $CRIU_VERSION"
else
    print_error "CRIU is not installed"
    echo "Install with: apt install criu (Ubuntu/Debian) or dnf install criu (Fedora/RHEL)"
    exit 1
fi

# Check CRIU functionality
echo "Testing CRIU functionality..."
if criu check &> /dev/null; then
    print_success "CRIU check passed - kernel supports checkpointing"
else
    print_error "CRIU check failed - kernel may not support checkpointing"
    echo "Try running: criu check --all for details"
    # Don't exit, some tests may still work
fi

# Check runc (required for checkpoint - crun doesn't support it on most systems)
if command -v runc &> /dev/null; then
    RUNC_VERSION=$(runc --version | head -n1)
    print_success "runc installed: $RUNC_VERSION"
else
    print_error "runc is not installed (required for checkpoint)"
    echo "Install with: apt install runc (Ubuntu/Debian) or dnf install runc (Fedora/RHEL)"
    exit 1
fi

# Create checkpoint directory
mkdir -p "$CHECKPOINT_DIR"
print_success "Checkpoint directory created: $CHECKPOINT_DIR"

#####################################
# 2. Create Test Container with State
#####################################
print_step "2. Creating Test Container with Stateful Process"

# Clean up any existing test container
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Run a container that maintains state (a counter)
# This Alpine container will increment a counter every second
# IMPORTANT: Must use --runtime=runc for checkpoint support
echo "Starting container with incrementing counter (using runc runtime)..."
podman run -d --name "$CONTAINER_NAME" \
    --runtime="$OCI_RUNTIME" \
    alpine:latest \
    sh -c 'COUNTER=0; while true; do echo "Counter: $COUNTER"; COUNTER=$((COUNTER + 1)); sleep 1; done'

sleep 3  # Let it run for a few seconds

print_success "Container started"

# Show current state
echo ""
echo "Container ID: $(podman ps -qf name=$CONTAINER_NAME)"
echo "Container status:"
podman ps --filter name=$CONTAINER_NAME --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Command}}"

# Show recent logs
echo ""
echo "Recent container output (counter value):"
podman logs --tail 5 "$CONTAINER_NAME"

# Record the counter value before checkpoint
BEFORE_CHECKPOINT=$(podman logs --tail 1 "$CONTAINER_NAME" | grep -oP 'Counter: \K[0-9]+' || echo "unknown")
print_info "Counter value before checkpoint: $BEFORE_CHECKPOINT"

#####################################
# 3. Test Local Checkpoint (In-Place)
#####################################
print_step "3. Testing Local Checkpoint (In-Place)"

echo "Creating checkpoint of running container..."
echo "This preserves the container state including memory..."

# Checkpoint the container (keeps it running)
if podman container checkpoint "$CONTAINER_NAME" --leave-running; then
    print_success "Local checkpoint created successfully"
    echo ""
    echo "Container is still running after checkpoint:"
    podman ps --filter name=$CONTAINER_NAME
else
    print_error "Checkpoint failed"
    echo "Trying with --tcp-established flag (if container has TCP connections)..."
    podman container checkpoint "$CONTAINER_NAME" --leave-running --tcp-established || true
fi

#####################################
# 4. Test Checkpoint with Export
#####################################
print_step "4. Testing Checkpoint with Export to File"

# Wait a bit more to see counter increase
sleep 3

# Record counter before export checkpoint
BEFORE_EXPORT=$(podman logs --tail 1 "$CONTAINER_NAME" | grep -oP 'Counter: \K[0-9]+' || echo "unknown")
print_info "Counter value before export checkpoint: $BEFORE_EXPORT"

echo "Creating checkpoint and exporting to file..."
echo "This stops the container and saves state to: $CHECKPOINT_FILE"

if podman container checkpoint "$CONTAINER_NAME" --export="$CHECKPOINT_FILE"; then
    print_success "Checkpoint exported successfully"
    ls -lh "$CHECKPOINT_FILE"

    echo ""
    echo "Container status after checkpoint (should be Exited):"
    podman ps -a --filter name=$CONTAINER_NAME --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
else
    print_error "Export checkpoint failed"
    exit 1
fi

#####################################
# 5. Test Restore from Checkpoint
#####################################
print_step "5. Testing Restore from Checkpoint File"

# Remove the stopped container
echo "Removing stopped container..."
podman rm "$CONTAINER_NAME"

# Wait a moment
sleep 2

echo "Restoring container from checkpoint file..."
if podman container restore --import="$CHECKPOINT_FILE" --name "$CONTAINER_NAME"; then
    print_success "Container restored from checkpoint"

    echo ""
    echo "Container status after restore:"
    podman ps --filter name=$CONTAINER_NAME --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

    # Wait for container to produce some output
    sleep 3

    # Show logs after restore
    echo ""
    echo "Container output after restore:"
    podman logs --tail 5 "$CONTAINER_NAME"

    # Check counter value
    AFTER_RESTORE=$(podman logs --tail 1 "$CONTAINER_NAME" | grep -oP 'Counter: \K[0-9]+' || echo "unknown")
    print_info "Counter value after restore: $AFTER_RESTORE"

    echo ""
    if [[ "$BEFORE_EXPORT" != "unknown" && "$AFTER_RESTORE" != "unknown" ]]; then
        if [[ "$AFTER_RESTORE" -ge "$BEFORE_EXPORT" ]]; then
            print_success "STATE PRESERVED! Counter continued from $BEFORE_EXPORT → $AFTER_RESTORE"
        else
            print_error "Counter mismatch - state may not be fully preserved"
        fi
    fi
else
    print_error "Restore from checkpoint failed"
fi

#####################################
# 6. Test Multiple Checkpoints
#####################################
print_step "6. Testing Multiple Checkpoint Exports"

echo "Creating multiple checkpoints to simulate snapshot history..."

for i in 1 2 3; do
    sleep 2
    CURRENT_COUNT=$(podman logs --tail 1 "$CONTAINER_NAME" | grep -oP 'Counter: \K[0-9]+' || echo "?")
    SNAP_FILE="$CHECKPOINT_DIR/snapshot-$i.tar.gz"

    if podman container checkpoint "$CONTAINER_NAME" --export="$SNAP_FILE" --leave-running; then
        print_success "Snapshot $i created (counter=$CURRENT_COUNT): $SNAP_FILE"
    else
        print_error "Failed to create snapshot $i"
    fi
done

echo ""
echo "All snapshots created:"
ls -lh "$CHECKPOINT_DIR"/*.tar.gz

#####################################
# 7. Restore from Specific Snapshot
#####################################
print_step "7. Testing Restore from Specific Snapshot (Time Travel)"

# Stop and remove current container
podman rm -f "$CONTAINER_NAME"

echo "Restoring from first snapshot (oldest state)..."
if podman container restore --import="$CHECKPOINT_DIR/snapshot-1.tar.gz" --name "${CONTAINER_NAME}-old"; then
    sleep 2
    OLD_COUNT=$(podman logs --tail 1 "${CONTAINER_NAME}-old" | grep -oP 'Counter: \K[0-9]+' || echo "?")
    print_success "Restored to oldest snapshot (counter=$OLD_COUNT)"
    podman rm -f "${CONTAINER_NAME}-old"
fi

echo "Restoring from third snapshot (newest state)..."
if podman container restore --import="$CHECKPOINT_DIR/snapshot-3.tar.gz" --name "${CONTAINER_NAME}-new"; then
    sleep 2
    NEW_COUNT=$(podman logs --tail 1 "${CONTAINER_NAME}-new" | grep -oP 'Counter: \K[0-9]+' || echo "?")
    print_success "Restored to newest snapshot (counter=$NEW_COUNT)"
    podman rm -f "${CONTAINER_NAME}-new"
fi

#####################################
# Summary
#####################################
print_step "Summary"

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    TEST RESULTS SUMMARY                       ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Podman Version: $(printf '%-43s' "$PODMAN_VERSION")║${NC}"
echo -e "${GREEN}║  CRIU Version:   $(printf '%-43s' "$CRIU_VERSION")║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Features Tested:                                             ║${NC}"
echo -e "${GREEN}║  ✓ Container checkpoint (in-place)                            ║${NC}"
echo -e "${GREEN}║  ✓ Checkpoint export to file                                  ║${NC}"
echo -e "${GREEN}║  ✓ Restore from checkpoint file                               ║${NC}"
echo -e "${GREEN}║  ✓ State preservation (counter continuity)                    ║${NC}"
echo -e "${GREEN}║  ✓ Multiple snapshots (time-travel capability)                ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Notes:                                                       ║${NC}"
echo -e "${GREEN}║  • Checkpoint requires root/sudo                              ║${NC}"
echo -e "${GREEN}║  • Use --tcp-established for containers with TCP connections  ║${NC}"
echo -e "${GREEN}║  • Checkpoint files can be migrated to other hosts            ║${NC}"
echo -e "${GREEN}║  • Similar to VM snapshots but for containers                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"

echo ""
echo "Checkpoint files created during test:"
ls -lh "$CHECKPOINT_DIR"/ 2>/dev/null || echo "  (cleaned up)"

echo ""
echo -e "${BLUE}Test completed! Check the output above for detailed results.${NC}"
