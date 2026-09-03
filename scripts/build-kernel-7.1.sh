#!/bin/bash
# Build the 7.1 kernel with optimizations
# Usage: ./build-kernel-7.1.sh

set -e
set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="7.1"

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch and select appropriate config
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")
if [ "$BRANCH" = "generic-build" ]; then
    CONFIG_FILE="$BASE_DIR/configs/config-7.1-generic"
    echo -e "${BLUE}Branch: generic-build - using generic (x86-64) config${NC}"
elif [ "$BRANCH" = "pixel-slate" ]; then
    CONFIG_FILE="$BASE_DIR/configs/config-7.1-pixel-slate"
    echo -e "${BLUE}Branch: pixel-slate - using Pixel Slate (camera + audio optimized) config${NC}"
else
    CONFIG_FILE="$BASE_DIR/configs/config-7.1-march-native"
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
if [ "$BRANCH" = "master" ] || [ "$BRANCH" = "march-native" ] || [ "$BRANCH" = "linux-7.1" ]; then
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
elif [ "$BRANCH" = "master" ] || [ "$BRANCH" = "march-native" ] || [ "$BRANCH" = "linux-7.1" ]; then
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

# Clean up old 7.1 build logs
echo -e "${BLUE}Cleaning old 7.1 build logs...${NC}"
find "$BASE_DIR" -maxdepth 1 -name "build-7.1-*.log" -type f -delete 2>/dev/null || true
echo -e "${GREEN}✓ Old logs removed${NC}"

# Set up log file
LOG_FILE="$BASE_DIR/build-7.1-$(date +%Y%m%d-%H%M%S).log"

# Build and capture output
{
    echo "Build started at $(date)"
    echo "Branch: $BRANCH"
    echo "Kernel Version: $KERNEL_VERSION"
    echo "LLVM Version: ${LLVM_VERSION:-system default}"
    echo "KCFLAGS: ${KCFLAGS}"
    echo "ccache: ${USE_CCACHE:-disabled}"
    echo ""
    # LOCALVERSION= suppresses the "-dirty" suffix that scripts/setlocalversion
    # would otherwise append (our patches modify the kernel tree without
    # committing them into Linus's git history, which is expected).
    make LOCALVERSION= LLVM=${LLVM_VERSION} HOSTCC=gcc HOSTCXX=g++ CC="${USE_CCACHE} clang${LLVM_VERSION}" -j$(nproc)
    echo ""
    echo "Build completed at $(date)"
} 2>&1 | tee "$LOG_FILE"

echo ""
echo -e "${GREEN}✓ Kernel build completed successfully!${NC}"
echo -e "${BLUE}Build log saved to: $LOG_FILE${NC}"

# Package headers for DKMS/out-of-tree module builds on the target machine.
# Best-effort: a failure here does not invalidate the kernel that was just
# built successfully, so it never exits nonzero on its own.
#
# Plain tarball, not a .deb: tried the formal `dpkg`/`debian/rules
# binary-headers` route first and hit a real, unfixable wall - Debian's
# packaging tooling requires all-lowercase package names, and this
# project's own KERNELRELEASE ("...-BobZKernel-...") gets embedded
# directly in the package name, so mkdebian always fails
# (dh_listpackages rejects "linux-image-...-BobZKernel-..." outright).
# Not a flag problem, not fixable without changing KERNELRELEASE itself
# (used everywhere - module paths, GRUB entries - not worth breaking to
# satisfy Debian naming policy). A tarball has no such constraint.
#
# What's actually needed for building an out-of-tree module against
# this kernel isn't every file in the tree - it's the Kbuild
# infrastructure (Makefile/Kconfig/scripts chain), .config, and
# Module.symvers. Everything already exists correctly from the build
# above; this step only selects and archives it, no new compilation.
# The one thing worth getting right: keep scripts/'s own prebuilt host
# binaries (modpost, fixdep, kconfig's conf, etc.) since DKMS/module
# builds need those to already exist, not get rebuilt from source -
# only exclude *.o OUTSIDE scripts/ (driver/subsystem object files,
# irrelevant to a module build and the vast majority of the tree's
# size), plus *.ko/*.ko.zst/vmlinux/bzImage/System.map.
echo ""
echo -e "${BLUE}═══ Packaging headers (DKMS support) ═══${NC}"
KERNELRELEASE=$(make -s LOCALVERSION= kernelrelease 2>/dev/null)
HEADERS_TARBALL="$BASE_DIR/linux-headers-$KERNELRELEASE.tar.gz"
HEADERS_FILELIST=$(mktemp)
find . -path './.git' -prune -o \
    \( -name "*.o" ! -path "./scripts/*" \) -prune -o \
    -name "*.ko" -prune -o \
    -name "*.ko.zst" -prune -o \
    -path "./vmlinux" -prune -o \
    -path "./arch/x86/boot/bzImage" -prune -o \
    -path "./System.map" -prune -o \
    -type f -print | sed 's|^\./||' > "$HEADERS_FILELIST"
if tar czf "$HEADERS_TARBALL" \
    --transform "s,^,linux-headers-$KERNELRELEASE/," \
    -T "$HEADERS_FILELIST"; then
    echo -e "${GREEN}✓ Headers package: $(basename "$HEADERS_TARBALL") ($(du -h "$HEADERS_TARBALL" | cut -f1))${NC}"
else
    echo -e "${YELLOW}⚠ Headers packaging failed - kernel itself is still fine, just no DKMS support this build${NC}"
    rm -f "$HEADERS_TARBALL"
fi
rm -f "$HEADERS_FILELIST"
