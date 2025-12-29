# First App Deployment on K3s/Kubernetes

> [!warning] Test Machine
> This is a **TEST/LAB environment**. Do not use for production workloads.

---

## Test Machine Specifications

| Property | Value |
|----------|-------|
| **Hostname** | ubuntu2404 |
| **SSH Access** | `ssh root@k3s` |
| **Node IP** | 10.10.0.99 |
| **OS** | Ubuntu 24.04.3 LTS (Noble Numbat) |
| **Kernel** | 6.8.0-31-generic (x86_64) |
| **CPU Cores** | 16 |
| **Memory** | 32 GB (29 GB available) |
| **Disk** | 60 GB (48 GB available) |
| **K3s Version** | v1.33.6+k3s1 |
| **Container Runtime** | containerd 2.1.5-k3s1.33 |

### Network Configuration
| Interface | IP Address | Purpose |
|-----------|------------|---------|
| ens33 | 10.10.0.99/16 | Primary network |
| flannel.1 | 10.42.0.0/32 | Pod network (CNI) |
| cni0 | 10.42.0.1/24 | Container bridge |

---

## Access Points

| Service | URL/Port | Notes |
|---------|----------|-------|
| **K8s Dashboard** | https://10.10.0.99:30243 | Kong proxy NodePort |
| **Traefik HTTP** | http://10.10.0.99:30436 | Ingress controller |
| **Traefik HTTPS** | https://10.10.0.99:30320 | Ingress controller |

---

## Current Cluster State (as of setup)

### System Pods Running
```
NAMESPACE              NAME                                         STATUS
kube-system            coredns-6d668d687-5rzx2                      Running
kube-system            local-path-provisioner-869c44bfbd-7zzjp      Running
kube-system            metrics-server-7bfffcd44-658sp               Running
kube-system            traefik-865bd56545-tfl9n                     Running
kubernetes-dashboard   kubernetes-dashboard-api-7b4b7d9d74-h7xw5    Running
kubernetes-dashboard   kubernetes-dashboard-auth-7cfcb4585d-zl8j7   Running
kubernetes-dashboard   kubernetes-dashboard-kong-76f95967c6-tnxg9   Running
kubernetes-dashboard   kubernetes-dashboard-web-59b8766cc-d7rzn     Running
```

### Pre-installed Components
- **CoreDNS** - Cluster DNS
- **Traefik** - Ingress controller (LoadBalancer)
- **Metrics Server** - Resource metrics
- **Local Path Provisioner** - Dynamic PV provisioning
- **Kubernetes Dashboard** - Web UI with Kong API gateway

---

## Step 1: Verify Cluster Status

First, confirm your cluster is running properly:

```bash
# Check node status
kubectl get nodes

# Check all system pods are running
kubectl get pods -A

# View cluster info
kubectl cluster-info
```

**Expected Output**: All nodes should show `Ready` status.

---

## Step 2: Deploy Your First App (nginx)

### Option A: Deploy via Dashboard (Web UI)

1. Open Dashboard: https://10.10.0.99:30243/#/create?namespace=default
2. Select **輸入並創建** (Create from input) tab
3. Paste the YAML below into the text area
4. Click **上传** (Upload) button

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo-service
spec:
  type: NodePort
  selector:
    app: nginx-demo
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
```

5. After deployment, access app at: http://10.10.0.99:30080
6. View deployment in sidebar: **Workloads** → **Deployments**

---

### Option B: Quick Deploy via kubectl

```bash
# Create a simple nginx deployment
kubectl create deployment nginx --image=nginx

# Verify deployment
kubectl get deployments

# Check the pod is running
kubectl get pods

# Expose the deployment as a service (NodePort for external access)
kubectl expose deployment nginx --port=80 --type=NodePort

# Get the assigned NodePort
kubectl get svc nginx
```

### Option B: Deploy Using YAML Manifest

Create a file `nginx-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo-service
spec:
  type: NodePort
  selector:
    app: nginx-demo
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080  # Access via http://10.10.0.99:30080
```

Apply the manifest:

```bash
kubectl apply -f nginx-deployment.yaml
```

---

## Step 3: Verify Deployment

```bash
# Check deployment status
kubectl get deployments

# Check pods are running
kubectl get pods -o wide

# Check service is created
kubectl get svc

# Describe deployment for details
kubectl describe deployment nginx-demo
```

---

## Step 4: Access Your App

### Via Command Line
```bash
# Get the NodePort assigned
kubectl get svc nginx-demo-service

# Test with curl (replace PORT with actual NodePort)
curl http://10.10.0.99:30080
```

### Via Browser
Navigate to: `http://10.10.0.99:30080`

You should see the **"Welcome to nginx!"** page.

### Via Dashboard
1. Open: https://10.10.0.99:30243/#/workloads?namespace=default
2. Navigate to **Deployments** → You should see `nginx-demo`
3. Click on the deployment to view pods, replica sets, and logs

---

## Step 5: Scale the Deployment

```bash
# Scale up to 3 replicas
kubectl scale deployment nginx-demo --replicas=3

# Verify scaling
kubectl get pods

# Scale down
kubectl scale deployment nginx-demo --replicas=1
```

---

## Step 6: View Logs and Debug

```bash
# View pod logs
kubectl logs <pod-name>

# Follow logs in real-time
kubectl logs -f <pod-name>

# Execute command inside pod
kubectl exec -it <pod-name> -- /bin/bash

# Get detailed pod info
kubectl describe pod <pod-name>
```

---

## Step 7: Clean Up

```bash
# Delete deployment and service
kubectl delete deployment nginx-demo
kubectl delete service nginx-demo-service

# Or if using YAML
kubectl delete -f nginx-deployment.yaml

# Verify cleanup
kubectl get all
```

---

## Common Commands Reference

| Command | Description |
|---------|-------------|
| `kubectl get all` | List all resources in current namespace |
| `kubectl get pods -w` | Watch pods in real-time |
| `kubectl get events` | View cluster events |
| `kubectl top nodes` | View node resource usage |
| `kubectl top pods` | View pod resource usage |
| `kubectl port-forward svc/nginx 8080:80` | Local port forwarding |

---

## Troubleshooting

### Pod stuck in Pending
```bash
kubectl describe pod <pod-name>  # Check Events section
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Pod in CrashLoopBackOff
```bash
kubectl logs <pod-name> --previous  # View logs from crashed container
```

### Can't access service externally
```bash
# Verify service type and ports
kubectl get svc -o wide

# Check if NodePort is in allowed range (30000-32767)
# Verify firewall allows the port
```

---

## Next Steps

- [ ] Deploy a custom application
- [ ] Set up Ingress controller for domain-based routing
- [ ] Configure persistent volumes for data storage
- [ ] Explore Helm charts for complex deployments
- [ ] Set up monitoring with Prometheus/Grafana

---

#kubernetes #k3s #deployment #devops
