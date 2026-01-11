#!/bin/bash
# tailscale-location-toggle.sh
# Automatically toggle Tailscale --accept-routes based on network location
#
# When on home LAN (10.10.0.0/16): disable route acceptance (use local network)
# When on other networks: enable route acceptance (access home via Tailscale)

HOME_SUBNET="10.10.0."  # Prefix to detect home network
LOG_FILE="/tmp/tailscale-location.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Get current local IP
get_local_ip() {
    # Try common interfaces: en0 (WiFi on laptops), en1 (Ethernet or WiFi on Mac Mini)
    for iface in en0 en1 en2; do
        ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return
        fi
    done
    echo ""
}

# Check if Tailscale is running
if ! tailscale status &>/dev/null; then
    log "Tailscale is not running or not logged in. Exiting."
    exit 1
fi

LOCAL_IP=$(get_local_ip)

if [[ -z "$LOCAL_IP" ]]; then
    log "Could not determine local IP. Exiting."
    exit 1
fi

log "Detected local IP: $LOCAL_IP"

# Check current --accept-routes status
CURRENT_STATUS=$(tailscale debug prefs 2>/dev/null | grep -o '"RouteAll": [a-z]*' | cut -d' ' -f2)

if [[ "$LOCAL_IP" == $HOME_SUBNET* ]]; then
    # On home network - disable route acceptance
    log "On home network ($LOCAL_IP). Disabling --accept-routes to use local LAN."

    if [[ "$CURRENT_STATUS" == "true" ]] || [[ -z "$CURRENT_STATUS" ]]; then
        tailscale set --accept-routes=false
        log "Routes disabled. Local LAN will be used directly."
    else
        log "Routes already disabled. No change needed."
    fi
else
    # On remote network - enable route acceptance
    log "On remote network ($LOCAL_IP). Enabling --accept-routes for home LAN access."

    if [[ "$CURRENT_STATUS" == "false" ]]; then
        tailscale set --accept-routes=true
        log "Routes enabled. Home LAN accessible via Tailscale."
    else
        log "Routes already enabled. No change needed."
    fi
fi

# Show current status
log "Current Tailscale status:"
tailscale status | head -5 >> "$LOG_FILE"
