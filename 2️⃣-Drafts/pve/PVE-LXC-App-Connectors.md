# Guide: Enabling Tailscale App Connectors for Proxmox LXCs (No Client Required)

## Executive Summary
This guide explains how to allow **all** your Proxmox LXC containers to use **Tailscale App Connectors** (routing traffic to specific domains via specific exit nodes) **without installing Tailscale inside each LXC**.

**Mechanism**:
1.  **Traffic**: PVE Host routes LXC traffic into the Tailnet (Subnet Router).
2.  **Resolution (The Key)**: App Connectors work by DNS hijacking (returning `100.x.y.z` IPs). LXCs must use a DNS server that "sees" these mappings. We will configure the PVE Host to forward DNS queries from LXCs to Tailscale.

### How it works for default LXCs (vmbr0)
Your default LXCs live on `vmbr0` (the 10.10.0.0/16 network). They are "next to" the PVE host.
1.  **DNS Query**: LXC asks PVE Host (`10.10.0.9`) "Where is target.com?".
2.  **PVE Response**: PVE (running our modified dnsmasq) asks Tailscale, which replies "It's at 100.x.y.z" (Magic IP).
3.  **Traffic Flow**: LXC sends traffic to `100.x.y.z`.
4.  **Routing**:
    *   **IF** LXC Gateway is PVE (`10.10.0.9`): PVE immediately routes it into the Tailscale tunnel. **(Recommended)**
    *   **IF** LXC Gateway is Router (`10.10.0.1`): Router sends it BACK to PVE (requires Static Route on Router).

---

## Part 1: Prerequisites
1.  **Proxmox Host** is part of your Tailnet.
2.  **App Connectors** are already configured in your Tailscale Admin Console (e.g., `github.com` routed via `node-us-east`).
3.  **Verified** internal network subnet: `10.10.0.0/16` and PVE Host IP: `10.10.0.9`.
4.  **Verified** `dnsmasq` is installed and running on the host (serving `vmbr1`). We will extend it to serve `vmbr0`.

---

## Part 2: Configure PVE Host as Subnet Router
*If you have already done this, skip to Part 3.*

1.  **Enable IP Forwarding** on PVE Host:
    ```bash
    echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
    sysctl -p /etc/sysctl.d/99-tailscale.conf
    ```

2.  **Advertise Routes**:
    Replace `10.10.0.0/16` with your actual subnet.
    ```bash
    tailscale up --advertise-routes=10.10.0.0/16 --accept-dns=true
    ```
    *`--accept-dns=true` ensures the Host itself uses MagicDNS.*

3.  **Approve Route** in Tailscale Admin Console:
    -   Machines -> Your PVE Host -> Edit Route Settings -> Enable the subnet (`10.10.0.0/16`).

---

## Part 3: Configure DNS Forwarding on PVE Host (The Trick)
All LXCs need to use Tailscale's DNS (100.100.100.100) to "see" the App Connectors. We will install `dnsmasq` on the Host to listen on the LAN IP and forward requests to Tailscale.

1.  **Install dnsmasq**:
    ```bash
    apt update && apt install dnsmasq -y
    ```

4.  **Configure dnsmasq**:
    Create/Edit `/etc/dnsmasq.d/01-tailscale.conf`.
    *Critically, we add `interface=vmbr0` so dnsmasq listens on your main network.*
    ```ini
    # Listen on vmbr0 so standard LXCs can query 10.10.0.9
    interface=vmbr0
    
    # Forward EVERYTHING to Tailscale's MagicDNS
    # This ensures App Connectors AND MagicDNS hostnames work for configured LXCs
    server=100.100.100.100
    
    # Never forward plain names (optional, good practice)
    domain-needed
    bogus-priv
    ```

3.  **Restart dnsmasq**:
    ```bash
    systemctl restart dnsmasq
    ```
    *Check status with `systemctl status dnsmasq`.*
    *Note: This will also make `vmbr1` (existing NAT network) use Tailscale DNS, which is generally fine.*

---

## Part 4: Configure LXC Containers (vmbr0)
You must change the network settings for **each** LXC you want to use App Connectors.

### The "Golden" Configuration (Recommended)
This guarantees traffic works without modifying your main router.

1.  **Shutdown** the LXC.
2.  Go to **Resources -> Network**.
    -   **Bridge**: `vmbr0` (Default)
    -   **IPv4/CIDR**: `10.10.0.x/16` (Your static IP) or DHCP
    -   **Gateway (IPv4)**: `10.10.0.9` (Set to PVE Host IP!)
        *   *Why?* This forces traffic meant for Tailscale IPs to go directly to the PVE Host, which knows how to route them.
    -   **DNS Server**: `10.10.0.9` (Set to PVE Host IP!)
        *   *Why?* This ensures the LXC can resolve names like `code.corp` or `github.com` to Tailscale IPs.
3.  **Start** the LXC.

### Alternative (If you keep Router Gateway)
If you keep Gateway as `10.10.0.1` (Router), you **MUST** log into your Router (UniFi/Omada/etc) and add a Static Route:
*   Destination: `100.64.0.0/10`
*   Next Hop: `10.10.0.9` (PVE Host)
*Without this, LXC sends traffic to Router, and Router drops it because it doesn't know where `100.x.x.x` is.*

---

## Part 5: Verification

Inside an LXC (without Tailscale installed):

1.  **Test DNS**:
    ```bash
    # Should return a 100.x.y.z IP (Tailscale CGNAT), NOT the public IP
    nslookup target-domain.com
    ```

2.  **Test Connectivity**:
    ```bash
    # Should work
    curl -v target-domain.com
    ```
