#!/bin/bash
#
# Podman Checkpoint Setup Script
# Configures Podman to use runc runtime (required for checkpoint/restore)
#
# This script:
# 1. Installs required packages (podman, criu, runc)
# 2. Configures containers.conf to use runc as default runtime
# 3. Migrates existing containers to runc
# 4. Restarts podman services
#
# Usage:
#   sudo ./setup-podman-checkpoint.sh           # Full setup
#   sudo ./setup-podman-checkpoint.sh --check   # Check only, don't modify
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CHECK_ONLY=false
if [[ "$1" == "--check" || "$1" == "-c" ]]; then
    CHECK_ONLY=true
fi

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Podman Checkpoint/Restore Setup Script                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    else
        OS="unknown"
        OS_NAME="Unknown"
    fi
}

detect_os
echo -e "${CYAN}System: $OS_NAME${NC}"
echo ""

#####################################
# 1. Install Required Packages
#####################################
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ Step 1: Check/Install Required Packages${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

install_packages() {
    case $OS in
        ubuntu|debian)
            # Check if CRIU PPA is needed (Ubuntu 24.04+)
            if [[ "$OS" == "ubuntu" ]] && [[ "${VERSION%%.*}" -ge 24 ]]; then
                if ! grep -q "criu/ppa" /etc/apt/sources.list.d/* 2>/dev/null; then
                    echo "Adding CRIU PPA for Ubuntu 24.04+..."
                    add-apt-repository -y ppa:criu/ppa
                fi
            fi
            apt-get update -qq
            apt-get install -y podman criu runc
            ;;
        fedora)
            dnf install -y podman criu runc
            ;;
        centos|rhel|rocky|almalinux)
            dnf install -y podman criu runc || yum install -y podman criu runc
            ;;
        arch)
            pacman -Sy --noconfirm podman criu runc
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            echo "Please install podman, criu, and runc manually"
            exit 1
            ;;
    esac
}

# Check each package
MISSING_PKGS=""

if ! command -v podman &> /dev/null; then
    echo -e "${RED}✗ Podman not installed${NC}"
    MISSING_PKGS="$MISSING_PKGS podman"
else
    echo -e "${GREEN}✓ Podman installed: $(podman --version)${NC}"
fi

if ! command -v criu &> /dev/null; then
    echo -e "${RED}✗ CRIU not installed${NC}"
    MISSING_PKGS="$MISSING_PKGS criu"
else
    echo -e "${GREEN}✓ CRIU installed: $(criu --version 2>&1 | head -1)${NC}"
fi

if ! command -v runc &> /dev/null; then
    echo -e "${RED}✗ runc not installed${NC}"
    MISSING_PKGS="$MISSING_PKGS runc"
else
    echo -e "${GREEN}✓ runc installed: $(runc --version 2>&1 | head -1)${NC}"
fi

if [[ -n "$MISSING_PKGS" ]]; then
    if [[ "$CHECK_ONLY" == true ]]; then
        echo ""
        echo -e "${YELLOW}Missing packages:$MISSING_PKGS${NC}"
        echo "Run without --check to install"
    else
        echo ""
        echo "Installing missing packages:$MISSING_PKGS"
        install_packages
    fi
fi

#####################################
# 2. Configure containers.conf
#####################################
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ Step 2: Configure Default Runtime to runc${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

CONTAINERS_CONF="/etc/containers/containers.conf"
CONTAINERS_CONF_DIR="/etc/containers"

# Check current runtime
CURRENT_RUNTIME=$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || echo "unknown")
echo "Current default runtime: $CURRENT_RUNTIME"

if [[ "$CURRENT_RUNTIME" == "runc" ]]; then
    echo -e "${GREEN}✓ Runtime already set to runc${NC}"
else
    if [[ "$CHECK_ONLY" == true ]]; then
        echo -e "${YELLOW}⚠ Runtime is $CURRENT_RUNTIME (need to change to runc)${NC}"
        echo ""
        echo "Configuration needed in $CONTAINERS_CONF:"
        echo ""
        echo "  [engine]"
        echo "  runtime = \"runc\""
    else
        echo "Configuring runtime to runc..."

        # Create directory if needed
        mkdir -p "$CONTAINERS_CONF_DIR"

        # Backup existing config
        if [[ -f "$CONTAINERS_CONF" ]]; then
            cp "$CONTAINERS_CONF" "${CONTAINERS_CONF}.backup.$(date +%Y%m%d%H%M%S)"
            echo "Backed up existing config"

            # Check if [engine] section exists
            if grep -q '^\[engine\]' "$CONTAINERS_CONF"; then
                # Check if runtime is already set
                if grep -q '^runtime\s*=' "$CONTAINERS_CONF"; then
                    # Replace existing runtime setting
                    sed -i 's/^runtime\s*=.*/runtime = "runc"/' "$CONTAINERS_CONF"
                else
                    # Add runtime after [engine]
                    sed -i '/^\[engine\]/a runtime = "runc"' "$CONTAINERS_CONF"
                fi
            else
                # Add [engine] section
                echo "" >> "$CONTAINERS_CONF"
                echo "[engine]" >> "$CONTAINERS_CONF"
                echo 'runtime = "runc"' >> "$CONTAINERS_CONF"
            fi
        else
            # Create new config
            cat > "$CONTAINERS_CONF" << 'EOF'
# Podman containers.conf
# Configured for checkpoint/restore support

[engine]
# Use runc as default runtime (required for checkpoint/restore)
# crun does NOT support checkpoint/restore
runtime = "runc"
EOF
        fi

        echo -e "${GREEN}✓ Created/updated $CONTAINERS_CONF${NC}"
        echo ""
        echo "Configuration:"
        cat "$CONTAINERS_CONF"
    fi
fi

#####################################
# 3. Verify CRIU Works
#####################################
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ Step 3: Verify CRIU Kernel Support${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if command -v criu &> /dev/null; then
    if criu check 2>&1 | grep -q "Looks good"; then
        echo -e "${GREEN}✓ CRIU check passed - kernel supports checkpointing${NC}"
    else
        echo -e "${YELLOW}⚠ CRIU check has warnings (may still work)${NC}"
        criu check 2>&1 | head -5
    fi
else
    echo -e "${RED}✗ CRIU not available${NC}"
fi

#####################################
# 4. Migrate Existing Containers
#####################################
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ Step 4: Migrate Existing Containers to runc${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Count containers using non-runc runtime
CONTAINER_COUNT=$(podman ps -a --format '{{.Names}}' 2>/dev/null | wc -l)

if [[ "$CONTAINER_COUNT" -gt 0 ]]; then
    echo "Found $CONTAINER_COUNT container(s)"

    # Check which containers are not using runc
    NON_RUNC_CONTAINERS=""
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            RUNTIME=$(podman inspect "$container" --format '{{.OCIRuntime}}' 2>/dev/null || echo "unknown")
            if [[ "$RUNTIME" != "runc" ]]; then
                NON_RUNC_CONTAINERS="$NON_RUNC_CONTAINERS $container"
                echo "  - $container: $RUNTIME (needs migration)"
            else
                echo "  - $container: $RUNTIME (OK)"
            fi
        fi
    done < <(podman ps -a --format '{{.Names}}' 2>/dev/null)

    if [[ -n "$NON_RUNC_CONTAINERS" ]]; then
        if [[ "$CHECK_ONLY" == true ]]; then
            echo ""
            echo -e "${YELLOW}Containers needing migration:$NON_RUNC_CONTAINERS${NC}"
            echo "Run: podman system migrate --new-runtime runc"
        else
            echo ""
            echo "Migrating containers to runc runtime..."
            if podman system migrate --new-runtime runc 2>&1; then
                echo -e "${GREEN}✓ Migration completed${NC}"
            else
                echo -e "${YELLOW}⚠ Migration had warnings (containers may need restart)${NC}"
            fi
        fi
    else
        echo -e "${GREEN}✓ All containers already using runc${NC}"
    fi
else
    echo "No existing containers found"
fi

#####################################
# 5. Restart Podman Services
#####################################
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ Step 5: Restart Podman Services${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ "$CHECK_ONLY" == true ]]; then
    echo "Would restart: podman.socket podman.service"
else
    # Restart podman socket (for Cockpit and other API users)
    if systemctl is-active podman.socket &>/dev/null || systemctl is-enabled podman.socket &>/dev/null; then
        systemctl restart podman.socket 2>/dev/null || true
        echo -e "${GREEN}✓ Restarted podman.socket${NC}"
    fi

    if systemctl is-active podman.service &>/dev/null; then
        systemctl restart podman.service 2>/dev/null || true
        echo -e "${GREEN}✓ Restarted podman.service${NC}"
    fi
fi

#####################################
# 6. Verify Setup
#####################################
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}▶ Step 6: Verify Configuration${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Re-check runtime
NEW_RUNTIME=$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || echo "unknown")
echo "Default OCI Runtime: $NEW_RUNTIME"

if [[ "$NEW_RUNTIME" == "runc" ]]; then
    echo -e "${GREEN}✓ Runtime correctly set to runc${NC}"
else
    echo -e "${RED}✗ Runtime is still $NEW_RUNTIME${NC}"
fi

# Quick checkpoint test
if [[ "$CHECK_ONLY" != true ]] && [[ "$NEW_RUNTIME" == "runc" ]]; then
    echo ""
    echo "Running quick checkpoint test..."
    podman rm -f setup-test 2>/dev/null || true

    if podman run -d --name setup-test alpine sleep 60 &>/dev/null; then
        sleep 2
        if podman container checkpoint setup-test --export=/tmp/setup-test.tar.gz &>/dev/null; then
            echo -e "${GREEN}✓ Checkpoint test PASSED${NC}"
            rm -f /tmp/setup-test.tar.gz
        else
            echo -e "${RED}✗ Checkpoint test FAILED${NC}"
        fi
        podman rm -f setup-test &>/dev/null || true
    fi
fi

#####################################
# Summary
#####################################
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        SETUP COMPLETE                         ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"

if [[ "$CHECK_ONLY" == true ]]; then
    echo -e "${YELLOW}║  Mode: CHECK ONLY (no changes made)                          ║${NC}"
    echo -e "${YELLOW}║  Run without --check to apply changes                        ║${NC}"
else
    echo -e "${GREEN}║  ✓ Podman configured for checkpoint/restore                  ║${NC}"
    echo -e "${GREEN}║  ✓ Default runtime: runc                                     ║${NC}"
    echo -e "${GREEN}║  ✓ CRIU installed and working                                ║${NC}"
fi

echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Usage:                                                       ║${NC}"
echo -e "${BLUE}║    # Create checkpoint                                        ║${NC}"
echo -e "${BLUE}║    podman container checkpoint <name> --export=file.tar.gz    ║${NC}"
echo -e "${BLUE}║                                                               ║${NC}"
echo -e "${BLUE}║    # Restore checkpoint                                       ║${NC}"
echo -e "${BLUE}║    podman container restore --import=file.tar.gz              ║${NC}"
echo -e "${BLUE}║                                                               ║${NC}"
echo -e "${BLUE}║  Cockpit UI:                                                  ║${NC}"
echo -e "${BLUE}║    Checkpoint button should now work for all containers       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
