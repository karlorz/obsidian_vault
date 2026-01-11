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
**Crucial Note on DHCP**: Since your home router (`10.10.0.1`) manages DHCP, **you cannot simply select "DHCP"** in the LXC settings.
*   *Why?* DHCP will assign the Router (`10.10.0.1`) as the Gateway and DNS. This breaks App Connectors because the Router doesn't know how to resolve/route Tailscale traffic.
*   **Solution**: You must use **Static IPv4** settings for these LXCs.

### The "Golden" Configuration (Recommended)
1.  **Shutdown** the LXC.
2.  Go to **Resources -> Network**.
    -   **Bridge**: `vmbr0`
    -   **IPv4**: Select **Static** (Do NOT use DHCP).
    -   **IPv4/CIDR**: Pick an IP *outside* your Router's DHCP pool (e.g., `10.10.0.200/16`).
    -   **Gateway (IPv4)**: `10.10.0.9` (**PVE Host IP** - Required).
    -   **DNS Server**: `10.10.0.9` (**PVE Host IP** - Required).
3.  **Start** the LXC.

### "I really want to use DHCP" Method
If you absolutely must use DHCP (e.g., via Router reservation), it is much harder:
1.  **Router Config**: You must add a **Static Route** on your UniFi/Omada router: `100.64.0.0/10` -> `10.10.0.9`.
    *   *This fixes connectivity, but NOT DNS.*
2.  **LXC DNS**: Since the Router gives its own IP for DNS, you must manually edit `/etc/resolv.conf` inside *every* LXC to point to `10.10.0.9` to resolve App Connector domains.
    *   *Verdict*: Not recommended. Use Static IPv4 in Proxmox instead.

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
