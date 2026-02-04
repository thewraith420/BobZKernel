#!/bin/bash
# Install build dependencies for BobZKernel on Debian
# Uses askpass for sudo operations

set -e

# Set up askpass
export SUDO_ASKPASS=/home/bob/buildstuff/BobZKernel/scripts/askpass-helper.sh

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}BobZKernel - Installing Build Dependencies${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Clean up problematic LLVM repo if exists
if [ -f /etc/apt/sources.list.d/llvm.list ]; then
    echo -e "${YELLOW}Removing problematic LLVM repository...${NC}"
    sudo -A rm -f /etc/apt/sources.list.d/llvm.list /etc/apt/trusted.gpg.d/apt.llvm.org.asc
fi

# Update package lists
echo -e "${BLUE}Updating package lists...${NC}"
sudo -A apt update

# Install core build tools
echo ""
echo -e "${BLUE}Installing core build tools...${NC}"
sudo -A apt install -y \
    build-essential \
    bc \
    bison \
    flex \
    libelf-dev \
    libssl-dev \
    libncurses-dev \
    dwarves \
    git \
    curl \
    wget \
    tar \
    gzip \
    xz-utils \
    zstd \
    cpio \
    rsync \
    kmod \
    debhelper \
    fakeroot

# Install LLVM/Clang from Debian repos
echo ""
echo -e "${BLUE}Installing LLVM/Clang 19 from Debian repositories...${NC}"
sudo -A apt install -y \
    clang-19 \
    llvm-19 \
    lld-19 \
    llvm-19-dev \
    llvm-19-tools

# Also install generic clang packages that point to version 19
sudo -A apt install -y clang llvm lld

# Set up alternatives for LLVM 19
echo ""
echo -e "${BLUE}Setting up compiler alternatives...${NC}"
sudo -A update-alternatives --install /usr/bin/clang clang /usr/bin/clang-19 100
sudo -A update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100
sudo -A update-alternatives --install /usr/bin/llvm-ar llvm-ar /usr/bin/llvm-ar-19 100
sudo -A update-alternatives --install /usr/bin/llvm-nm llvm-nm /usr/bin/llvm-nm-19 100
sudo -A update-alternatives --install /usr/bin/llvm-strip llvm-strip /usr/bin/llvm-strip-19 100
sudo -A update-alternatives --install /usr/bin/llvm-objcopy llvm-objcopy /usr/bin/llvm-objcopy-19 100
sudo -A update-alternatives --install /usr/bin/llvm-objdump llvm-objdump /usr/bin/llvm-objdump-19 100
sudo -A update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-19 100

# Install DKMS
echo ""
echo -e "${BLUE}Installing DKMS (for out-of-tree modules)...${NC}"
sudo -A apt install -y dkms

# Install kernel build utilities
echo ""
echo -e "${BLUE}Installing kernel build utilities...${NC}"
sudo -A apt install -y kernel-package || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Installation complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Verifying installation...${NC}"
echo ""

# Verify key tools
clang --version | head -n1
ld.lld --version | head -n1
make --version | head -n1

echo ""
echo -e "${GREEN}Build environment is ready!${NC}"
echo ""
echo "Next steps:"
echo -e "  ${BLUE}cd /home/bob/buildstuff/BobZKernel${NC}"
echo -e "  ${BLUE}./scripts/update-and-build.sh 6.18${NC}"
