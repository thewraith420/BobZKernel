#!/bin/bash
# BobZKernel - Debian Build Environment Setup Script
# Sets up all dependencies needed to build the custom kernel on Debian 13 (Trixie)

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}BobZKernel - Debian Build Environment Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}ERROR: Do not run this script as root or with sudo${NC}"
    echo "Run it as a normal user. You'll be prompted for sudo when needed."
    exit 1
fi

# Verify Debian
if ! grep -q "ID=debian" /etc/os-release; then
    echo -e "${RED}ERROR: This script is designed for Debian${NC}"
    echo "Your system: $(cat /etc/os-release | grep PRETTY_NAME)"
    exit 1
fi

DEBIAN_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
echo -e "${GREEN}✓ Detected: Debian ${DEBIAN_VERSION}${NC}"
echo ""

# Update package lists
echo -e "${BLUE}Updating package lists...${NC}"
sudo apt update

# Core build dependencies
echo ""
echo -e "${BLUE}Installing core build tools...${NC}"
sudo apt install -y \
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
    debhelper

# LLVM/Clang toolchain
echo ""
echo -e "${BLUE}Installing LLVM/Clang compiler toolchain...${NC}"

# Check if we need to add LLVM repository
CLANG_VERSION=$(apt-cache policy clang | grep Candidate | awk '{print $2}' | cut -d: -f1 | cut -d- -f1)
echo "Available Clang version in Debian repos: $CLANG_VERSION"

if [ -z "$CLANG_VERSION" ] || [ "${CLANG_VERSION%.*}" -lt "18" ]; then
    echo -e "${YELLOW}Debian's Clang version is too old. Installing from LLVM official repos...${NC}"

    # Add LLVM repository
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc
    echo "deb http://apt.llvm.org/trixie/ llvm-toolchain-trixie-20 main" | sudo tee /etc/apt/sources.list.d/llvm.list

    sudo apt update

    # Install specific LLVM 20 version
    sudo apt install -y \
        clang-20 \
        llvm-20 \
        lld-20 \
        llvm-20-dev \
        llvm-20-tools

    # Set up alternatives for version 20
    sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 100
    sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-20 100
    sudo update-alternatives --install /usr/bin/llvm-ar llvm-ar /usr/bin/llvm-ar-20 100
    sudo update-alternatives --install /usr/bin/llvm-nm llvm-nm /usr/bin/llvm-nm-20 100
    sudo update-alternatives --install /usr/bin/llvm-strip llvm-strip /usr/bin/llvm-strip-20 100
    sudo update-alternatives --install /usr/bin/llvm-objcopy llvm-objcopy /usr/bin/llvm-objcopy-20 100
    sudo update-alternatives --install /usr/bin/llvm-objdump llvm-objdump /usr/bin/llvm-objdump-20 100
    sudo update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-20 100

    echo -e "${GREEN}✓ Installed LLVM/Clang 20 from official repos${NC}"
else
    # Debian Trixie should have reasonably recent Clang
    sudo apt install -y \
        clang \
        llvm \
        lld \
        llvm-dev

    echo -e "${GREEN}✓ Installed LLVM/Clang from Debian repos${NC}"
fi

# DKMS for out-of-tree modules
echo ""
echo -e "${BLUE}Installing DKMS (for NVIDIA, VMware, etc.)...${NC}"
sudo apt install -y dkms

# Kernel packaging tools
echo ""
echo -e "${BLUE}Installing kernel build utilities...${NC}"
sudo apt install -y \
    kernel-package \
    linux-headers-$(uname -r) \
    fakeroot

# Optional: GitHub CLI (for patch downloads if needed)
echo ""
echo -e "${BLUE}Installing GitHub CLI (optional)...${NC}"
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
    echo -e "${GREEN}✓ GitHub CLI installed${NC}"
else
    echo -e "${GREEN}✓ GitHub CLI already installed${NC}"
fi

# Verify installation
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Verifying Build Environment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check critical tools
MISSING=0

check_tool() {
    TOOL=$1
    DISPLAY_NAME=$2
    if command -v "$TOOL" &> /dev/null; then
        VERSION=$($TOOL --version 2>&1 | head -n1)
        echo -e "${GREEN}✓ $DISPLAY_NAME:${NC} $VERSION"
    else
        echo -e "${RED}✗ $DISPLAY_NAME: NOT FOUND${NC}"
        MISSING=1
    fi
}

check_tool "clang" "Clang"
check_tool "llvm-ar" "LLVM AR"
check_tool "ld.lld" "LLD Linker"
check_tool "git" "Git"
check_tool "make" "Make"
check_tool "flex" "Flex"
check_tool "bison" "Bison"
check_tool "pahole" "Pahole (dwarves)"

# Check libraries
echo ""
echo -e "${BLUE}Checking libraries:${NC}"
if dpkg -l | grep -q libelf-dev; then
    echo -e "${GREEN}✓ libelf-dev${NC}"
else
    echo -e "${RED}✗ libelf-dev${NC}"
    MISSING=1
fi

if dpkg -l | grep -q libssl-dev; then
    echo -e "${GREEN}✓ libssl-dev${NC}"
else
    echo -e "${RED}✗ libssl-dev${NC}"
    MISSING=1
fi

# Final status
echo ""
if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Build environment ready!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "You can now build BobZKernel with:"
    echo -e "  ${BLUE}cd /home/bob/buildstuff/BobZKernel${NC}"
    echo -e "  ${BLUE}./scripts/update-and-build.sh 6.18${NC}"
    echo ""
    echo "Or see QUICK-START.md for more options."
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Some dependencies missing!${NC}"
    echo -e "${RED}========================================${NC}"
    echo "Please check the errors above and install missing packages."
    exit 1
fi
