#!/bin/bash
# Update kernel source from upstream
# Usage: ./update-kernel-source.sh

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.18"

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: Kernel directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

cd "$KERNEL_DIR"

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: Uncommitted changes detected in kernel source.${NC}"
    echo -e "${YELLOW}These are likely patches from a previous build.${NC}"
    
    if [ "${AUTO_YES}" != "true" ]; then
        read -p "Reset source tree to clean state? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cannot proceed with dirty tree. Please clean manually or answer 'y'."
            exit 1
        fi
    else
        echo -e "${BLUE}Auto-cleaning source tree...${NC}"
    fi
    
    # Reset to current HEAD first to clear staged/unstaged changes
    git reset --hard HEAD
    git clean -fd
    echo -e "${GREEN}✓ Source tree cleaned${NC}"
fi

echo -e "${BLUE}Fetching latest changes from upstream...${NC}"
git fetch upstream

BRANCH="linux-6.18.y"

# Check if we're already up to date
CURRENT_HASH=$(git rev-parse HEAD)
UPSTREAM_HASH=$(git rev-parse upstream/$BRANCH)

if [ "$CURRENT_HASH" = "$UPSTREAM_HASH" ]; then
    echo -e "${YELLOW}Already up to date with upstream/$BRANCH${NC}"
    echo -e "${BLUE}Current version: $(git log -1 --oneline)${NC}"
    echo ""

    # Check if --yes flag was passed from parent script
    if [ "${AUTO_YES}" != "true" ]; then
        read -p "No updates available. Continue with rebuild anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Build cancelled."
            exit 1
        fi
    else
        echo -e "${BLUE}Auto-confirmed: Continuing with current version${NC}"
    fi
else
    echo -e "${BLUE}Merging upstream/$BRANCH...${NC}"
    git merge upstream/$BRANCH --no-edit || {
        echo -e "${YELLOW}Merge conflict detected. Please resolve manually.${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Kernel source updated to latest upstream${NC}"
    git log -1 --oneline
fi
