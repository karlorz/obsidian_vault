#!/bin/bash
#
# Kata Containers Kubernetes Deployment Script
# Uses official kata-deploy DaemonSet
# Source: https://github.com/kata-containers/kata-containers/tree/main/tools/packaging/kata-deploy
#
# Usage:
#   ./kata-k8s-deploy.sh install       # Install Kata on K8s cluster
#   ./kata-k8s-deploy.sh install-k3s   # Install on K3s
#   ./kata-k8s-deploy.sh uninstall     # Uninstall Kata
#   ./kata-k8s-deploy.sh status        # Check status
#
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Base URLs for kata-deploy manifests
KATA_REPO="https://raw.githubusercontent.com/kata-containers/kata-containers/main"
KATA_DEPLOY_BASE="${KATA_REPO}/tools/packaging/kata-deploy"

#######################################
# Install on standard Kubernetes
#######################################
install_k8s() {
    info "Installing Kata Containers on Kubernetes..."

    info "Applying RBAC..."
    kubectl apply -f "${KATA_DEPLOY_BASE}/kata-rbac/base/kata-rbac.yaml"

    info "Deploying kata-deploy DaemonSet..."
    kubectl apply -f "${KATA_DEPLOY_BASE}/kata-deploy/base/kata-deploy.yaml"

    info "Waiting for kata-deploy pods..."
    kubectl -n kube-system wait --timeout=10m --for=condition=Ready -l name=kata-deploy pod

    info "Creating RuntimeClasses..."
    kubectl apply -f "${KATA_DEPLOY_BASE}/runtimeclasses/kata-runtimeClasses.yaml"

    info "Installation complete!"
    kubectl get runtimeclass
}

#######################################
# Install on K3s
#######################################
install_k3s() {
    info "Installing Kata Containers on K3s..."

    # K3s needs overlay configuration
    info "Cloning kata-containers repo for K3s overlay..."
    local tmpdir=$(mktemp -d)
    git clone --depth 1 https://github.com/kata-containers/kata-containers.git "$tmpdir"

    cd "$tmpdir/tools/packaging/kata-deploy"

    info "Applying RBAC..."
    kubectl apply -f kata-rbac/base/kata-rbac.yaml

    info "Applying K3s overlay..."
    kubectl apply -k kata-deploy/overlays/k3s

    info "Waiting for kata-deploy pods..."
    kubectl -n kube-system wait --timeout=10m --for=condition=Ready -l name=kata-deploy pod

    info "Creating RuntimeClasses..."
    kubectl apply -f runtimeclasses/kata-runtimeClasses.yaml

    rm -rf "$tmpdir"

    info "Installation complete!"
    kubectl get runtimeclass
}

#######################################
# Uninstall
#######################################
uninstall() {
    info "Uninstalling Kata Containers..."

    # Apply cleanup DaemonSet
    kubectl apply -f "${KATA_DEPLOY_BASE}/kata-cleanup/base/kata-cleanup.yaml"

    info "Waiting for cleanup..."
    kubectl -n kube-system wait --timeout=10m --for=condition=Ready -l name=kata-cleanup pod
    sleep 10

    # Delete all kata-deploy resources
    kubectl delete -f "${KATA_DEPLOY_BASE}/kata-cleanup/base/kata-cleanup.yaml" || true
    kubectl delete -f "${KATA_DEPLOY_BASE}/kata-deploy/base/kata-deploy.yaml" || true
    kubectl delete -f "${KATA_DEPLOY_BASE}/kata-rbac/base/kata-rbac.yaml" || true

    # Delete RuntimeClasses
    kubectl delete runtimeclass kata kata-clh kata-dragonball kata-fc kata-qemu kata-qemu-coco-dev \
        kata-qemu-nvidia-gpu kata-qemu-nvidia-gpu-snp kata-qemu-nvidia-gpu-tdx kata-qemu-se \
        kata-qemu-sev kata-qemu-snp kata-qemu-tdx kata-remote kata-stratovirt 2>/dev/null || true

    info "Uninstallation complete!"
}

#######################################
# Check status
#######################################
status() {
    info "Kata Containers Status:"
    echo ""

    echo "=== RuntimeClasses ==="
    kubectl get runtimeclass 2>/dev/null || echo "No RuntimeClasses found"
    echo ""

    echo "=== kata-deploy Pods ==="
    kubectl -n kube-system get pods -l name=kata-deploy 2>/dev/null || echo "No kata-deploy pods"
    echo ""

    echo "=== Node Labels ==="
    kubectl get nodes -L katacontainers.io/kata-runtime 2>/dev/null || true
}

#######################################
# Test with a pod
#######################################
test_pod() {
    local runtime="${1:-kata}"
    info "Testing with RuntimeClass: $runtime"

    kubectl run kata-test-$(date +%s) \
        --image=alpine:latest \
        --restart=Never \
        --rm -it \
        --overrides='{"spec":{"runtimeClassName":"'$runtime'"}}' \
        -- uname -a
}

#######################################
# Main
#######################################
case "${1:-help}" in
    install)
        install_k8s
        ;;
    install-k3s)
        install_k3s
        ;;
    uninstall)
        uninstall
        ;;
    status)
        status
        ;;
    test)
        test_pod "${2:-kata}"
        ;;
    help|*)
        echo "Kata Containers Kubernetes Deployment"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  install       Install Kata on standard Kubernetes"
        echo "  install-k3s   Install Kata on K3s"
        echo "  uninstall     Uninstall Kata from cluster"
        echo "  status        Show Kata status"
        echo "  test [CLASS]  Run test pod (default: kata)"
        echo ""
        echo "Examples:"
        echo "  $0 install"
        echo "  $0 test kata-fc"
        ;;
esac
