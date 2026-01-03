#!/bin/bash
# Update kernel source from upstream stable releases
# Usage: ./update-kernel-source.sh [6.14|6.18] [version]
# Examples: 
#   ./update-kernel-source.sh 6.18         (updates 6.18 to latest)
#   ./update-kernel-source.sh 6.14         (updates 6.14 to latest)
#   ./update-kernel-source.sh 6.18 6.18.1  (updates to specific version)

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="/home/bob/buildstuff/BobzKernel/builds"
UPSTREAM_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"

# Determine which kernel to update
if [ "$1" == "6.14" ]; then
    KERNEL_DIR="$BASE_DIR/linux-6.14-cachyos"
    BRANCH="linux-6.14.y"
    MAJOR_VERSION="6.14"
    CONFIG_FILE="configs/.config-6.14"
elif [ "$1" == "6.18" ]; then
    KERNEL_DIR="$BASE_DIR/linux"
    BRANCH="linux-6.18.y"
    MAJOR_VERSION="6.18"
    CONFIG_FILE="configs/.config-6.18"
else
    echo -e "${RED}Error: Please specify kernel version (6.14 or 6.18)${NC}"
    echo "Usage: $0 [6.14|6.18] [specific_version]"
    exit 1
fi

SPECIFIC_VERSION="$2"

cd "$KERNEL_DIR"

echo -e "${BLUE}=== Kernel $MAJOR_VERSION Update Script ===${NC}"

# Add upstream if not present
if ! git remote get-url upstream &>/dev/null 2>&1; then
    echo -e "${BLUE}Adding upstream stable remote...${NC}"
    git remote add upstream "$UPSTREAM_URL"
fi

echo -e "${BLUE}Fetching latest stable updates from $BRANCH...${NC}"
git fetch upstream "$BRANCH"

# Save current state
CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_VERSION=$(make kernelversion)
echo -e "${BLUE}Current version: $CURRENT_VERSION (commit: ${CURRENT_COMMIT:0:7})${NC}"

if [ -n "$SPECIFIC_VERSION" ]; then
    # Update to specific version tag
    TAG="v$SPECIFIC_VERSION"
    echo -e "${BLUE}Updating to kernel $TAG...${NC}"
    git checkout "$TAG" 2>/dev/null || {
        echo -e "${RED}Error: Version $TAG not found${NC}"
        exit 1
    }
else
    # Update to latest stable
    echo -e "${BLUE}Updating to latest $MAJOR_VERSION.x stable...${NC}"
    git merge --ff-only upstream/"$BRANCH" || {
        echo -e "${YELLOW}Fast-forward failed. You may have local changes.${NC}"
        echo "Current branch: $(git branch --show-current)"
        echo "Run 'git status' to see changes"
        exit 1
    }
fi

NEW_VERSION=$(make kernelversion)
echo -e "${GREEN}Updated to version: $NEW_VERSION${NC}"

# Show changes
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo -e "${BLUE}Changes since last update:${NC}"
    git log --oneline "${CURRENT_COMMIT}..HEAD" | head -20
    echo ""
fi

echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review config changes: cd $KERNEL_DIR && make LLVM=1 listnewconfig"
echo "2. Update config: make LLVM=1 olddefconfig"
echo "3. Build kernel: cd $BASE_DIR/.. && ./scripts/build-kernel.sh"
echo "4. Install: sudo ./scripts/install-kernel.sh"
echo ""
echo -e "${YELLOW}To sync your fork:${NC}"
echo "cd $KERNEL_DIR"
echo "git push fork HEAD:$MAJOR_VERSION-stable --force"
