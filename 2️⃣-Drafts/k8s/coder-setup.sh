#!/bin/bash
# Coder Setup Script for K3s
# Based on: https://coder.com/docs/install/kubernetes
# Generated: 2025-12-29

set -e

NAMESPACE="coder"
PG_USER="coder"
PG_PASS="coder"
PG_DB="coder"

echo "=== Coder Setup for K3s ==="

# 1. Create namespace
echo "[1/5] Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 2. Add Helm repos
echo "[2/5] Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add coder-v2 https://helm.coder.com/v2
helm repo update

# 3. Install PostgreSQL
echo "[3/5] Installing PostgreSQL..."
helm upgrade --install postgresql bitnami/postgresql \
    --namespace $NAMESPACE \
    --set auth.username=$PG_USER \
    --set auth.password=$PG_PASS \
    --set auth.database=$PG_DB \
    --set primary.persistence.size=10Gi \
    --wait

# 4. Create DB connection secret
echo "[4/5] Creating database connection secret..."
kubectl create secret generic coder-db-url \
    --namespace $NAMESPACE \
    --from-literal=url="postgres://${PG_USER}:${PG_PASS}@postgresql.${NAMESPACE}.svc.cluster.local:5432/${PG_DB}?sslmode=disable" \
    --dry-run=client -o yaml | kubectl apply -f -

# 5. Install Coder
echo "[5/5] Installing Coder..."
helm upgrade --install coder coder-v2/coder \
    --namespace $NAMESPACE \
    --values /tmp/coder-values.yaml \
    --wait

echo "=== Setup Complete ==="
echo ""
echo "To access Coder:"
echo "  kubectl -n $NAMESPACE port-forward svc/coder 8080:80"
echo "  Then visit: http://localhost:8080"
echo ""
echo "Or via NodePort:"
echo "  kubectl -n $NAMESPACE get svc coder"
