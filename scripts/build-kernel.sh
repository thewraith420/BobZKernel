#!/bin/bash
# BobZKernel Build Script
# Builds a custom Linux kernel for Lenovo Legion laptop

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

KERNEL_DIR="/home/bob/buildstuff/BobzKernel/builds/linux"
CONFIG_FILE="/home/bob/buildstuff/BobzKernel/configs/.config"
LOCALVERSION="-BobZKernel"
NUM_JOBS="${1:-1}"  # Default to single job to avoid interruptions

echo -e "${BLUE}=== BobZKernel Build Script ===${NC}"
echo "Building Linux kernel $LOCALVERSION for Lenovo Legion"
echo "Kernel directory: $KERNEL_DIR"
echo "Build jobs: $NUM_JOBS"
echo ""

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: Kernel directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

cd "$KERNEL_DIR"

# Clean any previous build artifacts
echo -e "${BLUE}Step 1: Cleaning previous build...${NC}"
make mrproper

# Copy our config
echo -e "${BLUE}Step 2: Applying kernel configuration...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" .config
    echo "Configuration applied from $CONFIG_FILE"
else
    echo -e "${RED}Warning: Config file not found, using defconfig${NC}"
    make defconfig
fi

# Build the kernel
echo -e "${BLUE}Step 3: Building kernel image (this may take 10-30 minutes)...${NC}"
make LOCALVERSION=$LOCALVERSION -j$NUM_JOBS bzImage

# Build modules
echo -e "${BLUE}Step 4: Building kernel modules...${NC}"
make LOCALVERSION=$LOCALVERSION -j$NUM_JOBS modules

echo -e "${GREEN}=== Build Complete! ===${NC}"
echo ""
echo "Kernel image: arch/x86/boot/bzImage"
echo "LOCALVERSION: $LOCALVERSION"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Install kernel: sudo make LOCALVERSION=$LOCALVERSION install"
echo "  2. Install modules: sudo make LOCALVERSION=$LOCALVERSION modules_install"
echo "  3. Update bootloader: sudo update-grub"
echo "  4. Reboot and select 'Linux 6.14.0$LOCALVERSION' from GRUB"
