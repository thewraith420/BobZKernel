#!/bin/bash
# Build the kernel with optimizations
# Usage: ./build-kernel.sh

set -e
set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.18"

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch and select appropriate config
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")
if [ "$BRANCH" = "generic-build" ]; then
    CONFIG_FILE="$BASE_DIR/configs/config-6.18.3-generic"
    echo -e "${BLUE}Branch: generic-build - using generic (x86-64) config${NC}"
elif [ "$BRANCH" = "pixel-slate" ]; then
    CONFIG_FILE="$BASE_DIR/configs/config-6.18.6-pixel-slate"
    echo -e "${BLUE}Branch: pixel-slate - using Pixel Slate (camera + audio optimized) config${NC}"
else
    CONFIG_FILE="$BASE_DIR/configs/config-6.18.3-march-native"
    echo -e "${BLUE}Branch: $BRANCH - using march=native config${NC}"
fi

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

# Verify critical optimizations are enabled based on branch
echo -e "${BLUE}Verifying optimizations...${NC}"

# Check march settings per branch
if [ "$BRANCH" = "master" ] || [ "$BRANCH" = "march-native" ]; then
    if grep -q "CONFIG_X86_NATIVE_CPU=y" .config; then
        echo -e "${GREEN}✓ march=native enabled (CONFIG_X86_NATIVE_CPU)${NC}"
    else
        echo -e "${YELLOW}⚠ march=native not found in config${NC}"
    fi
elif [ "$BRANCH" = "pixel-slate" ]; then
    echo -e "${GREEN}✓ march=skylake optimizations will be applied (Pixel Slate - Kaby Lake)${NC}"
else
    echo -e "${YELLOW}⚠ Using generic x86-64 optimizations on $BRANCH branch${NC}"
fi

# Check LTO status
if grep -q "CONFIG_LTO_CLANG_FULL=y" .config; then
    echo -e "${GREEN}✓ Full LTO enabled (CONFIG_LTO_CLANG_FULL)${NC}"
elif grep -q "CONFIG_LTO_NONE=y" .config; then
    echo -e "${YELLOW}⚠ LTO disabled (CONFIG_LTO_NONE)${NC}"
else
    echo -e "${YELLOW}⚠ LTO status unknown${NC}"
fi

echo ""
echo -e "${BLUE}Starting kernel build...${NC}"
echo ""

# Set architecture-specific optimizations for pixel-slate branch
if [ "$BRANCH" = "pixel-slate" ]; then
    echo -e "${BLUE}Applying Skylake (Kaby Lake) optimizations for Pixel Slate...${NC}"
    KCFLAGS="-march=skylake -mtune=skylake"
    export KCFLAGS
fi

# Build kernel with LLVM (don't override LOCALVERSION - let config file define it)
make LLVM=-20 -j$(nproc) 2>&1 | tee "$BASE_DIR/build-$KERNEL_VERSION.log"

echo ""
echo -e "${GREEN}✓ Kernel build completed successfully!${NC}"
echo -e "${BLUE}Build log saved to: $BASE_DIR/build-$KERNEL_VERSION.log${NC}"
