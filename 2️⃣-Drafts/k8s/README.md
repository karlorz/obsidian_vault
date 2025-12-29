# Coder on K3s

Deployed: 2025-12-29

## Access

**NodePort**: `http://10.10.0.99:30768`

Or via SSH tunnel:
```bash
ssh -L 8080:localhost:30768 root@k3s
# Then visit http://localhost:8080
```

Or via kubectl port-forward:
```bash
ssh root@k3s "kubectl -n coder port-forward svc/coder 8080:80"
# Then visit http://localhost:8080
```

## First Login

1. Open the URL above
2. Create admin account on first visit
3. Add templates for workspaces

## Components

| Component | Status | Notes |
|-----------|--------|-------|
| PostgreSQL | Running | `postgresql.coder.svc.cluster.local:5432` |
| Coder | Running | NodePort 30768 |

## Files

- `coder-setup.sh` - Full install script (re-runnable)
- `coder-values.yaml` - Helm values configuration

## Commands

```bash
# Check status
ssh root@k3s "kubectl -n coder get pods,svc"

# View logs
ssh root@k3s "kubectl -n coder logs deployment/coder -f"

# Restart
ssh root@k3s "kubectl -n coder rollout restart deployment/coder"

# Uninstall
ssh root@k3s "helm uninstall coder -n coder && helm uninstall postgresql -n coder"
```

## Templates

After first login, add templates from:
- https://github.com/coder/coder/tree/main/examples/templates
- Docker template (simplest)
- Kubernetes template (for K3s pods)
