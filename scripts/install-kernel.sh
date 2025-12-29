#!/bin/bash
# BobZKernel Installation Script
# Installs the custom kernel and updates bootloader

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

KERNEL_DIR="/home/bob/buildstuff/KernelDev/builds/linux"
LOCALVERSION="-BobZKernel"

echo -e "${BLUE}=== BobZKernel Installation Script ===${NC}"
echo "Installing Linux kernel $LOCALVERSION"
echo ""

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    exit 1
fi

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: Kernel directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

cd "$KERNEL_DIR"

# Check if kernel was built
if [ ! -f "arch/x86/boot/bzImage" ]; then
    echo -e "${RED}Error: Kernel image not found. Run build script first.${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Installing kernel...${NC}"
make LOCALVERSION=$LOCALVERSION install

echo -e "${BLUE}Step 2: Installing modules...${NC}"
make LOCALVERSION=$LOCALVERSION modules_install

KERNEL_VERSION=$(make LOCALVERSION=$LOCALVERSION kernelrelease)

echo -e "${BLUE}Step 3: Compressing modules with zstd...${NC}"
find /lib/modules/$KERNEL_VERSION -name '*.ko' -exec zstd --rm -q -T0 {} \;
depmod -a $KERNEL_VERSION

echo -e "${BLUE}Step 4: Building DKMS modules for new kernel...${NC}"
echo "Building DKMS modules for kernel: $KERNEL_VERSION"

# Build all DKMS modules for the new kernel
dkms autoinstall -k "$KERNEL_VERSION" || {
    echo -e "${YELLOW}Warning: Some DKMS modules failed to build${NC}"
    echo -e "${YELLOW}You may need to rebuild them manually after boot${NC}"
}

echo -e "${BLUE}Step 5: Regenerating initramfs...${NC}"
update-initramfs -c -k $KERNEL_VERSION

echo -e "${BLUE}Step 6: Updating bootloader...${NC}"
update-grub

echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Before rebooting, ensure you have a way to boot${NC}"
echo -e "${YELLOW}your current kernel if the new one doesn't work.${NC}"
echo ""
echo -e "${BLUE}To boot the new kernel:${NC}"
echo "  1. Reboot your system"
echo "  2. At GRUB menu, select 'Linux 6.14.0$LOCALVERSION'"
echo "  3. If it boots successfully, you're good!"
echo "  4. If it fails, select your old kernel to boot back"