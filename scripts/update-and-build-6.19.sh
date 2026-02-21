#!/bin/bash
# Complete workflow: Update kernel, apply patches, verify, build, install, and patch DKMS
# For Linux 6.19 with rseq timeslice extension and NVIDIA compatibility
# Usage: ./update-and-build-6.19.sh [--skip-update] [--skip-install] [--skip-nvidia] [--yes] [--resume]

set -e
set -o pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.19"
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
echo -e "${BLUE}║   BobZKernel 6.19 Update & Build Workflow               ║${NC}"
echo -e "${BLUE}║   Features: RSEQ Timeslice, CachyOS, NVIDIA 590.48.01   ║${NC}"
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
    echo -e "${BLUE}═══ Step 1/8: Checking for Kernel Updates ═══${NC}"
    cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

    # Clean up any uncommitted changes from previous builds
    if [ "$RESUME_BUILD" = false ] && [ -n "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}Cleaning up uncommitted changes from previous build...${NC}"
        git reset --hard HEAD
        git clean -fd
    elif [ "$RESUME_BUILD" = true ]; then
        echo -e "${GREEN}Resume mode: Preserving build state${NC}"
    fi

    # Check if updates are available
    echo -e "${BLUE}Fetching latest changes from origin...${NC}"
    git fetch origin > /dev/null 2>&1 || {
        echo -e "${YELLOW}No origin configured, skipping update check${NC}"
    }

    if git rev-parse origin/linux-$KERNEL_VERSION.y >/dev/null 2>&1; then
        CURRENT_HASH=$(git rev-parse HEAD)
        ORIGIN_HASH=$(git rev-parse origin/linux-$KERNEL_VERSION.y)

        if [ "$CURRENT_HASH" = "$ORIGIN_HASH" ]; then
            echo -e "${YELLOW}⊘ No updates available${NC}"
            echo -e "${BLUE}Current version: $(git log -1 --oneline)${NC}"
        else
            echo -e "${BLUE}Updates available from origin${NC}"
            echo -e "${YELLOW}Current:  $(git log -1 --oneline)${NC}"
            echo -e "${GREEN}Latest:   $(git log -1 origin/linux-$KERNEL_VERSION.y --oneline)${NC}"

            if [ "$AUTO_YES" = false ]; then
                read -p "Apply kernel updates? (y/N) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    git merge origin/linux-$KERNEL_VERSION.y --no-edit || {
                        echo -e "${RED}Merge conflict detected. Please resolve manually.${NC}"
                        exit 1
                    }
                    echo -e "${GREEN}✓ Kernel source updated${NC}"
                fi
            else
                git merge origin/linux-$KERNEL_VERSION.y --no-edit || {
                    echo -e "${RED}Merge conflict detected. Please resolve manually.${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ Kernel source updated${NC}"
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
    echo -e "${BLUE}═══ Step 2/8: Cleaning Build Directory ═══${NC}"
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
    echo -e "${BLUE}═══ Step 2/8: Skipping Clean (Resume Mode) ═══${NC}"
    echo ""
fi

# Step 3: Apply CachyOS patches
if [ "$RESUME_BUILD" = true ]; then
    echo -e "${BLUE}═══ Step 3/8: Checking if Patches Already Applied ═══${NC}"
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
    echo -e "${BLUE}═══ Step 3/8: Applying CachyOS Patches ═══${NC}"
    cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

    # Apply CachyOS patches from patches/cachyos-6.19/
    for patch in "$BASE_DIR/patches/cachyos-6.19/"*.patch; do
        if [ -f "$patch" ]; then
            PATCH_NAME=$(basename "$patch")
            if patch -p1 --dry-run < "$patch" > /dev/null 2>&1; then
                patch -p1 < "$patch"
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
echo -e "${BLUE}═══ Step 4/8: Configuring Kernel ═══${NC}"
cd "$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch and select appropriate config
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")
if [ "$BRANCH" = "generic-build" ]; then
    CONFIG_SRC="$BASE_DIR/configs/config-6.19-generic"
    echo -e "${BLUE}Branch: generic-build - using generic (x86-64) config${NC}"
elif [ "$BRANCH" = "pixel-slate" ]; then
    CONFIG_SRC="$BASE_DIR/configs/config-6.19-pixel-slate"
    echo -e "${BLUE}Branch: pixel-slate - using Pixel Slate config${NC}"
else
    CONFIG_SRC="$BASE_DIR/configs/config-6.19-march-native"
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
echo -e "${BLUE}═══ Step 5/8: Building Kernel ═══${NC}"
cd "$BASE_DIR"
./scripts/build-kernel-6.19.sh || {
    echo -e "${RED}Kernel build failed!${NC}"
    echo -e "${YELLOW}Check build-6.19-*.log for errors${NC}"
    exit 1
}
echo -e "${GREEN}✓ Kernel built successfully${NC}"
echo ""

# Step 6: Install or Package (optional)
if [ "$SKIP_INSTALL" = false ]; then
    echo -e "${BLUE}═══ Step 6/8: Kernel Deployment ═══${NC}"

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
                sudo ./scripts/install-kernel-6.19.sh || {
                    echo -e "${RED}Kernel installation failed!${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ Kernel installed on this system${NC}"
                INSTALL_TYPE="local"
                ;;
            2)
                echo -e "${BLUE}Creating portable installer package...${NC}"
                ./scripts/create-portable-installer.sh 6.19 || {
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
        sudo ./scripts/install-kernel-6.19.sh || {
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
    echo -e "${BLUE}═══ Step 7/8: Patching NVIDIA 590.48.01 for 6.19 ═══${NC}"

    NVIDIA_PATCH="$BASE_DIR/patches/nvidia-590.48.01-linux-6.19.patch"
    NVIDIA_SRC="/usr/src/nvidia-590.48.01"

    if [ ! -f "$NVIDIA_PATCH" ]; then
        echo -e "${RED}NVIDIA patch not found: $NVIDIA_PATCH${NC}"
        echo -e "${YELLOW}Skipping NVIDIA patching${NC}"
    elif [ ! -d "$NVIDIA_SRC" ]; then
        echo -e "${YELLOW}NVIDIA 590.48.01 source not found, skipping${NC}"
    else
        # Check if patches are already applied
        if grep -q "folio_free" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c" 2>/dev/null; then
            echo -e "${GREEN}✓ NVIDIA patches already applied${NC}"
        else
            echo -e "${BLUE}Applying NVIDIA 6.19 compatibility patch...${NC}"

            # Apply zone_device_page_init fix
            sudo sed -i 's/zone_device_page_init(dpage);/zone_device_page_init(dpage, page_pgmap(dpage), 0);/' \
                "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_hmm.c"

            # Apply folio_free fixes using the method that worked
            # Insert devmem_folio_free wrapper
            LINE=$(grep -n "static const struct dev_pagemap_ops uvm_pmm_devmem_ops" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c" | cut -d: -f1)
            sudo sed -i "${LINE}i\\
static void devmem_folio_free(struct folio *folio) {\\
    devmem_page_free(folio_page(folio, 0));\\
}\\
" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c"
            sudo sed -i 's/\.page_free = devmem_page_free,/.folio_free = devmem_folio_free,/' "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c"

            # Insert device_coherent_folio_free wrapper
            LINE=$(grep -n "static const struct dev_pagemap_ops uvm_device_coherent_pgmap_ops" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c" | cut -d: -f1)
            sudo sed -i "${LINE}i\\
static void device_coherent_folio_free(struct folio *folio) {\\
    device_coherent_page_free(folio_page(folio, 0));\\
}\\
" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c"
            sudo sed -i 's/\.page_free = device_coherent_page_free,/.folio_free = device_coherent_folio_free,/' "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c"

            # Insert device_p2p_folio_free wrapper
            LINE=$(grep -n "static const struct dev_pagemap_ops uvm_device_p2p_pgmap_ops" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c" | cut -d: -f1)
            sudo sed -i "${LINE}i\\
static void device_p2p_folio_free(struct folio *folio) {\\
    device_p2p_page_free(folio_page(folio, 0));\\
}\\
" "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c"
            sudo sed -i 's/\.page_free = device_p2p_page_free,/.folio_free = device_p2p_folio_free,/' "$NVIDIA_SRC/kernel-open/nvidia-uvm/uvm_pmm_gpu.c"

            echo -e "${GREEN}✓ NVIDIA patches applied${NC}"
        fi

        # Build NVIDIA modules for the new kernel
        KERNELRELEASE=$(make -C "$BASE_DIR/builds/linux-$KERNEL_VERSION" -s kernelrelease 2>/dev/null)
        echo -e "${BLUE}Building NVIDIA modules for $KERNELRELEASE...${NC}"

        sudo /usr/sbin/dkms install nvidia/590.48.01 -k "$KERNELRELEASE" || {
            echo -e "${RED}NVIDIA DKMS build failed!${NC}"
            echo -e "${YELLOW}Check /var/lib/dkms/nvidia/590.48.01/build/make.log for errors${NC}"
            exit 1
        }
        echo -e "${GREEN}✓ NVIDIA modules built and installed${NC}"
    fi
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping NVIDIA module patching${NC}"
    echo ""
fi

# Step 8: Summary
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
    echo "  • NVIDIA 590.48.01 compatibility patches"
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
        echo "  Local install:      sudo ./scripts/install-kernel-6.19.sh"
        echo "  Portable installer: ./scripts/create-portable-installer.sh 6.19"
        ;;
esac

echo ""
echo -e "${BLUE}Kernel build artifacts:${NC}"
echo "  Image: builds/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
echo "  Log: build-6.19-*.log (timestamped)"
echo ""
