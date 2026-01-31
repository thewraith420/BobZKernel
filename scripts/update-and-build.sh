#!/bin/bash
# Complete workflow: Update kernel, apply patches, verify, build, and install
# Usage: ./update-and-build.sh [--skip-update] [--skip-install] [--yes]

set -e
set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.18"
SKIP_UPDATE=false
SKIP_INSTALL=false
AUTO_YES=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-update)
            SKIP_UPDATE=true
            ;;
        --skip-install)
            SKIP_INSTALL=true
            ;;
        --yes|-y)
            AUTO_YES=true
            ;;
        *)
            echo -e "${RED}Unknown argument: $arg${NC}"
            echo "Usage: $0 [--skip-update] [--skip-install] [--yes]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BobZKernel Complete Update & Build Workflow          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Kernel Version: $KERNEL_VERSION"
echo "Skip Update: $SKIP_UPDATE"
echo "Skip Install: $SKIP_INSTALL"
echo ""

if [ "$AUTO_YES" = false ]; then
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Step 1: Update kernel source (optional)
if [ "$SKIP_UPDATE" = false ]; then
    echo -e "${BLUE}═══ Step 1/7: Updating Kernel Source ═══${NC}"
    cd "$BASE_DIR"
    AUTO_YES=$AUTO_YES ./scripts/update-kernel-source.sh "$KERNEL_VERSION" || {
        echo -e "${RED}Kernel update failed!${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ Kernel source updated${NC}"
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping kernel source update${NC}"
    echo ""
fi

# Step 2: Clean previous build artifacts
echo -e "${BLUE}═══ Step 2/7: Cleaning Build Directory ═══${NC}"
cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"
make mrproper
echo -e "${GREEN}✓ Build directory cleaned${NC}"
echo ""

# Step 3: Apply patches
echo -e "${BLUE}═══ Step 3/7: Applying CachyOS Patches ═══${NC}"
cd "$BASE_DIR"
./scripts/apply-patches.sh "$KERNEL_VERSION" --force || {
    echo -e "${RED}Patch application failed!${NC}"
    exit 1
}
echo -e "${GREEN}✓ Patches applied${NC}"
echo ""

# Step 4: Verify patches
echo -e "${BLUE}═══ Step 4/7: Verifying Patches ═══${NC}"
./scripts/verify-patches.sh "$KERNEL_VERSION" || {
    echo -e "${RED}Patch verification failed!${NC}"
    echo -e "${YELLOW}Fix the issues reported above before continuing${NC}"
    exit 1
}
echo -e "${GREEN}✓ Patches verified${NC}"
echo ""

# Step 4.5: Apply cluster-aware NVMe IRQ optimization backport
echo -e "${BLUE}═══ Applying NVMe Cluster-Aware IRQ Optimization ═══${NC}"
./scripts/apply-cluster-aware-backport.sh || {
    echo -e "${YELLOW}⚠ Cluster-aware backport failed - continuing without it${NC}"
}
echo ""

# Step 4.6: Apply Revocable Resource Management patch
echo -e "${BLUE}═══ Applying Revocable Resource Management ═══${NC}"
cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"
if patch -p1 --dry-run < "$BASE_DIR/patches/0001-revocable-resource-management.patch" > /dev/null 2>&1; then
    patch -p1 < "$BASE_DIR/patches/0001-revocable-resource-management.patch"
    echo -e "${GREEN}✓ Revocable Resource Management applied${NC}"
else
    echo -e "${YELLOW}⚠ Revocable patch already applied or conflicts detected - skipping${NC}"
fi
echo ""

# Step 5: Apply config and build
echo -e "${BLUE}═══ Step 5/7: Building Kernel ═══${NC}"
cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch and select appropriate config
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")
if [ "$BRANCH" = "generic-build" ]; then
    CONFIG_SRC="$BASE_DIR/configs/config-6.18.3-generic"
    echo -e "${BLUE}Branch: generic-build - using generic (x86-64) config${NC}"
elif [ "$BRANCH" = "pixel-slate" ]; then
    CONFIG_SRC="$BASE_DIR/configs/config-6.18.6-pixel-slate"
    echo -e "${BLUE}Branch: pixel-slate - using Pixel Slate (camera + audio optimized) config${NC}"
else
    CONFIG_SRC="$BASE_DIR/configs/config-6.18.3-march-native"
    echo -e "${BLUE}Branch: $BRANCH - using march=native config${NC}"
fi

# Copy config
cp "$CONFIG_SRC" .config
echo -e "${BLUE}Config applied from $CONFIG_SRC${NC}"

# Update config for new options
yes "" | make LLVM=-20 olddefconfig 2>/dev/null || make LLVM=-20 olddefconfig

# Save updated config back
cp .config "$BASE_DIR/configs/.config-$KERNEL_VERSION.$(date +%Y%m%d)"
echo -e "${BLUE}Config backed up to configs/.config-$KERNEL_VERSION.$(date +%Y%m%d)${NC}"

# Build
cd "$BASE_DIR"
./scripts/build-kernel.sh "$KERNEL_VERSION" || {
    echo -e "${RED}Kernel build failed!${NC}"
    echo -e "${YELLOW}Check build.log for errors${NC}"
    exit 1
}
echo -e "${GREEN}✓ Kernel built successfully${NC}"
echo ""

# Step 6: Install or Package (optional)
if [ "$SKIP_INSTALL" = false ]; then
    echo -e "${BLUE}═══ Step 6/7: Kernel Deployment ═══${NC}"

    if [ "$AUTO_YES" = false ]; then
        echo -e "${YELLOW}Choose deployment option:${NC}"
        echo "  1) Install kernel on this system"
        echo "  2) Create portable installer package"
        echo "  3) Skip (do nothing)"
        echo ""
        read -p "Select option [1-3]: " -n 1 -r
        echo

        case $REPLY in
            1)
                echo -e "${BLUE}Installing kernel on this system...${NC}"
                sudo ./scripts/install-kernel.sh "$KERNEL_VERSION" || {
                    echo -e "${RED}Kernel installation failed!${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ Kernel installed on this system${NC}"
                INSTALL_TYPE="local"
                ;;
            2)
                echo -e "${BLUE}Creating portable installer package...${NC}"
                ./scripts/create-portable-installer.sh || {
                    echo -e "${RED}Portable installer creation failed!${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ Portable installer created${NC}"
                INSTALL_TYPE="portable"
                ;;
            3|*)
                echo -e "${YELLOW}Skipping deployment${NC}"
                SKIP_INSTALL=true
                INSTALL_TYPE="skipped"
                ;;
        esac
    else
        # AUTO_YES is true, install locally by default
        sudo ./scripts/install-kernel.sh "$KERNEL_VERSION" || {
            echo -e "${RED}Kernel installation failed!${NC}"
            exit 1
        }
        echo -e "${GREEN}✓ Kernel installed${NC}"
        INSTALL_TYPE="local"
    fi
else
    echo -e "${YELLOW}⊘ Skipping kernel deployment${NC}"
    INSTALL_TYPE="skipped"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Workflow Complete!                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show appropriate next steps based on deployment choice
case "${INSTALL_TYPE:-skipped}" in
    local)
        echo -e "${BLUE}Next steps:${NC}"
        echo "1. Reboot your system"
        echo "2. Select '6.$KERNEL_VERSION.*-BobZKernel' from GRUB menu"
        echo "3. Verify with: uname -r"
        ;;
    portable)
        KERNELRELEASE=$(make -C builds/linux-$KERNEL_VERSION -s kernelrelease 2>/dev/null)
        PACKAGE_NAME="BobZKernel-${KERNELRELEASE}-installer.tar.gz"
        echo -e "${BLUE}Portable installer created:${NC}"
        echo "  Package: $PACKAGE_NAME"
        echo ""
        echo -e "${BLUE}To deploy on target system:${NC}"
        echo "1. Copy $PACKAGE_NAME to target system"
        echo "2. Extract: tar -xzf $PACKAGE_NAME"
        echo "3. Install: cd installer-* && sudo ./install.sh"
        ;;
    skipped)
        echo -e "${BLUE}Deployment options:${NC}"
        echo "  Local install:      sudo ./scripts/install-kernel.sh $KERNEL_VERSION"
        echo "  Portable installer: ./scripts/create-portable-installer.sh"
        ;;
esac

echo ""
echo -e "${BLUE}Kernel build artifacts:${NC}"
echo "  Image: builds/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
echo "  Modules: lib/modules/\$(make -C builds/linux-$KERNEL_VERSION kernelrelease)"
echo "  Log: build-$KERNEL_VERSION-*.log (timestamped)"
