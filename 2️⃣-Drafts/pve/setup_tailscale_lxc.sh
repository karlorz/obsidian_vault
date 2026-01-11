#!/bin/bash
set -e

# Configuration
PVE_HOST_IP="10.10.0.9"           # Your PVE Host IP
TAILSCALE_INTERFACE="tailscale0"  # Tailscale interface name
SNIPPET_DIR="/var/lib/vz/snippets"
HOOK_SCRIPT_NAME="tailscale-hook.sh"
TEMPLATE_VMID=9000                # The template to clone from

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# 1. Host Configuration: DNS & Routing
log "Configuring PVE Host..."

# Check/Install Tailscale
if ! command -v tailscale &> /dev/null; then
    log "Tailscale not found. Installing..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log "Tailscale installed."
else
    log "Tailscale is already installed."
fi

# Check Tailscale Status
if ! tailscale status &> /dev/null; then
    log "Tailscale is not logged in."
    log "Running 'tailscale up'... properly authenticate via the link below:"
    tailscale up --accept-dns=true --accept-routes=true
else
    log "Tailscale is up and running."
    # Enable accept-routes for App Connector support
    tailscale set --accept-routes=true
    log "Enabled --accept-routes for App Connectors."
fi

# Install dnsmasq if missing
if ! command -v dnsmasq &> /dev/null; then
    log "Installing dnsmasq..."
    apt update && apt install dnsmasq -y
else
    log "dnsmasq is already installed."
fi

# Configure dnsmasq
log "Configuring dnsmasq service..."
cat <<EOF > /etc/dnsmasq.d/01-tailscale.conf
# Listen on vmbr0 so standard LXCs can query 10.10.0.9
interface=vmbr0
# Forward EVERYTHING to Tailscale's MagicDNS
server=100.100.100.100
domain-needed
bogus-priv
EOF

systemctl restart dnsmasq
log "dnsmasq restarted."

# Enable IP Forwarding
log "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward = 1' | tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf

# IPTables Masquerading
log "Configuring IPTables Masquerading..."
if ! iptables -t nat -C POSTROUTING -o $TAILSCALE_INTERFACE -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o $TAILSCALE_INTERFACE -j MASQUERADE
    log "Added MASQUERADE rule."
    
    # Persist rules
    if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
        log "Installing iptables-persistent..."
        DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y
    fi
    netfilter-persistent save
else
    log "MASQUERADE rule already exists."
fi

# 2. Configure Tailscale SOCKS5 Proxy
log "Configuring Tailscale SOCKS5 proxy..."
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
    log "WARNING: SOCKS5 proxy may not be running"
fi

# 2. Create Hook Script
log "Creating LXC Hook Script..."
mkdir -p "$SNIPPET_DIR"

cat <<EOF > "$SNIPPET_DIR/$HOOK_SCRIPT_NAME"
#!/bin/bash
vmid="\$1"
phase="\$2"

if [[ "\$phase" == "post-start" ]]; then
    echo "[\$vmid] Tailscale Hook: Configuring routes, DNS, and proxy..."
    
    # Wait for network to be ready inside LXC (Retry loop)
    echo "[\$vmid] Waiting for network..."
    for i in {1..30}; do
        if lxc-attach -n \$vmid -- ip route add 100.64.0.0/10 via $PVE_HOST_IP 2>/dev/null; then
            echo "[\$vmid] Route added successfully."
            break
        fi
        sleep 1
    done
    
    # 2. Force DNS to PVE Host ($PVE_HOST_IP)
    lxc-attach -n \$vmid -- bash -c "echo 'nameserver $PVE_HOST_IP' > /etc/resolv.conf"
    
    # 3. Configure Proxy environment for App Connectors
    # This routes HTTP/HTTPS traffic through Tailscale's SOCKS5 proxy
    lxc-attach -n \$vmid -- bash -c "cat >> /etc/environment << 'ENVEOF'
ALL_PROXY=socks5://$PVE_HOST_IP:1055
HTTP_PROXY=http://$PVE_HOST_IP:1055
HTTPS_PROXY=http://$PVE_HOST_IP:1055
http_proxy=http://$PVE_HOST_IP:1055
https_proxy=http://$PVE_HOST_IP:1055
ENVEOF"
    
    # Also set for current session in common profile (for interactive shells)
    lxc-attach -n \$vmid -- bash -c "cat >> /etc/profile.d/tailscale-proxy.sh << 'PROFEOF'
export ALL_PROXY=socks5://$PVE_HOST_IP:1055
export HTTP_PROXY=http://$PVE_HOST_IP:1055
export HTTPS_PROXY=http://$PVE_HOST_IP:1055
export http_proxy=http://$PVE_HOST_IP:1055
export https_proxy=http://$PVE_HOST_IP:1055
PROFEOF"
    
    # 4. Configure curl to use proxy by default (system-wide .curlrc)
    lxc-attach -n \$vmid -- bash -c "echo 'proxy = socks5://10.10.0.9:1055' > /etc/curlrc"
    
    # 5. Also set for root user's curlrc
    lxc-attach -n \$vmid -- bash -c "echo 'proxy = socks5://10.10.0.9:1055' > /root/.curlrc"
    
    # 6. Configure apt to use proxy
    lxc-attach -n \$vmid -- bash -c "cat > /etc/apt/apt.conf.d/99proxy << 'APTEOF'
Acquire::http::proxy \"socks5h://10.10.0.9:1055\";
Acquire::https::proxy \"socks5h://10.10.0.9:1055\";
APTEOF"
    
    # 7. Install and configure redsocks for transparent proxy (ALL TCP traffic)
    # Check if redsocks is available, install if not
    if lxc-attach -n \$vmid -- which redsocks > /dev/null 2>&1; then
        echo "[\$vmid] redsocks already installed"
    else
        echo "[\$vmid] Installing redsocks for transparent proxy..."
        lxc-attach -n \$vmid -- apt-get update -qq
        lxc-attach -n \$vmid -- apt-get install -y -qq redsocks iptables
    fi
    
    # Create redsocks config
    lxc-attach -n \$vmid -- bash -c "cat > /etc/redsocks.conf << 'RSCONF'
base {
    log_debug = off;
    log_info = off;
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 10.10.0.9;
    port = 1055;
    type = socks5;
}
RSCONF"
    
    # Create iptables rules script
    lxc-attach -n \$vmid -- bash -c "cat > /usr/local/bin/redsocks-fw.sh << 'FWEOF'
#!/bin/bash
# Create REDSOCKS chain
iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS

# Exclude local/private networks
iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 100.64.0.0/10 -j RETURN
iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN

# Redirect all other TCP to redsocks
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345

# Apply to all outbound TCP
iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
FWEOF
chmod +x /usr/local/bin/redsocks-fw.sh"
    
    # Create systemd service for redsocks
    lxc-attach -n \$vmid -- bash -c "cat > /etc/systemd/system/redsocks.service << 'SVCEOF'
[Unit]
Description=Redsocks Transparent Proxy
After=network.target

[Service]
Type=forking
ExecStartPre=/usr/local/bin/redsocks-fw.sh
ExecStart=/usr/sbin/redsocks -c /etc/redsocks.conf
ExecStopPost=/sbin/iptables -t nat -F REDSOCKS
Restart=on-failure

[Install]
WantedBy=multi-user.target
SVCEOF"
    
    # Enable and start redsocks
    lxc-attach -n \$vmid -- systemctl daemon-reload
    lxc-attach -n \$vmid -- systemctl enable redsocks
    lxc-attach -n \$vmid -- systemctl start redsocks
    
    echo "[\$vmid] Tailscale Hook: Done. All TCP traffic now routes through proxy."
fi
EOF

chmod +x "$SNIPPET_DIR/$HOOK_SCRIPT_NAME"
log "Hook script created at $SNIPPET_DIR/$HOOK_SCRIPT_NAME"

# 3. Verification: Clone and Test
log "Starting Verification..."

# Check if template 9000 exists
if ! pct config $TEMPLATE_VMID &>/dev/null; then
    error "Template VMID $TEMPLATE_VMID not found! Cannot proceed with verification test."
fi

# Find next available VMID
NEXT_VMID=$(pvesh get /cluster/nextid)
log "Cloning VMID $TEMPLATE_VMID to new VMID $NEXT_VMID..."

# Clone
pct clone $TEMPLATE_VMID $NEXT_VMID --hostname "tailscale-test-$NEXT_VMID" --full 1
log "Clone complete."

# Set Hookscript
log "Setting hookscript..."
pct set $NEXT_VMID -hookscript "local:snippets/$HOOK_SCRIPT_NAME"

# Start Container
log "Starting container $NEXT_VMID..."
pct start $NEXT_VMID

# Wait for startup and hook execution
log "Waiting 10 seconds for container startup and hook execution..."
sleep 10

# Verify Route
log "Verifying Routes inside container..."
ROUTE_CHECK=$(pct exec $NEXT_VMID -- ip route show 100.64.0.0/10)
if [[ $ROUTE_CHECK == *"via $PVE_HOST_IP"* ]]; then
    log "✅ Route verification PASSED: $ROUTE_CHECK"
else
    log "❌ Route verification FAILED. Output: $ROUTE_CHECK"
fi

# Verify DNS
log "Verifying DNS inside container..."
DNS_CHECK=$(pct exec $NEXT_VMID -- cat /etc/resolv.conf)
if [[ $DNS_CHECK == *"nameserver $PVE_HOST_IP"* ]]; then
    log "✅ DNS verification PASSED."
else
    log "❌ DNS verification FAILED. Output: $DNS_CHECK"
fi

log "\n--- Setup and Verification Complete ---"
log "You can now delete the test container: pct destroy $NEXT_VMID"
