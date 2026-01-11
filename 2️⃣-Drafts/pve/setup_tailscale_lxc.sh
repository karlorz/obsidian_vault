#!/bin/bash
set -e

# ============================================================================
# Tailscale App Connector Setup for PVE LXCs
# 
# Usage:
#   ./setup_tailscale_lxc.sh           # Full setup + verification
#   ./setup_tailscale_lxc.sh --attach <VMID>  # Attach hook to existing VM/template
#   ./setup_tailscale_lxc.sh --help    # Show help
# ============================================================================

# Configuration
PVE_HOST_IP="10.10.0.9"           # Your PVE Host IP
TAILSCALE_INTERFACE="tailscale0"  # Tailscale interface name
SNIPPET_DIR="/var/lib/vz/snippets"
HOOK_SCRIPT_NAME="tailscale-hook.sh"
TEMPLATE_VMID=9000                # Default template for verification

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

show_help() {
    cat << 'EOF'
Tailscale App Connector Setup for PVE LXCs

USAGE:
    ./setup_tailscale_lxc.sh [OPTIONS]

OPTIONS:
    (no args)       Full setup: configure host, create hook, run verification
    --attach VMID   Attach hook script to an existing VM or template
    --help          Show this help message

EXAMPLES:
    # Full setup with verification
    ./setup_tailscale_lxc.sh

    # Attach hook to template 9000
    ./setup_tailscale_lxc.sh --attach 9000

    # Attach hook to running LXC 105
    ./setup_tailscale_lxc.sh --attach 105
EOF
    exit 0
}

# ============================================================================
# Attach Hook to VMID
# ============================================================================
attach_hook() {
    local vmid="$1"
    
    if ! pct config "$vmid" &>/dev/null; then
        error "VMID $vmid not found!"
    fi
    
    log "Attaching hook script to VMID $vmid..."
    pct set "$vmid" -hookscript "local:snippets/$HOOK_SCRIPT_NAME"
    log "✅ Hook script attached to VMID $vmid"
    log "   Containers cloned from this template will auto-configure on start."
}

# ============================================================================
# Create Hook Script
# ============================================================================
create_hook_script() {
    log "Creating LXC Hook Script..."
    mkdir -p "$SNIPPET_DIR"

    cat <<'HOOKEOF' > "$SNIPPET_DIR/$HOOK_SCRIPT_NAME"
#!/bin/bash
vmid="$1"
phase="$2"
PVE_HOST_IP="10.10.0.9"

if [[ "$phase" == "post-start" ]]; then
    echo "[$vmid] Tailscale Hook: Configuring routes, DNS, and transparent proxy..."
    
    # Wait for network to be ready inside LXC
    echo "[$vmid] Waiting for network..."
    for i in {1..30}; do
        if lxc-attach -n $vmid -- ip route add 100.64.0.0/10 via $PVE_HOST_IP 2>/dev/null; then
            echo "[$vmid] Route added successfully."
            break
        fi
        sleep 1
    done
    
    # Force DNS to PVE Host
    lxc-attach -n $vmid -- bash -c "echo 'nameserver $PVE_HOST_IP' > /etc/resolv.conf"
    
    # Install redsocks for transparent TCP proxying (if not present)
    if ! lxc-attach -n $vmid -- which redsocks > /dev/null 2>&1; then
        echo "[$vmid] Installing redsocks..."
        lxc-attach -n $vmid -- apt-get update -qq
        lxc-attach -n $vmid -- apt-get install -y -qq redsocks iptables
    fi
    
    # Create redsocks config
    lxc-attach -n $vmid -- bash -c "cat > /etc/redsocks.conf << 'RSCONF'
base {
    log_debug = off;
    log_info = off;
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = $PVE_HOST_IP;
    port = 1055;
    type = socks5;
}
RSCONF"
    
    # Create iptables rules script
    lxc-attach -n $vmid -- bash -c 'cat > /usr/local/bin/redsocks-fw.sh << '\''FWEOF'\''
#!/bin/bash
iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 100.64.0.0/10 -j RETURN
iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
FWEOF
chmod +x /usr/local/bin/redsocks-fw.sh'
    
    # Create systemd service
    lxc-attach -n $vmid -- bash -c 'cat > /etc/systemd/system/redsocks.service << '\''SVCEOF'\''
[Unit]
Description=Redsocks Transparent Proxy
After=network.target

[Service]
Type=forking
# Apply iptables rules before starting
ExecStartPre=/usr/local/bin/redsocks-fw.sh
ExecStart=/usr/sbin/redsocks -c /etc/redsocks.conf
# Ensure rules are cleaned up on stop
ExecStopPost=/sbin/iptables -t nat -F REDSOCKS
ExecStopPost=/sbin/iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF'
    
    # Enable and start redsocks
    lxc-attach -n $vmid -- systemctl daemon-reload
    lxc-attach -n $vmid -- systemctl enable redsocks
    lxc-attach -n $vmid -- systemctl start redsocks
    
    echo "[$vmid] Tailscale Hook: Done. All TCP traffic routes through proxy."
fi
HOOKEOF

    chmod +x "$SNIPPET_DIR/$HOOK_SCRIPT_NAME"
    log "Hook script created at $SNIPPET_DIR/$HOOK_SCRIPT_NAME"
}

# ============================================================================
# Configure PVE Host
# ============================================================================
configure_host() {
    log "Configuring PVE Host..."

    # Install Tailscale if needed
    if ! command -v tailscale &> /dev/null; then
        log "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        log "Tailscale already installed."
    fi

    # Configure Tailscale
    if ! tailscale status &> /dev/null; then
        log "Running 'tailscale up'... authenticate via the link below:"
        tailscale up --accept-dns=true --accept-routes=true
    else
        log "Tailscale is up."
        tailscale set --accept-routes=true
        log "Enabled --accept-routes for App Connectors."
    fi

    # Install dnsmasq if needed
    if ! command -v dnsmasq &> /dev/null; then
        log "Installing dnsmasq..."
        apt update && apt install dnsmasq -y
    fi

    # Configure dnsmasq for MagicDNS forwarding
    log "Configuring dnsmasq..."
    cat > /etc/dnsmasq.d/01-tailscale.conf << 'DNSEOF'
interface=vmbr0
server=100.100.100.100
domain-needed
bogus-priv
DNSEOF
    systemctl restart dnsmasq

    # Enable IP forwarding
    log "Enabling IP forwarding..."
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
    sysctl -p /etc/sysctl.d/99-tailscale.conf

    # IPTables Masquerading
    if ! iptables -t nat -C POSTROUTING -o $TAILSCALE_INTERFACE -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o $TAILSCALE_INTERFACE -j MASQUERADE
        log "Added MASQUERADE rule."
        if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y
        fi
        netfilter-persistent save
    fi

    # Configure SOCKS5 proxy
    log "Configuring SOCKS5 proxy..."
    mkdir -p /etc/systemd/system/tailscaled.service.d
    cat > /etc/systemd/system/tailscaled.service.d/socks5.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641 --socks5-server=10.10.0.9:1055 --outbound-http-proxy-listen=10.10.0.9:1055
EOF
    systemctl daemon-reload
    systemctl restart tailscaled
    sleep 3
    if ss -tlnp | grep -q ':1055'; then
        log "SOCKS5 proxy listening on 10.10.0.9:1055"
    else
        warn "SOCKS5 proxy may not be running"
    fi
}

# ============================================================================
# Verification
# ============================================================================
run_verification() {
    log "Starting Verification..."
    
    if ! pct config $TEMPLATE_VMID &>/dev/null; then
        warn "Template VMID $TEMPLATE_VMID not found. Skipping verification."
        return
    fi

    NEXT_VMID=$(pvesh get /cluster/nextid)
    log "Cloning VMID $TEMPLATE_VMID to new VMID $NEXT_VMID..."
    pct clone $TEMPLATE_VMID $NEXT_VMID --hostname "tailscale-test-$NEXT_VMID" --full 0
    
    log "Setting hookscript..."
    pct set $NEXT_VMID -hookscript "local:snippets/$HOOK_SCRIPT_NAME"
    
    log "Starting container $NEXT_VMID..."
    pct start $NEXT_VMID
    
    log "Waiting 15 seconds for startup and hook execution..."
    sleep 15

    log "Verifying Routes..."
    if pct exec $NEXT_VMID -- ip route show 100.64.0.0/10 | grep -q "via $PVE_HOST_IP"; then
        log "✅ Route verification PASSED"
    else
        warn "❌ Route verification FAILED"
    fi

    log "Verifying DNS..."
    if pct exec $NEXT_VMID -- cat /etc/resolv.conf | grep -q "nameserver $PVE_HOST_IP"; then
        log "✅ DNS verification PASSED"
    else
        warn "❌ DNS verification FAILED"
    fi

    log ""
    log "--- Setup Complete ---"
    log "Test container: pct exec $NEXT_VMID -- curl https://api.ipify.org"
    log "Delete when done: pct destroy $NEXT_VMID"
}

# ============================================================================
# Main
# ============================================================================
case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --attach)
        if [ -z "${2:-}" ]; then
            error "Usage: $0 --attach <VMID>"
        fi
        create_hook_script
        attach_hook "$2"
        ;;
    *)
        configure_host
        create_hook_script
        run_verification
        ;;
esac
