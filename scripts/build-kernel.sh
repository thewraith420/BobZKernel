#!/bin/bash
# Build the kernel with optimizations
# Usage: ./build-kernel.sh

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.18"

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"
CONFIG_FILE="$BASE_DIR/config-$KERNEL_VERSION"

if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: Kernel directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

cd "$KERNEL_DIR"

# Copy config if it doesn't exist
if [ ! -f .config ]; then
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}Copying config from $CONFIG_FILE...${NC}"
        cp "$CONFIG_FILE" .config
    else
        echo -e "${RED}Error: No .config found and no config-$KERNEL_VERSION in base directory${NC}"
        exit 1
    fi
fi

# Show build configuration
echo -e "${BLUE}Build Configuration:${NC}"
echo "  Kernel Version: $KERNEL_VERSION"
echo "  Build Directory: $KERNEL_DIR"
echo "  Compiler: Clang/LLVM"
echo "  Jobs: $(nproc)"
echo ""

# Verify critical optimizations are enabled
echo -e "${BLUE}Verifying optimizations...${NC}"
if grep -q "CONFIG_X86_NATIVE_CPU=y" .config; then
    echo -e "${GREEN}✓ march=native enabled (CONFIG_X86_NATIVE_CPU)${NC}"
else
    echo -e "${YELLOW}⚠ march=native not found in config${NC}"
fi

if grep -q "CONFIG_LTO_CLANG_FULL=y" .config; then
    echo -e "${GREEN}✓ Full LTO enabled (CONFIG_LTO_CLANG_FULL)${NC}"
else
    echo -e "${YELLOW}⚠ Full LTO not found in config${NC}"
fi

if grep -q "CONFIG_SCHED_BORE=y" .config; then
    echo -e "${GREEN}✓ BORE scheduler enabled (CONFIG_SCHED_BORE)${NC}"
else
    echo -e "${YELLOW}⚠ BORE scheduler not found in config${NC}"
fi

echo ""
echo -e "${BLUE}Starting kernel build...${NC}"
echo ""

# Build kernel with LLVM and custom localversion
make LLVM=1 LOCALVERSION=-BobZKernel -j$(nproc) 2>&1 | tee "$BASE_DIR/build-$KERNEL_VERSION.log"

echo ""
echo -e "${GREEN}✓ Kernel build completed successfully!${NC}"
echo -e "${BLUE}Build log saved to: $BASE_DIR/build-$KERNEL_VERSION.log${NC}"
