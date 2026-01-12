#!/bin/bash
# Build VMware modules for new kernel
# Usage: ./build-vmware-modules.sh KERNEL_VERSION
#
# This script builds VMware vmmon and vmnet modules for kernels compiled with Clang.
# It applies necessary prototype fixes for modern kernel compatibility.

set -e

KERNEL_VERSION="$1"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$BASE_DIR/builds/linux-6.18"
WORK_DIR="/tmp/vmware-modules-$$"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$KERNEL_VERSION" ]; then
    # Auto-detect from running kernel if not specified
    KERNEL_VERSION=$(uname -r)
fi

# Check if VMware is installed
if [ ! -d "/usr/lib/vmware" ]; then
    echo "VMware not installed, skipping"
    exit 0
fi

if [ ! -f "/usr/lib/vmware/modules/source/vmmon.tar" ]; then
    echo "VMware module sources not found, skipping"
    exit 0
fi

echo -e "${GREEN}Building VMware modules for kernel $KERNEL_VERSION...${NC}"

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Extract module sources
echo "Extracting vmmon and vmnet sources..."
tar xf /usr/lib/vmware/modules/source/vmmon.tar
tar xf /usr/lib/vmware/modules/source/vmnet.tar

# Apply prototype fixes for modern kernels (C23 compatibility)
echo "Applying prototype fixes..."

# Fix vmnet driver.c - VNetFreeInterfaceList needs void parameter
sed -i 's/VNetFreeInterfaceList()$/VNetFreeInterfaceList(void)/' vmnet-only/driver.c

# Fix vmnet smac_compat.c - SMACL_GetUptime needs void parameter
sed -i 's/SMACL_GetUptime()$/SMACL_GetUptime(void)/' vmnet-only/smac_compat.c

# Build vmmon with clang (required for clang-built kernels)
echo -e "${YELLOW}Building vmmon...${NC}"
cd "$WORK_DIR/vmmon-only"
make CC=clang LD=ld.lld VM_UNAME="$KERNEL_VERSION" || {
    echo -e "${RED}vmmon build failed${NC}"
    rm -rf "$WORK_DIR"
    exit 1
}

# Build vmnet with clang
echo -e "${YELLOW}Building vmnet...${NC}"
cd "$WORK_DIR/vmnet-only"
make CC=clang LD=ld.lld VM_UNAME="$KERNEL_VERSION" || {
    echo -e "${RED}vmnet build failed${NC}"
    rm -rf "$WORK_DIR"
    exit 1
}

# Install modules
echo "Installing modules to /lib/modules/$KERNEL_VERSION/misc/..."
mkdir -p "/lib/modules/$KERNEL_VERSION/misc"
cp "$WORK_DIR/vmmon-only/vmmon.ko" "/lib/modules/$KERNEL_VERSION/misc/"
cp "$WORK_DIR/vmnet-only/vmnet.ko" "/lib/modules/$KERNEL_VERSION/misc/"

# Update module dependencies
depmod -a "$KERNEL_VERSION"

# Cleanup
rm -rf "$WORK_DIR"

echo -e "${GREEN}VMware modules built and installed successfully${NC}"

# Try to load modules if we're running the target kernel
if [ "$(uname -r)" = "$KERNEL_VERSION" ]; then
    echo "Loading modules..."
    modprobe vmmon 2>/dev/null || true
    modprobe vmnet 2>/dev/null || true
fi
