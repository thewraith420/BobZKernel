#!/bin/bash
# Complete workflow: Update kernel, apply patches, verify, build, install, and patch DKMS
# For Linux 7.0 with rseq timeslice extension and NVIDIA compatibility
# Usage: ./update-and-build-7.0.sh [--skip-update] [--skip-install] [--skip-nvidia] [--yes] [--resume]

set -e
set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="7.0"
SKIP_UPDATE=false
SKIP_INSTALL=false
SKIP_NVIDIA=false
AUTO_YES=false
RESUME_BUILD=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-update)
            SKIP_UPDATE=true
            ;;
        --skip-install)
            SKIP_INSTALL=true
            ;;
        --skip-nvidia)
            SKIP_NVIDIA=true
            ;;
        --yes|-y)
            AUTO_YES=true
            ;;
        --resume)
            RESUME_BUILD=true
            SKIP_UPDATE=true
            ;;
        *)
            echo -e "${RED}Unknown argument: $arg${NC}"
            echo "Usage: $0 [--skip-update] [--skip-install] [--skip-nvidia] [--yes] [--resume]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BobZKernel 7.0 Update & Build Workflow               ║${NC}"
echo -e "${BLUE}║   Features: RSEQ Timeslice, CachyOS, NVIDIA 595.58.03   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Kernel Version: $KERNEL_VERSION"
echo "Skip Update: $SKIP_UPDATE"
echo "Skip Install: $SKIP_INSTALL"
echo "Skip NVIDIA: $SKIP_NVIDIA"
echo "Resume Build: $RESUME_BUILD"
echo ""

if [ "$AUTO_YES" = false ]; then
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Step 1: Check for kernel updates
if [ "$SKIP_UPDATE" = false ]; then
    echo -e "${BLUE}═══ Step 1/9: Checking for Kernel Updates ═══${NC}"
    cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

    # Clean up any uncommitted changes from previous builds
    if [ "$RESUME_BUILD" = false ] && [ -n "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}Cleaning up uncommitted changes from previous build...${NC}"
        git reset --hard HEAD
        git clean -fd
    elif [ "$RESUME_BUILD" = true ]; then
        echo -e "${GREEN}Resume mode: Preserving build state${NC}"
    fi

    # Find the latest stable point release tag
    echo -e "${BLUE}Checking for latest v$KERNEL_VERSION.x release...${NC}"
    LATEST_TAG=$(timeout 30 git ls-remote --tags origin "refs/tags/v$KERNEL_VERSION.*" 2>/dev/null \
        | grep -v '\^{}\|rc' \
        | awk '{print $2}' | sed 's|refs/tags/||' \
        | sort -t. -k3 -n | tail -1)

    if [ -z "$LATEST_TAG" ]; then
        echo -e "${YELLOW}Could not reach origin, skipping update check${NC}"
    else
        CURRENT_TAG=$(git describe --tags --exact-match HEAD 2>/dev/null || echo "v$KERNEL_VERSION")
        echo -e "${BLUE}Current: $CURRENT_TAG${NC}"
        echo -e "${BLUE}Latest:  $LATEST_TAG${NC}"

        if [ "$CURRENT_TAG" = "$LATEST_TAG" ]; then
            echo -e "${GREEN}✓ Already on latest point release${NC}"
        else
            echo -e "${GREEN}Update available: $CURRENT_TAG → $LATEST_TAG${NC}"

            if [ "$AUTO_YES" = false ]; then
                read -p "Apply update? (y/N) " -n 1 -r
                echo
                [[ ! $REPLY =~ ^[Yy]$ ]] && LATEST_TAG=""
            fi

            if [ -n "$LATEST_TAG" ]; then
                echo -e "${BLUE}Fetching $LATEST_TAG...${NC}"
                git fetch --depth=1 origin tag "$LATEST_TAG" || {
                    echo -e "${RED}Fetch failed${NC}"; exit 1
                }
                git checkout "$LATEST_TAG"
                echo -e "${GREEN}✓ Updated to $LATEST_TAG${NC}"
            fi
        fi
    fi
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping kernel source update${NC}"
    echo ""
fi

# Step 2: Clean previous build artifacts and reset source (skip if resume)
if [ "$RESUME_BUILD" = false ]; then
    echo -e "${BLUE}═══ Step 2/9: Cleaning Build Directory ═══${NC}"
    cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

    # Reset source files to clean state (undo any previous patches)
    if [ -d ".git" ]; then
        echo -e "${YELLOW}Resetting source tree to clean state...${NC}"
        git checkout -- .
        git clean -fd
        echo -e "${GREEN}✓ Source tree reset to clean state${NC}"
    fi

    make mrproper
    echo -e "${GREEN}✓ Build directory cleaned${NC}"
    echo ""
else
    echo -e "${BLUE}═══ Step 2/9: Skipping Clean (Resume Mode) ═══${NC}"
    echo ""
fi

# Step 3: Apply CachyOS patches
if [ "$RESUME_BUILD" = true ]; then
    echo -e "${BLUE}═══ Step 3/9: Checking if Patches Already Applied ═══${NC}"
    cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"
    if grep -q "CONFIG_SCHED_BORE" kernel/sched/fair.c 2>/dev/null; then
        echo -e "${GREEN}✓ Patches already applied (detected BORE scheduler code)${NC}"
        SKIP_PATCHES=true
    else
        SKIP_PATCHES=false
    fi
    echo ""
else
    SKIP_PATCHES=false
fi

if [ "$SKIP_PATCHES" = false ]; then
    echo -e "${BLUE}═══ Step 3/9: Applying CachyOS Patches ═══${NC}"
    cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

    # Apply CachyOS patches from patches/cachyos-7.0/
    for patch in "$BASE_DIR/patches/cachyos-7.0/"*.patch; do
        if [ -f "$patch" ]; then
            PATCH_NAME=$(basename "$patch")
            if patch -p1 --dry-run --ignore-whitespace < "$patch" > /dev/null 2>&1; then
                patch -p1 --ignore-whitespace < "$patch"
                echo -e "${GREEN}✓ Applied: $PATCH_NAME${NC}"
            else
                echo -e "${YELLOW}⚠ Skipping (already applied or conflicts): $PATCH_NAME${NC}"
            fi
        fi
    done
    echo -e "${GREEN}✓ Patches applied${NC}"
    echo ""
fi

# Step 4: Copy and configure kernel config
echo -e "${BLUE}═══ Step 4/9: Configuring Kernel ═══${NC}"
cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch and select appropriate config
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")
if [ "$BRANCH" = "generic-build" ]; then
    CONFIG_SRC="$BASE_DIR/configs/config-7.0-generic"
    echo -e "${BLUE}Branch: generic-build - using generic (x86-64) config${NC}"
elif [ "$BRANCH" = "pixel-slate" ]; then
    CONFIG_SRC="$BASE_DIR/configs/config-7.0-pixel-slate"
    echo -e "${BLUE}Branch: pixel-slate - using Pixel Slate config${NC}"
else
    CONFIG_SRC="$BASE_DIR/configs/config-7.0-march-native"
    echo -e "${BLUE}Branch: $BRANCH - using march=native config${NC}"
fi

if [ -f "$CONFIG_SRC" ]; then
    cp "$CONFIG_SRC" .config
    echo -e "${BLUE}Config applied from $CONFIG_SRC${NC}"
else
    echo -e "${YELLOW}Config not found at $CONFIG_SRC, using existing .config${NC}"
fi

# Auto-detect LLVM version
if command -v clang-19 &> /dev/null; then
    LLVM_VERSION="-19"
elif command -v clang-20 &> /dev/null; then
    LLVM_VERSION="-20"
elif command -v clang-18 &> /dev/null; then
    LLVM_VERSION="-18"
else
    LLVM_VERSION=""
fi

echo -e "${BLUE}Using LLVM version: ${LLVM_VERSION:-system default}${NC}"

# Update config for new options
yes "" | make LLVM=${LLVM_VERSION} HOSTCC=gcc HOSTCXX=g++ olddefconfig 2>/dev/null || \
    make LLVM=${LLVM_VERSION} HOSTCC=gcc HOSTCXX=g++ olddefconfig

# Save updated config
cp .config "$BASE_DIR/configs/.config-$KERNEL_VERSION.$(date +%Y%m%d)"
echo -e "${GREEN}✓ Kernel configured${NC}"
echo ""

# Step 5: Build kernel
echo -e "${BLUE}═══ Step 5/9: Building Kernel ═══${NC}"
cd "$BASE_DIR"
./scripts/build-kernel-7.0.sh || {
    echo -e "${RED}Kernel build failed!${NC}"
    echo -e "${YELLOW}Check build-7.0-*.log for errors${NC}"
    exit 1
}
echo -e "${GREEN}✓ Kernel built successfully${NC}"
echo ""

# Step 6: Install or Package (optional)
if [ "$SKIP_INSTALL" = false ]; then
    echo -e "${BLUE}═══ Step 6/9: Kernel Deployment ═══${NC}"

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
                sudo ./scripts/install-kernel-7.0.sh || {
                    echo -e "${RED}Kernel installation failed!${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ Kernel installed on this system${NC}"
                INSTALL_TYPE="local"
                ;;
            2)
                echo -e "${BLUE}Creating portable installer package...${NC}"
                ./scripts/create-portable-installer.sh 7.0 || {
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
        sudo ./scripts/install-kernel-7.0.sh || {
            echo -e "${RED}Kernel installation failed!${NC}"
            exit 1
        }
        echo -e "${GREEN}✓ Kernel installed${NC}"
        INSTALL_TYPE="local"
    fi
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping kernel deployment${NC}"
    INSTALL_TYPE="skipped"
    echo ""
fi

# Step 7: Patch and build NVIDIA modules
if [ "$SKIP_NVIDIA" = false ]; then
    echo -e "${BLUE}═══ Step 7/9: Verifying NVIDIA DKMS Modules ═══${NC}"

    KERNELRELEASE=$(make -C "$BASE_DIR/builds/linux-$KERNEL_VERSION" -s kernelrelease 2>/dev/null)
    # dkms is in /usr/sbin (root path) and the pipeline can SIGPIPE under
    # `set -o pipefail`. Use sudo and `|| true` to keep the script alive.
    NVIDIA_VERSION=$(sudo dkms status nvidia 2>/dev/null | awk -F'[,/]' 'NR==1{gsub(/ /,"",$2); print $2}' || true)

    if [ -z "$NVIDIA_VERSION" ]; then
        echo -e "${YELLOW}No NVIDIA DKMS module found, skipping${NC}"
    else
        echo -e "${BLUE}Checking NVIDIA $NVIDIA_VERSION for $KERNELRELEASE...${NC}"
        STATUS=$(sudo dkms status "nvidia/$NVIDIA_VERSION" -k "$KERNELRELEASE" 2>/dev/null || true)

        if echo "$STATUS" | grep -q "installed"; then
            echo -e "${GREEN}✓ NVIDIA $NVIDIA_VERSION already built for $KERNELRELEASE${NC}"
        else
            echo -e "${BLUE}Building NVIDIA $NVIDIA_VERSION for $KERNELRELEASE...${NC}"
            sudo dkms install "nvidia/$NVIDIA_VERSION" -k "$KERNELRELEASE" || {
                echo -e "${RED}NVIDIA DKMS build failed!${NC}"
                echo -e "${YELLOW}Check /var/lib/dkms/nvidia/$NVIDIA_VERSION/build/make.log${NC}"
                exit 1
            }
            echo -e "${GREEN}✓ NVIDIA $NVIDIA_VERSION built for $KERNELRELEASE${NC}"
        fi
    fi
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping NVIDIA module check${NC}"
    echo ""
fi

# Step 8: LenovoLegionLinux DKMS module (from thewraith420 fork)
echo -e "${BLUE}═══ Step 8/9: Updating LenovoLegionLinux DKMS Module ═══${NC}"

LEGION_FORK="https://github.com/thewraith420/LenovoLegionLinux.git"
LEGION_VERSION="1.0.0"
LEGION_SRC="/usr/src/LenovoLegionLinux-$LEGION_VERSION"
LEGION_TMP="/tmp/legion-fork-$$"
KERNELRELEASE=$(make -C "$BASE_DIR/builds/linux-$KERNEL_VERSION" -s kernelrelease 2>/dev/null)

echo -e "${BLUE}Fetching latest from fork...${NC}"
rm -rf "$LEGION_TMP"
if ! timeout 60 git clone --depth 1 "$LEGION_FORK" "$LEGION_TMP" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Could not reach fork, skipping legion update${NC}"
else
    NEW_HASH=$(git -C "$LEGION_TMP" rev-parse --short HEAD)
    OLD_HASH=$(cat "$LEGION_SRC/.fork_hash" 2>/dev/null || echo "none")

    if [ "$NEW_HASH" = "$OLD_HASH" ]; then
        echo -e "${GREEN}✓ Already at $NEW_HASH${NC}"
        rm -rf "$LEGION_TMP"
    else
        echo -e "${BLUE}Updating $OLD_HASH → $NEW_HASH${NC}"
        # Remove from DKMS first so source replacement is clean
        sudo dkms remove "LenovoLegionLinux/$LEGION_VERSION" --all >/dev/null 2>&1 || true
        sudo rm -rf "$LEGION_SRC"
        sudo cp -r "$LEGION_TMP/kernel_module" "$LEGION_SRC"
        sudo sed -i "s/PACKAGE_VERSION=\"DKMS_VERSION\"/PACKAGE_VERSION=\"$LEGION_VERSION\"/" "$LEGION_SRC/dkms.conf"
        echo "$NEW_HASH" | sudo tee "$LEGION_SRC/.fork_hash" >/dev/null
        rm -rf "$LEGION_TMP"

        sudo dkms add "LenovoLegionLinux/$LEGION_VERSION" >/dev/null 2>&1 || true
    fi

    # Ensure built for the current kernel
    if sudo dkms status "LenovoLegionLinux/$LEGION_VERSION" -k "$KERNELRELEASE" 2>/dev/null | grep -q installed; then
        echo -e "${GREEN}✓ LenovoLegionLinux already built for $KERNELRELEASE${NC}"
    else
        echo -e "${BLUE}Building LenovoLegionLinux for $KERNELRELEASE...${NC}"
        sudo dkms install "LenovoLegionLinux/$LEGION_VERSION" -k "$KERNELRELEASE" --force || {
            echo -e "${RED}LenovoLegionLinux DKMS build failed!${NC}"
            echo -e "${YELLOW}Check /var/lib/dkms/LenovoLegionLinux/$LEGION_VERSION/build/make.log${NC}"
            exit 1
        }
        echo -e "${GREEN}✓ LenovoLegionLinux built for $KERNELRELEASE${NC}"
    fi
fi
echo ""

# Step 9: Summary
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Build Complete!                            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

KERNELRELEASE=$(make -C "$BASE_DIR/builds/linux-$KERNEL_VERSION" -s kernelrelease 2>/dev/null)

echo -e "${BLUE}Kernel built: $KERNELRELEASE${NC}"
echo ""
echo -e "${BLUE}Features included:${NC}"
echo "  • CachyOS scheduler patches (BORE)"
echo "  • RSEQ Timeslice Extension with statistics"
echo "  • Cluster-aware CPU grouping (optimized NVMe IRQ affinity)"
echo "  • march=native optimizations"
echo "  • LLVM/Clang compilation"
if [ "$SKIP_NVIDIA" = false ]; then
    echo "  • NVIDIA 595.58.03 compatibility patches"
fi
echo ""

# Show appropriate next steps based on deployment choice
case "${INSTALL_TYPE:-skipped}" in
    local)
        echo -e "${BLUE}Next steps:${NC}"
        echo "1. Reboot your system"
        echo "2. Select '$KERNELRELEASE' from GRUB menu"
        echo "3. Verify with: uname -r"
        echo "4. Check RSEQ stats: sudo cat /sys/kernel/debug/rseq/stats"
        ;;
    portable)
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
        echo "  Local install:      sudo ./scripts/install-kernel-7.0.sh"
        echo "  Portable installer: ./scripts/create-portable-installer.sh 7.0"
        ;;
esac

echo ""
echo -e "${BLUE}Kernel build artifacts:${NC}"
echo "  Image: builds/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
echo "  Log: build-7.0-*.log (timestamped)"
echo ""
