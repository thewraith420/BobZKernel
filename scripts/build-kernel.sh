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
CONFIG_FILE="/home/bob/buildstuff/BobzKernel/configs/.config-6.18"
LOCALVERSION="-BobZKernel-6.18"
NUM_JOBS="${1:-11}"  # Default to 11 jobs (leaves 1 core free for usability)
BUILD_LOG="/home/bob/buildstuff/BobzKernel/build.log"

echo -e "${BLUE}=== BobZKernel Build Script ===${NC}"
echo "Building Linux kernel $LOCALVERSION for Lenovo Legion"
echo "Kernel directory: $KERNEL_DIR"
echo "Build jobs: $NUM_JOBS"
echo "Compiler: LLVM/Clang"
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
    # Auto-accept defaults for any new/changed config options
    make LLVM=1 olddefconfig
else
    echo -e "${RED}Warning: Config file not found, using defconfig${NC}"
    make defconfig
fi

# Build the kernel with LLVM/Clang
echo -e "${BLUE}Step 3: Building kernel image (this may take 10-30 minutes)...${NC}"
make LLVM=1 LOCALVERSION=$LOCALVERSION -j$NUM_JOBS bzImage 2>&1 | tee -a "$BUILD_LOG"

# Build modules
echo -e "${BLUE}Step 4: Building kernel modules...${NC}"
make LLVM=1 LOCALVERSION=$LOCALVERSION -j$NUM_JOBS modules 2>&1 | tee -a "$BUILD_LOG"

echo -e "${GREEN}=== Build Complete! ===${NC}"
echo ""
echo "Kernel image: arch/x86/boot/bzImage"
echo "LOCALVERSION: $LOCALVERSION"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Install kernel: sudo make LLVM=1 LOCALVERSION=$LOCALVERSION install"
echo "  2. Install modules: sudo make LLVM=1 LOCALVERSION=$LOCALVERSION modules_install"
echo "  3. Update bootloader: sudo update-grub"
echo "  4. Reboot and select 'Linux 6.18.0$LOCALVERSION' from GRUB"
