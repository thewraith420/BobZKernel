#!/bin/bash
# Check build dependencies without requiring sudo

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}BobZKernel - Build Dependencies Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check critical tools
MISSING=0
MISSING_TOOLS=()

check_tool() {
    TOOL=$1
    DISPLAY_NAME=$2
    if command -v "$TOOL" &> /dev/null; then
        VERSION=$($TOOL --version 2>&1 | head -n1)
        echo -e "${GREEN}✓ $DISPLAY_NAME:${NC} $VERSION"
        return 0
    else
        echo -e "${RED}✗ $DISPLAY_NAME: NOT FOUND${NC}"
        MISSING_TOOLS+=("$DISPLAY_NAME")
        MISSING=1
        return 1
    fi
}

echo -e "${BLUE}Checking tools:${NC}"
check_tool "clang" "Clang"
check_tool "llvm-ar" "LLVM AR"
check_tool "ld.lld" "LLD Linker"
check_tool "git" "Git"
check_tool "make" "Make"
check_tool "flex" "Flex"
check_tool "bison" "Bison"
check_tool "pahole" "Pahole (dwarves)"
check_tool "bc" "BC"

# Check libraries
echo ""
echo -e "${BLUE}Checking libraries:${NC}"
if dpkg -l 2>/dev/null | grep -q libelf-dev; then
    echo -e "${GREEN}✓ libelf-dev${NC}"
else
    echo -e "${RED}✗ libelf-dev${NC}"
    MISSING_TOOLS+=("libelf-dev")
    MISSING=1
fi

if dpkg -l 2>/dev/null | grep -q libssl-dev; then
    echo -e "${GREEN}✓ libssl-dev${NC}"
else
    echo -e "${RED}✗ libssl-dev${NC}"
    MISSING_TOOLS+=("libssl-dev")
    MISSING=1
fi

if dpkg -l 2>/dev/null | grep -q libncurses-dev; then
    echo -e "${GREEN}✓ libncurses-dev${NC}"
else
    echo -e "${RED}✗ libncurses-dev${NC}"
    MISSING_TOOLS+=("libncurses-dev")
    MISSING=1
fi

# Check DKMS
echo ""
echo -e "${BLUE}Checking optional tools:${NC}"
if command -v dkms &> /dev/null; then
    echo -e "${GREEN}✓ DKMS (for NVIDIA, VMware modules)${NC}"
else
    echo -e "${YELLOW}! DKMS: NOT FOUND (needed for NVIDIA/VMware modules)${NC}"
fi

if command -v gh &> /dev/null; then
    echo -e "${GREEN}✓ GitHub CLI${NC}"
else
    echo -e "${YELLOW}! GitHub CLI: NOT FOUND (optional)${NC}"
fi

# Final status
echo ""
if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All required dependencies installed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "You can now build BobZKernel with:"
    echo -e "  ${BLUE}cd /home/bob/buildstuff/BobZKernel${NC}"
    echo -e "  ${BLUE}./scripts/update-and-build.sh 6.18${NC}"
    echo ""
    exit 0
else
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Missing dependencies detected${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Run this command to install missing packages:"
    echo ""
    echo -e "${BLUE}./scripts/setup-debian-build-env.sh${NC}"
    echo ""
    echo "Or install manually with sudo."
    exit 1
fi
