# Guide: Enabling Tailscale App Connectors for Proxmox LXCs (No Client Required)

## Executive Summary
This guide explains how to allow **all** your Proxmox LXC containers to use **Tailscale App Connectors** (routing traffic to specific domains via specific exit nodes) **without installing Tailscale inside each LXC**.

**Mechanism**:
1.  **Traffic**: PVE Host routes LXC traffic into the Tailnet (Subnet Router).
2.  **Resolution (The Key)**: App Connectors work by DNS hijacking (returning `100.x.y.z` IPs). LXCs must use a DNS server that "sees" these mappings. We will configure the PVE Host to forward DNS queries from LXCs to Tailscale.

---

## Part 1: Prerequisites
1.  **Proxmox Host** is part of your Tailnet.
2.  **App Connectors** are already configured in your Tailscale Admin Console (e.g., `github.com` routed via `node-us-east`).
3.  You know your internal network subnet (e.g., `192.168.1.0/24`) and PVE Host IP (e.g., `192.168.1.5`).

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
    Replace `192.168.1.0/24` with your actual subnet.
    ```bash
    tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=true
    ```
    *`--accept-dns=true` ensures the Host itself uses MagicDNS.*

3.  **Approve Route** in Tailscale Admin Console:
    -   Machines -> Your PVE Host -> Edit Route Settings -> Enable the subnet.

---

## Part 3: Configure DNS Forwarding on PVE Host (The Trick)
All LXCs need to use Tailscale's DNS (100.100.100.100) to "see" the App Connectors. We will install `dnsmasq` on the Host to listen on the LAN IP and forward requests to Tailscale.

1.  **Install dnsmasq**:
    ```bash
    apt update && apt install dnsmasq -y
    ```

2.  **Configure dnsmasq**:
    Create/Edit `/etc/dnsmasq.d/01-tailscale.conf`:
    ```ini
    # Listen on the bridge interface (LAN)
    interface=vmbr0
    
    # Or explicitly bind to the Host LAN IP (safer if multiple NICs)
    # listen-address=127.0.0.1,192.168.1.5
    
    # Don't bind to wildcards (prevents conflict with systemd-resolved if active)
    bind-interfaces
    
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
    systemctl enable dnsmasq
    ```
    *Check status with `systemctl status dnsmasq` to ensure it successfully bound to port 53.*

---

## Part 4: Configure LXC Containers
Now tell your LXCs to use the PVE Host as their Gateway and DNS Server.

### Method A: Per-Container (Static)
1.  **Shutdown** the LXC.
2.  Go to **Resources -> Network**.
    -   **Gateway**: Should already be your router (e.g., `192.168.1.1`).
        -   *Note*: If your router has a static route to the PVE Host for `100.64.0.0/10` (Tailscale range), this is fine.
        -   *Easier *: Set Gateway to PVE Host IP (e.g. `192.168.1.5`) if you want PVE to route *everything*.
        -   *Standard Setup*: Keep gateway as Router, but Router *must* know how to reach `100.x` IPs via PVE.
            -   **Simpler Alternative**: Just set LXC Gateway to `192.168.1.5` (PVE Host). This ensures traffic meant for App Connectors (which resolve to 100.x IPs) goes to the PVE Host.
    -   **DNS**: Set to PVE Host IP (e.g., `192.168.1.5`).
3.  **Start** the LXC.

### Method B: DHCP (Router Config)
If your LXCs use DHCP:
1.  Configure your DHCP server (Router) to offer the PVE Host IP (`192.168.1.5`) as the **DNS Server** for these devices.

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
