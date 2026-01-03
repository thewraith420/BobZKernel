#!/bin/bash
# Build VMware modules (vmmon, vmnet) with Clang for kernel compatibility
# Automatically patches function prototypes that fail with strict-prototypes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

KERNEL_VERSION="${1:-}"
KBUILD_DIR="/lib/modules/$KERNEL_VERSION/build"

if [ -z "$KERNEL_VERSION" ]; then
    echo -e "${RED}Error: kernel version required${NC}"
    echo "Usage: $0 <kernel_version>"
    exit 1
fi

echo -e "${BLUE}=== Building VMware Modules for $KERNEL_VERSION ===${NC}"
echo ""
# Set the working directory for building

# Check if VMware modules are installed
if [ ! -f "/usr/lib/vmware/modules/source/vmmon.tar" ]; then
    echo -e "${YELLOW}VMware modules not found. Skipping.${NC}"
    exit 0
fi

WORK_DIR="/tmp/vmware-build-$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo -e "${BLUE}Step 1: Extracting VMware source archives...${NC}"
tar -xf /usr/lib/vmware/modules/source/vmmon.tar
tar -xf /usr/lib/vmware/modules/source/vmnet.tar
echo -e "${GREEN}✓ Extracted${NC}"

# Patch vmmon - VNetFreeInterfaceList prototype
echo -e "${BLUE}Step 2: Patching vmmon prototypes...${NC}"
if [ -f "vmmon-only/driver.c" ]; then
    sed -i 's/VNetFreeInterfaceList()$/VNetFreeInterfaceList(void)/' vmmon-only/driver.c
    echo -e "${GREEN}✓ vmmon patched${NC}"
fi

# Patch vmnet - function prototypes
echo -e "${BLUE}Step 3: Patching vmnet prototypes...${NC}"
if [ -f "vmnet-only/driver.c" ]; then
    sed -i 's/VNetFreeInterfaceList()$/VNetFreeInterfaceList(void)/' vmnet-only/driver.c
    echo -e "${GREEN}✓ vmnet driver.c patched${NC}"
fi

if [ -f "vmnet-only/smac_compat.c" ]; then
    sed -i 's/SMACL_GetUptime()$/SMACL_GetUptime(void)/' vmnet-only/smac_compat.c
    echo -e "${GREEN}✓ vmnet smac_compat.c patched${NC}"
fi

# Build vmmon
echo -e "${BLUE}Step 4: Building vmmon module...${NC}"
cd vmmon-only
make VM_UNAME="$KERNEL_VERSION" LLVM=1 CC=clang LD=ld.lld 2>&1 | grep -E "Error|error:|✓|Building" || true
if [ -f vmmon.ko ]; then
    echo -e "${GREEN}✓ vmmon built${NC}"
else
    echo -e "${RED}✗ vmmon build failed - vmmon.ko not found${NC}"
    exit 1
fi
cd ..

# Build vmnet
echo -e "${BLUE}Step 5: Building vmnet module...${NC}"
cd vmnet-only
make VM_UNAME="$KERNEL_VERSION" LLVM=1 CC=clang LD=ld.lld 2>&1 | grep -E "Error|error:|✓|Building" || true
if [ -f vmnet.ko ]; then
    echo -e "${GREEN}✓ vmnet built${NC}"
else
    echo -e "${RED}✗ vmnet build failed - vmnet.ko not found${NC}"
    exit 1
fi
cd ..

# Install modules
echo -e "${BLUE}Step 6: Installing VMware modules...${NC}"
MODULES_DIR="/lib/modules/$KERNEL_VERSION/misc"

if [ ! -d "$MODULES_DIR" ]; then
    echo -e "${YELLOW}Creating $MODULES_DIR${NC}"
    sudo mkdir -p "$MODULES_DIR"
fi

sudo install -D -m 644 vmmon-only/vmmon.ko "$MODULES_DIR/vmmon.ko"
sudo install -D -m 644 vmnet-only/vmnet.ko "$MODULES_DIR/vmnet.ko"
echo -e "${GREEN}✓ Modules installed${NC}"

# Update depmod
echo -e "${BLUE}Step 7: Updating module dependencies...${NC}"
sudo depmod -a "$KERNEL_VERSION"
echo -e "${GREEN}✓ depmod updated${NC}"

# Cleanup
echo -e "${BLUE}Step 8: Cleaning up build directory...${NC}"
cd /
rm -rf "$WORK_DIR"

echo -e "${GREEN}=== VMware Module Build Complete ===${NC}"
echo ""
echo "To load modules:"
echo "  sudo modprobe vmmon"
echo "  sudo modprobe vmnet"
echo ""
echo "To start VMware networking:"
echo "  sudo /usr/bin/vmware-networks --start"
