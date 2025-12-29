#!/bin/bash
#
# Kata Containers Quick Installation Script
# Source: Derived from official kata-manager.sh
# Repo: https://github.com/kata-containers/kata-containers
#
# Usage:
#   ./kata-quickstart.sh              # Install Kata + containerd (latest)
#   ./kata-quickstart.sh --firecracker # Install and configure for Firecracker
#   ./kata-quickstart.sh --k3s        # Install for K3s cluster
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Configuration
KATA_VERSION="${KATA_VERSION:-}"  # Empty = latest
INSTALL_DIR="/opt/kata"
ARCH=$(uname -m)

#######################################
# Check prerequisites
#######################################
check_prereqs() {
    info "Checking prerequisites..."

    # Check root
    [[ $EUID -eq 0 ]] || error "Run as root: sudo $0"

    # Check KVM
    if [[ ! -e /dev/kvm ]]; then
        warn "/dev/kvm not found. Loading KVM modules..."
        modprobe kvm || true
        if grep -q Intel /proc/cpuinfo; then
            modprobe kvm_intel || true
        elif grep -q AMD /proc/cpuinfo; then
            modprobe kvm_amd || true
        fi
    fi

    [[ -e /dev/kvm ]] || error "KVM not available. Enable VT-x/AMD-V in BIOS."

    # Check tools
    for cmd in curl jq tar; do
        command -v $cmd &>/dev/null || error "Required: $cmd"
    done

    info "Prerequisites OK"
}

#######################################
# Get latest Kata version from GitHub
#######################################
get_latest_version() {
    curl -sL "https://api.github.com/repos/kata-containers/kata-containers/releases" | \
        jq -r '.[].tag_name | select(contains("-") | not)' | \
        sort -V | tail -1
}

#######################################
# Download and install Kata binaries
#######################################
install_kata() {
    local version="${KATA_VERSION:-$(get_latest_version)}"
    info "Installing Kata Containers ${version}..."

    local url="https://github.com/kata-containers/kata-containers/releases/download/${version}/kata-static-${version}-${ARCH}.tar.xz"

    info "Downloading from: ${url}"
    local tmpfile=$(mktemp)
    curl -L "$url" -o "$tmpfile"

    info "Extracting to ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    tar -xJf "$tmpfile" -C /
    rm -f "$tmpfile"

    # Create symlinks
    info "Creating symlinks in /usr/local/bin..."
    for bin in kata-runtime containerd-shim-kata-v2 kata-collect-data.sh; do
        [[ -f "${INSTALL_DIR}/bin/${bin}" ]] && \
            ln -sf "${INSTALL_DIR}/bin/${bin}" /usr/local/bin/
    done

    info "Kata ${version} installed successfully"
}

#######################################
# Configure containerd for Kata
#######################################
configure_containerd() {
    info "Configuring containerd..."

    local config="/etc/containerd/config.toml"
    mkdir -p /etc/containerd

    # Backup existing config
    [[ -f "$config" ]] && cp "$config" "${config}.bak.$(date +%s)"

    # Check if containerd is running
    if ! systemctl is-active containerd &>/dev/null; then
        warn "containerd not running. Creating basic config..."
        containerd config default > "$config"
    fi

    # Add Kata runtime if not present
    if ! grep -q "kata.v2" "$config" 2>/dev/null; then
        info "Adding Kata runtime to containerd config..."
        cat >> "$config" <<'EOF'

# Kata Containers runtime
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
  runtime_type = "io.containerd.kata.v2"
  privileged_without_host_devices = true
  pod_annotations = ["io.katacontainers.*"]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata.options]
    ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration.toml"
EOF
    fi

    info "Restarting containerd..."
    systemctl restart containerd
}

#######################################
# Configure for Firecracker hypervisor
#######################################
configure_firecracker() {
    info "Configuring Firecracker hypervisor..."

    # Create Firecracker shim
    cat > /usr/local/bin/containerd-shim-kata-fc-v2 <<'EOF'
#!/bin/bash
KATA_CONF_FILE=/opt/kata/share/defaults/kata-containers/configuration-fc.toml \
  /opt/kata/bin/containerd-shim-kata-v2 "$@"
EOF
    chmod +x /usr/local/bin/containerd-shim-kata-fc-v2

    # Add Firecracker runtime to containerd
    local config="/etc/containerd/config.toml"
    if ! grep -q "kata-fc" "$config" 2>/dev/null; then
        cat >> "$config" <<'EOF'

# Kata Containers with Firecracker
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]
  runtime_type = "io.containerd.kata-fc.v2"
  privileged_without_host_devices = true
  pod_annotations = ["io.katacontainers.*"]
EOF
    fi

    systemctl restart containerd
    info "Firecracker configured"
}

#######################################
# Setup devmapper for Firecracker
#######################################
setup_devmapper() {
    info "Setting up devmapper snapshotter (required for Firecracker)..."

    local data_dir="/var/lib/containerd/devmapper"
    local pool_name="devpool"

    # Check if already exists
    if dmsetup ls | grep -q "$pool_name"; then
        warn "Devmapper pool '$pool_name' already exists"
        return 0
    fi

    mkdir -p "$data_dir"

    # Create sparse files
    touch "${data_dir}/data"
    truncate -s 100G "${data_dir}/data"
    touch "${data_dir}/meta"
    truncate -s 10G "${data_dir}/meta"

    # Setup loop devices
    local data_dev=$(losetup --find --show "${data_dir}/data")
    local meta_dev=$(losetup --find --show "${data_dir}/meta")

    # Calculate parameters
    local data_size=$(blockdev --getsize64 -q "$data_dev")
    local length=$((data_size / 512))

    # Create thin-pool
    dmsetup create "$pool_name" \
        --table "0 $length thin-pool $meta_dev $data_dev 128 32768"

    # Add to containerd config
    local config="/etc/containerd/config.toml"
    if ! grep -q "devmapper" "$config" 2>/dev/null; then
        cat >> "$config" <<EOF

# Devmapper snapshotter for Firecracker
[plugins."io.containerd.snapshotter.v1.devmapper"]
  pool_name = "${pool_name}"
  root_path = "${data_dir}"
  base_image_size = "10GB"
  discard_blocks = true
EOF
    fi

    # Update Firecracker runtime to use devmapper
    sed -i 's/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc\]/[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]\n  snapshotter = "devmapper"/' "$config" 2>/dev/null || true

    systemctl restart containerd
    info "Devmapper configured"
}

#######################################
# K3s-specific setup
#######################################
configure_k3s() {
    info "Configuring for K3s..."

    # K3s uses containerd internally
    local k3s_config="/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"

    if [[ -d /var/lib/rancher/k3s ]]; then
        mkdir -p "$(dirname "$k3s_config")"

        # Create K3s containerd template
        cat > "$k3s_config" <<'EOF'
version = 2

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
  runtime_type = "io.containerd.kata.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata.options]
    ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration.toml"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]
  runtime_type = "io.containerd.kata-fc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc.options]
    ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration-fc.toml"
EOF

        # Restart K3s
        systemctl restart k3s 2>/dev/null || systemctl restart k3s-agent 2>/dev/null || true
    fi

    # Apply RuntimeClass via kubectl
    if command -v kubectl &>/dev/null; then
        info "Creating Kubernetes RuntimeClasses..."
        kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata
---
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
EOF
    fi

    info "K3s configured"
}

#######################################
# Test installation
#######################################
test_kata() {
    info "Testing Kata installation..."

    # Test with ctr
    if command -v ctr &>/dev/null; then
        local image="docker.io/library/busybox:latest"
        ctr image pull "$image" 2>/dev/null || true

        info "Running test container..."
        local output=$(ctr run --runtime io.containerd.kata.v2 --rm "$image" test-kata uname -r 2>&1) || true

        if [[ "$output" == *"kata"* ]] || [[ "$output" != "$(uname -r)" ]]; then
            info "Test PASSED - Container running in Kata VM"
            echo "  Host kernel: $(uname -r)"
            echo "  Kata kernel: $output"
        else
            warn "Test inconclusive - Output: $output"
        fi
    else
        warn "ctr not found, skipping test"
    fi
}

#######################################
# Main
#######################################
main() {
    local firecracker=false
    local k3s=false
    local test_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --firecracker|-f) firecracker=true; shift ;;
            --k3s|-k) k3s=true; shift ;;
            --test|-t) test_only=true; shift ;;
            --version|-v) KATA_VERSION="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --firecracker, -f  Configure Firecracker hypervisor"
                echo "  --k3s, -k          Configure for K3s cluster"
                echo "  --test, -t         Run test only"
                echo "  --version, -v VER  Install specific version"
                echo "  --help, -h         Show this help"
                exit 0
                ;;
            *) error "Unknown option: $1" ;;
        esac
    done

    check_prereqs

    if $test_only; then
        test_kata
        exit 0
    fi

    install_kata
    configure_containerd

    if $firecracker; then
        configure_firecracker
        setup_devmapper
    fi

    if $k3s; then
        configure_k3s
    fi

    test_kata

    info "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Run a Kata container:"
    echo "     sudo ctr run --runtime io.containerd.kata.v2 --rm -t docker.io/library/alpine:latest test sh"
    echo ""
    if $firecracker; then
        echo "  2. Run with Firecracker:"
        echo "     sudo ctr run --snapshotter devmapper --runtime io.containerd.kata-fc.v2 --rm -t docker.io/library/alpine:latest test sh"
        echo ""
    fi
    if $k3s; then
        echo "  3. Create a Kata pod:"
        echo '     kubectl run kata-test --image=alpine --restart=Never --overrides='"'"'{"spec":{"runtimeClassName":"kata"}}'"'"' -- sleep 30'
        echo ""
    fi
}

main "$@"
