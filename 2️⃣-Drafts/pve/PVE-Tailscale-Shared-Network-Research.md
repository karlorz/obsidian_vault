# Research: Shared Tailscale Networking for Proxmox VE and LXCs

## 1. Executive Summary
You asked if using the specific community script (`add-tailscale-lxc.sh`) on a Proxmox VE (PVE) host allows all LXCs to "share the same network setting" as the host.

**The short answer is NO.** 
The script you referenced (`add-tailscale-lxc.sh`) is designed to install a **dedicated, independent Tailscale instance** inside a *specific* LXC container. If you run this for 10 containers, you will have 10 separate Tailscale machines in your admin console. They do not share the host's networking; they just join the same Tailnet as independent devices.

## 2. The Solution: Subnet Router (Gateway)
To achieve your goal of having **all PVE LXCs/VMs share the PVE Host's Tailscale connection**, you should not install Tailscale inside every LXC. Instead, you should configure the **PVE Host (or a dedicated LXC)** as a **Subnet Router**.

### How it works
1.  **Tailscale** runs on the PVE Host (or a dedicated Gateway LXC).
2.  It "advertises" your local Proxmox network (e.g., `192.168.1.0/24`).
3.  You approve these routes in the Tailscale Admin Console.
4.  **Result:** Any device on your Tailscale network (your phone, laptop) can access **ANY** LXC or VM by its local IP (e.g., `192.168.1.105`) without installing anything on the LXC itself.

## 3. Implementation Steps

### Option A: Install on PVE Host (Simplest for "Sharing")
This makes the Host the gateway. All LXCs "share" this access automatically.

1.  **Install Tailscale on PVE Host** (standard Linux install, not the LXC script):
    ```bash
    curl -fsSL https://tailscale.com/install.sh | sh
    ```
2.  **Enable Subnet Routing**:
    Assuming your PVE bridge/network is `192.168.1.0/24` (check with `ip a`):
    ```bash
    tailscale up --advertise-routes=192.168.1.0/24
    ```
3.  **Authorize in Dashboard**:
    -   Go to [Tailscale Admin Console](https://login.tailscale.com/admin/machines).
    -   Find your PVE Host.
    -   Click **Edit Route Settings** -> Enable the `192.168.1.0/24` route.

### Option B: Use the Script (`add-tailscale-lxc.sh`)
Use this ONLY if you need a specific LXC to have its own MagicDNS name (e.g., `plex.tailnet-name.ts.net`) or if you want that LXC to be able to connect OUT to other Tailscale nodes *independently* of the host.
-   **Usage**: Run the script on the PVE host -> Select LXC -> Follow prompts.
-   **Result**: The LXC gets `tailscale` installed. You must run `tailscale up` inside the LXC. It will be a *separate* node.

## 4. Summary Table

| Feature | Subnet Router (Recommended) | Per-LXC Install (Script) |
| :--- | :--- | :--- |
| **Setup** | Once on Host | Repeated per LXC |
| **Access Method** | IP Address (e.g., `192.168.1.105`) | MagicDNS (e.g., `my-lxc`) |
| **Resource Usage** | Low (Single Agent) | Higher (Agent per LXC) |
| **Maintenance** | Single Update | Update every LXC |
| **"Shared Settings"** | **YES** (Centralized) | **NO** (Independent) |

## 5. Recommendation
If your goal is valid "sharing" where you configured the host and everything else just works: **Use the Subnet Router method on the Host.** Do not use the LXC script for every container unless you have a specific need for isolated entry points.
