#!/bin/bash
# Build the 6.19 kernel with optimizations
# Usage: ./build-kernel-6.19.sh

set -e
set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.19"

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch and select appropriate config
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")
if [ "$BRANCH" = "generic-build" ]; then
    CONFIG_FILE="$BASE_DIR/configs/config-6.19-generic"
    echo -e "${BLUE}Branch: generic-build - using generic (x86-64) config${NC}"
elif [ "$BRANCH" = "pixel-slate" ]; then
    CONFIG_FILE="$BASE_DIR/configs/config-6.19-pixel-slate"
    echo -e "${BLUE}Branch: pixel-slate - using Pixel Slate (camera + audio optimized) config${NC}"
else
    CONFIG_FILE="$BASE_DIR/configs/config-6.19-march-native"
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
        echo -e "${YELLOW}Warning: No config file found at $CONFIG_FILE${NC}"
        echo -e "${YELLOW}Using existing .config in kernel directory or default config${NC}"
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
if [ "$BRANCH" = "master" ] || [ "$BRANCH" = "march-native" ] || [ "$BRANCH" = "linux-6.19" ]; then
    if grep -q "CONFIG_X86_NATIVE_CPU=y" .config; then
        echo -e "${GREEN}✓ march=native enabled (CONFIG_X86_NATIVE_CPU)${NC}"
    else
        echo -e "${YELLOW}⚠ march=native not found in config, will apply via KCFLAGS${NC}"
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

# Set architecture-specific optimizations
if [ "$BRANCH" = "pixel-slate" ]; then
    echo -e "${BLUE}Applying Skylake (Kaby Lake) optimizations for Pixel Slate...${NC}"
    KCFLAGS="-march=skylake -mtune=skylake"
elif [ "$BRANCH" = "master" ] || [ "$BRANCH" = "march-native" ] || [ "$BRANCH" = "linux-6.19" ]; then
    echo -e "${BLUE}Applying march=native optimizations...${NC}"
    KCFLAGS="-march=native"
fi

export KCFLAGS

# Auto-detect LLVM version
if command -v clang-19 &> /dev/null; then
    LLVM_VERSION="-19"
elif command -v clang-20 &> /dev/null; then
    LLVM_VERSION="-20"
elif command -v clang-18 &> /dev/null; then
    LLVM_VERSION="-18"
else
    LLVM_VERSION=""  # Use system default clang
fi

echo -e "${BLUE}Using LLVM version: ${LLVM_VERSION:-system default}${NC}"
echo -e "${BLUE}KCFLAGS: ${KCFLAGS}${NC}"

# Enable ccache if available
if command -v ccache &> /dev/null; then
    export CCACHE_DIR="$HOME/.cache/ccache"
    echo -e "${BLUE}ccache enabled (cache dir: $CCACHE_DIR)${NC}"
    USE_CCACHE="ccache"
else
    USE_CCACHE=""
fi

# Clean up old 6.19 build logs
echo -e "${BLUE}Cleaning old 6.19 build logs...${NC}"
find "$BASE_DIR" -maxdepth 1 -name "build-6.19-*.log" -type f -delete 2>/dev/null || true
echo -e "${GREEN}✓ Old logs removed${NC}"

# Set up log file
LOG_FILE="$BASE_DIR/build-6.19-$(date +%Y%m%d-%H%M%S).log"

# Build and capture output
{
    echo "Build started at $(date)"
    echo "Branch: $BRANCH"
    echo "Kernel Version: $KERNEL_VERSION"
    echo "LLVM Version: ${LLVM_VERSION:-system default}"
    echo "KCFLAGS: ${KCFLAGS}"
    echo "ccache: ${USE_CCACHE:-disabled}"
    echo ""
    make LLVM=${LLVM_VERSION} HOSTCC=gcc HOSTCXX=g++ CC="${USE_CCACHE} clang${LLVM_VERSION}" -j$(nproc)
    echo ""
    echo "Build completed at $(date)"
} 2>&1 | tee "$LOG_FILE"

echo ""
echo -e "${GREEN}✓ Kernel build completed successfully!${NC}"
echo -e "${BLUE}Build log saved to: $LOG_FILE${NC}"
