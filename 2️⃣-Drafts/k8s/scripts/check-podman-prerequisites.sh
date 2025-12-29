#!/bin/bash
#
# Podman CRIU Checkpoint Prerequisites Check Script
# Checks and optionally installs all requirements for container checkpointing
#
# Usage:
#   ./check-podman-prerequisites.sh          # Check only
#   ./check-podman-prerequisites.sh --install # Check and install missing packages
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

INSTALL_MODE=false
FAILED_CHECKS=0
PASSED_CHECKS=0

if [[ "$1" == "--install" || "$1" == "-i" ]]; then
    INSTALL_MODE=true
fi

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Podman CRIU Checkpoint Prerequisites Checker                ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_NAME=$(cat /etc/redhat-release)
    else
        OS="unknown"
        OS_NAME="Unknown"
    fi
}

# Function to print check result
print_check() {
    local status=$1
    local name=$2
    local details=$3

    if [[ "$status" == "pass" ]]; then
        echo -e "${GREEN}✓${NC} ${name}: ${details}"
        ((PASSED_CHECKS++))
    elif [[ "$status" == "warn" ]]; then
        echo -e "${YELLOW}⚠${NC} ${name}: ${details}"
    else
        echo -e "${RED}✗${NC} ${name}: ${details}"
        ((FAILED_CHECKS++))
    fi
}

# Function to print section header
print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▶ $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Install package based on OS
install_package() {
    local pkg=$1
    if [[ "$INSTALL_MODE" != true ]]; then
        echo "  Run with --install to install automatically"
        return 1
    fi

    echo "  Installing $pkg..."
    case $OS in
        ubuntu|debian)
            apt-get update -qq && apt-get install -y "$pkg"
            ;;
        fedora)
            dnf install -y "$pkg"
            ;;
        centos|rhel|rocky|almalinux)
            dnf install -y "$pkg" || yum install -y "$pkg"
            ;;
        arch)
            pacman -S --noconfirm "$pkg"
            ;;
        *)
            echo "  Cannot auto-install on $OS. Please install $pkg manually."
            return 1
            ;;
    esac
}

#####################################
# System Information
#####################################
print_section "System Information"
detect_os
echo "OS: $OS_NAME"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"

#####################################
# 1. Check Root/Sudo Access
#####################################
print_section "1. Root/Sudo Access"

if [[ $EUID -eq 0 ]]; then
    print_check "pass" "Root access" "Running as root"
else
    if sudo -n true 2>/dev/null; then
        print_check "pass" "Sudo access" "Passwordless sudo available"
    else
        print_check "warn" "Sudo access" "Need to run checkpoint commands with sudo"
    fi
fi

#####################################
# 2. Check Podman Installation
#####################################
print_section "2. Podman Installation"

if command -v podman &> /dev/null; then
    PODMAN_VERSION=$(podman --version)
    print_check "pass" "Podman installed" "$PODMAN_VERSION"

    # Check Podman version (CRIU support improved in 3.0+)
    VERSION_NUM=$(podman --version | grep -oP '[0-9]+\.[0-9]+' | head -1)
    MAJOR_VER=$(echo "$VERSION_NUM" | cut -d. -f1)
    MINOR_VER=$(echo "$VERSION_NUM" | cut -d. -f2)

    if [[ "$MAJOR_VER" -ge 4 ]]; then
        print_check "pass" "Podman version" "v$VERSION_NUM (excellent CRIU support)"
    elif [[ "$MAJOR_VER" -ge 3 ]]; then
        print_check "pass" "Podman version" "v$VERSION_NUM (good CRIU support)"
    else
        print_check "warn" "Podman version" "v$VERSION_NUM (consider upgrading to 4.x+)"
    fi
else
    print_check "fail" "Podman installed" "Not found"
    echo ""
    echo "  Install Podman:"
    case $OS in
        ubuntu|debian)
            echo "    apt-get update && apt-get install -y podman"
            ;;
        fedora)
            echo "    dnf install -y podman"
            ;;
        centos|rhel|rocky|almalinux)
            echo "    dnf install -y podman"
            ;;
        *)
            echo "    See https://podman.io/getting-started/installation"
            ;;
    esac
    install_package "podman"
fi

#####################################
# 3. Check CRIU Installation
#####################################
print_section "3. CRIU Installation"

if command -v criu &> /dev/null; then
    CRIU_VERSION=$(criu --version 2>&1 | head -n1)
    print_check "pass" "CRIU installed" "$CRIU_VERSION"

    # Check CRIU version (3.11+ recommended for Podman)
    CRIU_VER=$(criu --version 2>&1 | grep -oP '[0-9]+\.[0-9]+' | head -1)
    CRIU_MAJOR=$(echo "$CRIU_VER" | cut -d. -f1)
    CRIU_MINOR=$(echo "$CRIU_VER" | cut -d. -f2)

    if [[ "$CRIU_MAJOR" -ge 3 && "$CRIU_MINOR" -ge 15 ]]; then
        print_check "pass" "CRIU version" "v$CRIU_VER (optimal for Podman)"
    elif [[ "$CRIU_MAJOR" -ge 3 && "$CRIU_MINOR" -ge 11 ]]; then
        print_check "pass" "CRIU version" "v$CRIU_VER (minimum requirement met)"
    else
        print_check "warn" "CRIU version" "v$CRIU_VER (recommend 3.11+)"
    fi
else
    print_check "fail" "CRIU installed" "Not found"
    echo ""
    echo "  Install CRIU:"
    case $OS in
        ubuntu|debian)
            echo "    apt-get update && apt-get install -y criu"
            ;;
        fedora)
            echo "    dnf install -y criu"
            ;;
        centos|rhel|rocky|almalinux)
            echo "    dnf install -y criu"
            ;;
        *)
            echo "    See https://criu.org/Installation"
            ;;
    esac
    install_package "criu"
fi

#####################################
# 4. Kernel Configuration
#####################################
print_section "4. Kernel Configuration"

# Check kernel version (4.x+ recommended)
KERNEL_VER=$(uname -r | cut -d. -f1,2)
KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
if [[ "$KERNEL_MAJOR" -ge 5 ]]; then
    print_check "pass" "Kernel version" "$(uname -r) (excellent)"
elif [[ "$KERNEL_MAJOR" -ge 4 ]]; then
    print_check "pass" "Kernel version" "$(uname -r) (good)"
else
    print_check "warn" "Kernel version" "$(uname -r) (may have issues)"
fi

# Check for user namespaces
if [[ -f /proc/sys/kernel/unprivileged_userns_clone ]]; then
    USERNS=$(cat /proc/sys/kernel/unprivileged_userns_clone)
    if [[ "$USERNS" == "1" ]]; then
        print_check "pass" "User namespaces" "Enabled"
    else
        print_check "warn" "User namespaces" "Disabled (enable with: echo 1 > /proc/sys/kernel/unprivileged_userns_clone)"
    fi
else
    print_check "pass" "User namespaces" "Default enabled (no sysctl)"
fi

# Check for cgroup v2
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    print_check "pass" "Cgroups" "v2 (unified)"
elif [[ -d /sys/fs/cgroup/memory ]]; then
    print_check "warn" "Cgroups" "v1 (legacy - consider upgrading to v2)"
else
    print_check "warn" "Cgroups" "Unknown configuration"
fi

#####################################
# 5. CRIU Functionality Check
#####################################
print_section "5. CRIU Kernel Support Check"

if command -v criu &> /dev/null; then
    echo "Running CRIU kernel check (this may take a moment)..."
    echo ""

    # Run CRIU check and capture output
    if CRIU_CHECK=$(criu check 2>&1); then
        print_check "pass" "CRIU basic check" "All core features supported"
    else
        print_check "fail" "CRIU basic check" "Some features missing"
        echo "  Details: $CRIU_CHECK"
    fi

    # Check specific features important for containers
    echo ""
    echo "Checking specific CRIU features..."

    # Check userfaultfd (important for lazy restore)
    if criu check --feature userfaultfd 2>/dev/null; then
        print_check "pass" "userfaultfd" "Supported (enables lazy page restoration)"
    else
        print_check "warn" "userfaultfd" "Not available (lazy restore disabled)"
    fi

    # Check memfd (for memory file descriptors)
    if criu check --feature memfd 2>/dev/null; then
        print_check "pass" "memfd" "Supported"
    else
        print_check "warn" "memfd" "Not available"
    fi

    # Check pidfd (for process file descriptors)
    if criu check --feature pidfd 2>/dev/null; then
        print_check "pass" "pidfd" "Supported"
    else
        print_check "warn" "pidfd" "Not available"
    fi
else
    print_check "fail" "CRIU check" "CRIU not installed"
fi

#####################################
# 6. Container Runtime Check
#####################################
print_section "6. Container Runtime Configuration"

if command -v podman &> /dev/null; then
    # Check default OCI runtime
    RUNTIME=$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || echo "unknown")
    print_check "pass" "OCI Runtime" "$RUNTIME"

    # Check storage driver
    STORAGE=$(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo "unknown")
    if [[ "$STORAGE" == "overlay" ]]; then
        print_check "pass" "Storage driver" "$STORAGE (optimal)"
    elif [[ "$STORAGE" == "vfs" ]]; then
        print_check "warn" "Storage driver" "$STORAGE (slow - consider overlay)"
    else
        print_check "pass" "Storage driver" "$STORAGE"
    fi

    # Check rootless vs rootful
    ROOTLESS=$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || echo "unknown")
    if [[ "$ROOTLESS" == "true" ]]; then
        print_check "warn" "Rootless mode" "Yes (checkpoint requires root/sudo)"
    else
        print_check "pass" "Rootless mode" "No (running as root)"
    fi
fi

#####################################
# 7. Required Directories and Permissions
#####################################
print_section "7. Required Directories"

# Check /tmp access (for checkpoints)
if [[ -w /tmp ]]; then
    print_check "pass" "/tmp directory" "Writable"
else
    print_check "fail" "/tmp directory" "Not writable"
fi

# Check /var/lib/containers (Podman storage)
if [[ -d /var/lib/containers ]]; then
    print_check "pass" "Podman storage" "/var/lib/containers exists"
else
    print_check "warn" "Podman storage" "/var/lib/containers not found (will be created)"
fi

# Check for runc or crun
if command -v crun &> /dev/null; then
    print_check "pass" "Container runtime" "crun available ($(crun --version | head -1))"
elif command -v runc &> /dev/null; then
    print_check "pass" "Container runtime" "runc available ($(runc --version | head -1))"
else
    print_check "fail" "Container runtime" "Neither runc nor crun found"
    install_package "crun"
fi

#####################################
# 8. Quick Functional Test
#####################################
print_section "8. Quick Functional Test"

if [[ $EUID -eq 0 ]] && command -v podman &> /dev/null && command -v criu &> /dev/null; then
    echo "Running quick checkpoint test..."

    # Clean up any previous test
    podman rm -f prereq-test 2>/dev/null || true

    # Try to run and checkpoint a simple container
    if podman run -d --name prereq-test alpine:latest sleep 60 2>/dev/null; then
        sleep 2
        if podman container checkpoint prereq-test --export=/tmp/prereq-test.tar.gz 2>/dev/null; then
            print_check "pass" "Checkpoint test" "Container checkpoint works!"
            rm -f /tmp/prereq-test.tar.gz
        else
            print_check "fail" "Checkpoint test" "Checkpoint command failed"
        fi
        podman rm -f prereq-test 2>/dev/null || true
    else
        print_check "fail" "Container test" "Could not start test container"
    fi
else
    if [[ $EUID -ne 0 ]]; then
        print_check "warn" "Checkpoint test" "Skipped (requires root)"
        echo "  Run as root to perform full functional test"
    else
        print_check "warn" "Checkpoint test" "Skipped (missing dependencies)"
    fi
fi

#####################################
# Summary
#####################################
print_section "Summary"

echo ""
TOTAL=$((PASSED_CHECKS + FAILED_CHECKS))
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                 PREREQUISITES CHECK SUMMARY                   ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Total Checks:  $TOTAL                                               ║${NC}"
echo -e "${GREEN}║  Passed:        $PASSED_CHECKS                                               ║${NC}"
if [[ $FAILED_CHECKS -gt 0 ]]; then
echo -e "${RED}║  Failed:        $FAILED_CHECKS                                               ║${NC}"
else
echo -e "${GREEN}║  Failed:        0                                               ║${NC}"
fi
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════╣${NC}"

if [[ $FAILED_CHECKS -eq 0 ]]; then
    echo -e "${GREEN}║  ✓ All prerequisites met! Ready for checkpoint testing.       ║${NC}"
    echo -e "${GREEN}║                                                               ║${NC}"
    echo -e "${GREEN}║  Next step: Run the checkpoint test script:                   ║${NC}"
    echo -e "${GREEN}║    sudo ./test-podman-checkpoint.sh                           ║${NC}"
else
    echo -e "${RED}║  ✗ Some prerequisites are missing. Please install them first. ║${NC}"
    echo -e "${YELLOW}║                                                               ║${NC}"
    echo -e "${YELLOW}║  Quick fix for Ubuntu/Debian:                                 ║${NC}"
    echo -e "${YELLOW}║    sudo apt-get update && sudo apt-get install -y podman criu ║${NC}"
    echo -e "${YELLOW}║                                                               ║${NC}"
    echo -e "${YELLOW}║  Or run this script with --install flag:                      ║${NC}"
    echo -e "${YELLOW}║    sudo ./check-podman-prerequisites.sh --install             ║${NC}"
fi

echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"

echo ""

# Exit with appropriate code
if [[ $FAILED_CHECKS -gt 0 ]]; then
    exit 1
else
    exit 0
fi
