# PVE LXC Command Execution: Alternatives to SSH

**Date**: 2025-12-27
**Context**: cmux PVE LXC sandbox provider needs to execute commands inside LXC containers without relying on SSH to the PVE host.

---

## Problem Statement

The current cmux implementation for PVE LXC uses:
```
SSH to PVE host -> pct exec <vmid> -- <command>
```

This has drawbacks:
- Requires SSH key setup on PVE host
- SSH connection overhead
- Potential connection limits (mitigated with ControlMaster)
- Security surface of SSH exposure

---

## Research Summary

### Confirmed: PVE API Does NOT Expose LXC Exec

The Proxmox VE REST API **does not** provide an endpoint for executing arbitrary commands inside LXC containers. This is a deliberate design choice.

**Key Quote from Proxmox Forums:**
> "That API endpoint is not for executing arbitrary commands, but for calling API endpoints in a sort of batch mode." ([Source](https://forum.proxmox.com/threads/execute-command-in-node-with-api.112290/))

Available CLI tools (`pct exec`, `pct enter`, `lxc-attach`) are **CLI-only** and not exposed via REST.

---

## Solution Options

### Option 1: Custom Sidecar Agent in Container (Recommended)

**Concept**: Install a lightweight HTTP/WebSocket agent inside each LXC container that exposes an exec API.

**Architecture**:
```
cmux server -> HTTP/WS -> agent (inside LXC) -> executes command
```

**Implementation**:
- Deploy `cmux-pty` or similar agent as part of the container template
- Agent listens on a known port (e.g., 39383)
- Agent authenticates requests via JWT/shared secret
- Agent executes commands via `child_process.spawn()`

**Pros**:
- No SSH required
- Direct HTTP communication
- Already have `cmux-pty` implementation in Morph snapshots
- Same API as Morph `instance.exec()`

**Cons**:
- Must bake agent into template
- Agent is another process to manage
- Security: agent must validate requests

**Effort**: Low - cmux-pty already exists, just deploy to LXC templates

---

### Option 2: PVE termproxy + WebSocket

**Concept**: Use PVE's built-in terminal proxy API with WebSocket.

**API Flow**:
```
POST /nodes/{node}/lxc/{vmid}/termproxy -> {port, ticket}
WS  wss://{host}:8006/api2/json/nodes/{node}/lxc/{vmid}/vncwebsocket?port={port}&vncticket={ticket}
```

**Pros**:
- Uses existing PVE infrastructure
- No custom agent needed
- Works with API tokens

**Cons**:
- Designed for interactive terminals, not programmatic exec
- Requires parsing xterm.js output
- Complex ticket management
- Documented issues with API token auth ([Source](https://forum.proxmox.com/threads/unable-to-connect-to-vncwebsocket-endpoint-via-api-token.113420/))

**Effort**: High - would need to build exec abstraction over interactive terminal

---

### Option 3: Custom PVE Perl Plugin

**Concept**: Extend PVE's API with a custom endpoint that exposes `pct exec`.

**Implementation**:
```perl
# /usr/share/perl5/PVE/API2/Custom/LXCExec.pm
package PVE::API2::Custom::LXCExec;
use base qw(PVE::RESTHandler);

__PACKAGE__->register_method({
    name => 'exec',
    path => '{vmid}/exec',
    method => 'POST',
    parameters => { command => {...} },
    code => sub {
        my ($param) = @_;
        # Call pct exec internally
        my $vmid = $param->{vmid};
        my $cmd = $param->{command};
        return PVE::Tools::run_command(['pct', 'exec', $vmid, '--', @$cmd]);
    }
});
```

**Pros**:
- Native PVE integration
- Uses existing auth/permissions
- Clean REST API

**Cons**:
- Must maintain across PVE upgrades
- Perl knowledge required
- AGPLv3+ licensing requirements
- Security: exposing exec via API is risky

**Effort**: Medium - requires Perl plugin development

**References**:
- [Storage Plugin Development](https://pve.proxmox.com/wiki/Storage_Plugin_Development)
- [PVE Common Perl Code](https://github.com/proxmox/pve-common)

---

### Option 4: pvesh via Local Socket

**Concept**: If cmux server runs on PVE host, use `pvesh` directly.

**Implementation**:
```bash
pvesh create /nodes/{node}/execute --commands '[...]'
```

**Note**: The `/execute` endpoint is for batching API calls, not shell commands.

**Pros**:
- No network required
- Uses PVE's internal auth

**Cons**:
- Only works if cmux is on PVE host
- Still doesn't expose exec

**Effort**: N/A - doesn't solve the problem

---

### Option 5: Incus/LXD Migration

**Concept**: Replace PVE LXC with Incus which has native exec API.

**Incus Exec API**:
```
POST /1.0/instances/{name}/exec
{
  "command": ["/bin/bash", "-c", "echo hello"],
  "environment": {},
  "wait-for-websocket": false,
  "interactive": false
}
```

**Pros**:
- Native REST API for exec ([Incus REST API](https://linuxcontainers.org/incus/docs/main/rest-api/))
- Modern, actively developed
- Better API design

**Cons**:
- Major infrastructure change
- Would replace PVE entirely or run alongside
- Different management paradigm

**Effort**: Very High - infrastructure migration

---

### Option 6: SSH to Container Directly (Hybrid)

**Concept**: Instead of SSH to PVE host, SSH directly into LXC container.

**Implementation**:
- Bake SSH server into container template
- Inject SSH key at container creation
- Connect directly to container IP

**Pros**:
- Standard approach
- No custom agent
- Battle-tested

**Cons**:
- Still using SSH
- Container must have network access
- Key management complexity

**Effort**: Low - just configure template

---

## Morph vs PVE LXC: Exec Comparison

| Feature | Morph VM | PVE LXC (Current) | PVE LXC (Goal) |
|---------|----------|-------------------|----------------|
| **Exec Method** | `instance.exec()` API | SSH + `pct exec` | HTTP agent |
| **Transport** | HTTPS to Morph API | SSH to PVE host | HTTP to container |
| **Latency** | Low (~50ms) | Higher (~200ms SSH overhead) | Low (~50ms) |
| **Auth** | API token | SSH key | JWT/shared secret |
| **Dependencies** | Morph SDK | SSH client on host | Network to container |
| **Offline Support** | No (cloud API) | Yes (local SSH) | Yes (local HTTP) |

### Architecture Note: Server-Side Exec vs Public Domain Access

**Important**: The `instance.exec()` is a **server-side** operation. The cmux www server (backend) calls the sandbox's exec API to run setup scripts. This is NOT the same as public domain HTTPS access for end users.

```
                                    ┌─────────────────────────────────────┐
                                    │           Sandbox/Container          │
                                    │                                      │
┌──────────────┐                    │  ┌─────────────┐  ┌──────────────┐  │
│  cmux www    │──── exec() ───────▶│  │ cmux-pty    │  │  VSCode      │  │
│  (backend)   │    (server-side)   │  │ :39383      │  │  :39378      │  │
└──────────────┘                    │  └─────────────┘  └──────────────┘  │
                                    │         ▲                ▲          │
                                    │         │                │          │
                                    │         │ HTTP           │ HTTPS    │
                                    │         │ (internal)     │ (public) │
                                    └─────────┼────────────────┼──────────┘
                                              │                │
                                    ┌─────────┴────────────────┴──────────┐
                                    │        Reverse Proxy / Gateway       │
                                    │   (Morph: *.http.cloud.morph.so)     │
                                    │   (PVE: needs Caddy/Nginx/Cloudflare)│
                                    └─────────────────────────────────────┘
                                                       ▲
                                                       │ HTTPS
                                              ┌────────┴────────┐
                                              │   End User      │
                                              │   (Browser)     │
                                              └─────────────────┘
```

**For Morph**:
- `instance.exec()` -> Morph API -> Container (server-to-container)
- Public access: `https://{service}-{id}.http.cloud.morph.so` (Morph's reverse proxy)

**For PVE LXC** (with sidecar agent):
- `instance.exec()` -> HTTP to container IP:39383 (server-to-container)
- Public access: Requires separate reverse proxy (Caddy/Nginx/Cloudflare Tunnel)

### Public Domain Access for PVE LXC

The sidecar agent approach works for server-side exec. For public HTTPS access, you need:

1. **Reverse Proxy on PVE Host** (e.g., Caddy, Nginx, Traefik)
2. **Cloudflare Tunnel** (recommended for public access without port forwarding)
3. **Wildcard DNS** pointing to the proxy

Example with Cloudflare Tunnel:
```bash
# On PVE host, run cloudflared to expose containers
cloudflared tunnel --url http://container-ip:39378
# Results in: https://random-subdomain.trycloudflare.com
```

Or with Caddy reverse proxy:
```caddyfile
# Caddyfile on PVE host
*.sandbox.yourdomain.com {
    reverse_proxy {header.X-Container-IP}:39378
}
```

---

## Comparison Matrix: PVE LXC Options

| Option           | No SSH | No Custom Agent | Works Offline | Complexity | Recommended |
| ---------------- | ------ | --------------- | ------------- | ---------- | ----------- |
| 1. Sidecar Agent | Yes    | No              | Yes           | Low        | **Yes**     |
| 2. termproxy WS  | Yes    | Yes             | No            | High       | No          |
| 3. Perl Plugin   | Yes    | Yes             | Yes           | Medium     | Maybe       |
| 4. pvesh         | Yes    | Yes             | Local only    | Low        | No          |
| 5. Incus         | Yes    | Yes             | Yes           | Very High  | Future      |
| 6. Direct SSH    | No     | Yes             | No            | Low        | Fallback    |

---

## Recommended Approach

### Primary: Option 1 - Sidecar Agent (cmux-pty)

1. **Template Modification**: Include `cmux-pty` server in PVE LXC template
2. **Auto-Start**: Configure systemd unit to start agent on boot
3. **Port Binding**: Agent listens on `0.0.0.0:39383` (same as Morph)
4. **Auth**: Use same JWT mechanism as Morph environments

**Changes to `pve-lxc-client.ts`**:
```typescript
async execInContainer(vmid: number, command: string): Promise<ExecResult> {
  const ip = await this.getContainerIp(vmid);

  // Try cmux-pty agent first
  try {
    const response = await fetch(`http://${ip}:39383/exec`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command })
    });
    if (response.ok) {
      return response.json();
    }
  } catch {
    // Fall back to SSH + pct exec
  }

  // Fallback: SSH to PVE host
  const escapedCommand = command.replace(/'/g, "'\\''");
  const pctCommand = `pct exec ${vmid} -- bash -lc '${escapedCommand}'`;
  return this.sshExec(pctCommand);
}
```

### Secondary: Option 3 - Perl Plugin (Future)

If we need tighter PVE integration without custom agents, develop a Perl plugin that exposes `/nodes/{node}/lxc/{vmid}/exec` endpoint.

---

## Implementation Tasks

- [ ] Add cmux-pty to PVE LXC template build script
- [ ] Configure cmux-pty systemd unit in template
- [ ] Update `pve-lxc-client.ts` to use HTTP exec with SSH fallback
- [ ] Test exec latency comparison (agent vs SSH)
- [ ] Document PVE template requirements

---

## References

- [Proxmox VE API](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- [Proxmox Forum: Execute command in node with API](https://forum.proxmox.com/threads/execute-command-in-node-with-api.112290/)
- [Proxmox Forum: LXC Guest Agent equivalent](https://forum.proxmox.com/threads/lxc-guest-agent-equivalent.66425/)
- [Incus REST API - Instance Exec](https://linuxcontainers.org/incus/docs/main/instance-exec/)
- [pve-lxc-syscalld](https://github.com/proxmox/pve-lxc-syscalld) - handles seccomp syscall forwarding for mknod
- [Storage Plugin Development](https://pve.proxmox.com/wiki/Storage_Plugin_Development) - shows how to extend PVE with Perl
- [Ansible proxmox_pct_remote plugin](https://github.com/ansible-collections/community.general/pull/8424) - community effort for direct LXC management

---

## Existing Community Projects (Host-Side)

### No Pre-Built PVE Perl Plugin Found

After extensive searching, **no existing GitHub project** provides a ready-to-deploy Perl plugin that exposes `pct exec` via PVE's REST API. The community has worked around this limitation using other approaches:

### Available Workarounds

#### 1. ProxVNC (Python) - Via VNC WebSocket
**GitHub**: [xgiralt64/ProxVNC](https://github.com/xgiralt64/ProxVNC)

**What it does**: Connects to Proxmox nodes/LXC via VNC WebSocket to execute commands.

**How it works**:
1. Uses Proxmox's `termproxy` API to get a VNC ticket
2. Establishes WebSocket connection to `vncwebsocket` endpoint
3. Sends commands through the terminal interface

**Installation**: `pip install ProxVNC`

**Pros**:
- Works with existing PVE infrastructure
- No modifications to PVE needed
- Python-based, easy to integrate

**Cons**:
- Uses VNC terminal abstraction (hacky)
- Requires parsing terminal output
- May have timing issues with command completion

#### 2. LWS (Linux Web Services)
**GitHub**: [fabriziosalmi/lws](https://github.com/fabriziosalmi/lws)

**What it does**: Unified CLI + REST API for Proxmox, LXC, and Docker management.

**How it works**:
- SSH-based remote execution to Proxmox hosts
- REST API server that wraps CLI operations
- Swagger documentation included

**Installation**: Clone repo, `pip install -r requirements.txt`, configure `config.yaml`

**Pros**:
- Provides REST API for LXC operations
- Docker deployment available
- AWS-like unified interface

**Cons**:
- Still uses SSH under the hood
- External service, not native to PVE
- Additional infrastructure to maintain

#### 3. morph027/pve-lxc-scripts
**GitHub**: [morph027/pve-lxc-scripts](https://github.com/morph027/pve-lxc-scripts)

**What it does**: Shell scripts for batch LXC management including `lxc-exec`.

**Use case**: Run commands across all containers from PVE host CLI.

**Limitation**: CLI only, no API.

#### 4. FredHutch/proxmox-tools
**GitHub**: [FredHutch/proxmox-tools](https://github.com/FredHutch/proxmox-tools)

**What it does**: `prox` CLI tool for LXC deployment with runlist support.

**Use case**: Execute command lists across multiple containers.

**Limitation**: CLI/runlist based, not real-time API.

#### 5. Proxmoxer (Python Library)
**GitHub**: [proxmoxer/proxmoxer](https://github.com/proxmoxer/proxmoxer)
**PyPI**: `pip install proxmoxer`

**What it does**: Python wrapper around Proxmox REST API v2.

**Backends Supported**:
- `https` - REST API over HTTPS (default)
- `ssh_paramiko` - SSH via Paramiko library
- `openssh` - SSH via openssh_wrapper
- Direct `pvesh` utility access

**LXC Exec Support**: **NO**

Proxmoxer does NOT provide LXC exec functionality because PVE API doesn't expose it:
- QEMU VMs: Yes, via `.../agent/exec` (QEMU Guest Agent)
- LXC Containers: No API endpoint exists

**How to use SSH backend**:
```python
from proxmoxer import ProxmoxAPI

# SSH backend - runs pvesh commands over SSH
proxmox = ProxmoxAPI('pve-host', user='root', backend='ssh_paramiko')

# This does NOT give you pct exec - only API calls via pvesh
proxmox.nodes('pve').lxc(200).status.current.get()
```

**To execute commands in LXC via proxmoxer**, you must:
1. Use SSH backend to connect to PVE host
2. Manually run `pct exec` via the underlying SSH connection (not exposed by proxmoxer)

**Conclusion**: Proxmoxer wraps the PVE REST API. Since PVE API has no LXC exec endpoint, proxmoxer cannot provide it either. The SSH backend just runs `pvesh` commands, not arbitrary shell commands.

#### 6. Ansible proxmox_pct_remote Connection Plugin
**Docs**: [community.proxmox.proxmox_pct_remote](https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/proxmox_pct_remote_connection.html)

**What it does**: Ansible connection plugin that runs tasks in LXC via `pct exec` over SSH.

**How it works**:
1. SSH to PVE host (via Paramiko)
2. Run `pct exec <vmid> -- <command>`
3. Return results to Ansible

**Example**:
```yaml
- hosts: my_lxc_container
  connection: community.proxmox.proxmox_pct_remote
  vars:
    ansible_pct_remote_host: pve-host.example.com
    ansible_pct_remote_vmid: 200
  tasks:
    - name: Run command in LXC
      command: echo "hello from container"
```

**Pros**:
- No SSH needed inside container
- Works with Ansible ecosystem
- Mature implementation

**Cons**:
- Slow (Paramiko doesn't support persistent connections)
- Ansible dependency
- Still SSH under the hood (to PVE host)

---

## Option 3 Addendum: Custom PVE API Plugin (DIY)

Since no pre-built solution exists, building a custom Perl plugin requires:

### PVE API Architecture Notes

From [Snyk CVE-2024-21545 research](https://labs.snyk.io/resources/proxmox-ve-cve-2024-21545-tricking-the-api/):

- API endpoints at `/usr/share/perl5/PVE/`
- **Protected endpoints** run in `pvedaemon` (root)
- **Unprotected endpoints** run in `pveproxy` (www-data)
- For exec, must use **protected** endpoint

### Deployment Path

1. Create `/usr/share/perl5/PVE/API2/LXCExec.pm`
2. Register in PVE's API router
3. Mark as `protected => 1` (runs as root)
4. Restart `pvedaemon` and `pveproxy`

### Risks

- **Upgrade breakage**: PVE updates may overwrite custom files
- **Security**: Exposing arbitrary exec is dangerous
- **Licensing**: Must be AGPLv3+ compatible
- **Support**: Not officially supported by Proxmox

### Alternative: Standalone Daemon on PVE Host

Instead of patching PVE, deploy a separate daemon on the PVE host:

```python
# pve-exec-daemon.py (run on PVE host as root)
from flask import Flask, request
import subprocess

app = Flask(__name__)

@app.route('/exec/<int:vmid>', methods=['POST'])
def exec_command(vmid):
    auth = request.headers.get('Authorization')
    if not validate_auth(auth):
        return {'error': 'unauthorized'}, 401

    cmd = request.json.get('command')
    result = subprocess.run(
        ['pct', 'exec', str(vmid), '--', 'bash', '-lc', cmd],
        capture_output=True, text=True
    )
    return {
        'exit_code': result.returncode,
        'stdout': result.stdout,
        'stderr': result.stderr
    }

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=39377)
```

**Pros**:
- Doesn't modify PVE internals
- Easy to deploy/update
- Can run as systemd service

**Cons**:
- Another service to manage
- Must secure the endpoint
- Still runs on PVE host (vs in container)

---

## Updated Recommendation

Given the research findings:

| Approach | Effort | Reliability | Maintenance |
|----------|--------|-------------|-------------|
| **Option 1: In-container agent (cmux-pty)** | Low | High | Low |
| **Option 2a: ProxVNC** | Low | Medium | Low |
| **Option 3a: Standalone daemon on PVE host** | Medium | High | Medium |
| **Option 3b: Perl plugin (DIY)** | High | High | High |

**Best path forward**:
1. **Short-term**: Use cmux-pty in container (already implemented in Morph)
2. **Medium-term**: Consider standalone daemon on PVE host if agent deployment is problematic
3. **Avoid**: Custom Perl plugin unless absolutely necessary (maintenance burden)

---

## Appendix: Why No QEMU Guest Agent for LXC?

LXC containers share the host kernel. Unlike QEMU VMs which are fully isolated and need a guest agent for host-guest communication, PVE already has direct namespace access to LXC containers via `pct exec` / `lxc-attach`. The "agent" is the host kernel itself.

The `pve-lxc-syscalld` daemon exists specifically to handle forwarded syscalls (like `mknod`) from unprivileged containers using seccomp trap-to-userspace, not for general command execution.
