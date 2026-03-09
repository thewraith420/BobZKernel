#!/bin/bash
# BobZKernel Installation Script
# Installs the custom kernel and updates bootloader
# Usage: sudo ./install-kernel.sh

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Kernel version (6.19)
KERNEL_DIR="/home/bob/buildstuff/BobZKernel/builds/linux-6.19"
KERNEL_MAJOR="6.19"

LOCALVERSION="-BobZKernel"

echo -e "${BLUE}=== BobZKernel Installation Script ===${NC}"
echo "Installing Linux kernel $KERNEL_MAJOR$LOCALVERSION"
echo ""

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    exit 1
fi

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: Kernel directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

cd "$KERNEL_DIR"

# Check if kernel was built
if [ ! -f "arch/x86/boot/bzImage" ]; then
    echo -e "${RED}Error: Kernel image not found. Run build script first.${NC}"
    exit 1
fi

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

echo -e "${BLUE}Step 1: Patching DKMS sources for compatibility...${NC}"
# Patch DKMS sources BEFORE installation to fix known API incompatibilities
bash /home/bob/buildstuff/BobZKernel/scripts/patch-dkms-sources.sh

echo -e "${BLUE}Step 2: Installing kernel (disabling DKMS autoinstall hook)...${NC}"
# Temporarily disable DKMS autoinstall to avoid building before patching
if [ -f /etc/kernel/postinst.d/dkms ]; then
    mv /etc/kernel/postinst.d/dkms /etc/kernel/postinst.d/dkms.disabled
    DKMS_HOOK_DISABLED=true
fi

make LLVM=${LLVM_VERSION} install

# Re-enable DKMS hook
if [ "$DKMS_HOOK_DISABLED" = true ]; then
    mv /etc/kernel/postinst.d/dkms.disabled /etc/kernel/postinst.d/dkms
fi

echo -e "${BLUE}Step 3: Installing modules...${NC}"
make LLVM=${LLVM_VERSION} modules_install

KERNEL_VERSION=$(cat include/config/kernel.release)

echo -e "${BLUE}Step 4: Compressing modules with zstd...${NC}"
find /lib/modules/$KERNEL_VERSION -name '*.ko' -exec zstd --rm -q -T0 {} \;
depmod -a $KERNEL_VERSION

echo -e "${BLUE}Step 5: Building DKMS modules for new kernel...${NC}"
echo "Building DKMS modules for kernel: $KERNEL_VERSION"
echo "Forcing DKMS to use Clang to match kernel compiler..."

# Export Clang compiler variables to force DKMS to use Clang
export CC=clang
export CXX=clang++
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
export HOSTCC=clang
export HOSTCXX=clang++
export HOSTAR=llvm-ar
export HOSTLD=ld.lld
export LLVM=${LLVM_VERSION}
export LLVM_IAS=1

# Get list of all installed DKMS modules (query DKMS directly for accurate names)
echo "Detecting installed DKMS modules..."
DKMS_MODULES=""
# Get unique module/version pairs from dkms status output
while IFS= read -r line; do
    if [ -n "$line" ]; then
        # Extract module/version from "module/version, kernel, arch: status" format
        module_version=$(echo "$line" | cut -d',' -f1)
        # Verify source directory exists
        module_name=$(echo "$module_version" | cut -d'/' -f1)
        version=$(echo "$module_version" | cut -d'/' -f2)

        # Check if source exists in /usr/src
        if ls /usr/src/${module_name}-${version} >/dev/null 2>&1 || \
           ls /usr/src/${module_name}*${version}* >/dev/null 2>&1; then
            # Add if not already in list
            if ! echo "$DKMS_MODULES" | grep -q "$module_version"; then
                DKMS_MODULES="$DKMS_MODULES $module_version"
                echo -e "${GREEN}  Found: $module_version${NC}"
            fi
        fi
    fi
done < <(dkms status 2>/dev/null | grep -v "^Error" | grep -v "^File:")

if [ -z "$DKMS_MODULES" ]; then
    echo -e "${YELLOW}No DKMS modules found to build${NC}"
else
    # Rebuild each DKMS module for the new kernel with correct source
    echo ""
    echo "Rebuilding DKMS modules with Clang and correct kernel source..."
    for module in $DKMS_MODULES; do
        module_name=$(echo "$module" | cut -d'/' -f1)
        module_version=$(echo "$module" | cut -d'/' -f2)

        echo -e "${YELLOW}  Building $module_name/$module_version for kernel $KERNEL_VERSION...${NC}"

        # Remove old build for this kernel if it exists
        dkms remove "$module_name/$module_version" -k "$KERNEL_VERSION" 2>/dev/null || true

        # Build and install with explicit kernel source directory
        if dkms install "$module_name/$module_version" -k "$KERNEL_VERSION" \
            --kernelsourcedir="$KERNEL_DIR" --verbose 2>&1 | grep -v "^$"; then
            echo -e "${GREEN}    ✓ Success: $module_name/$module_version${NC}"
        else
            echo -e "${RED}    ✗ Failed: $module_name/$module_version${NC}"
            echo -e "${YELLOW}    You may need to rebuild this manually after boot${NC}"
        fi
    done

    echo -e "${GREEN}DKMS module build complete${NC}"
fi

echo -e "${BLUE}Step 6: Regenerating initramfs...${NC}"
update-initramfs -c -k $KERNEL_VERSION

echo -e "${BLUE}Step 7: Building VMware modules (if installed)...${NC}"
bash /home/bob/buildstuff/BobZKernel/scripts/build-vmware-modules.sh "$KERNEL_VERSION" || {
    echo -e "${YELLOW}Note: VMware modules not built (VMware may not be installed)${NC}"
}

echo -e "${BLUE}Step 8: Updating GRUB bootloader...${NC}"
update-grub

echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Before rebooting, ensure you have a way to boot${NC}"
echo -e "${YELLOW}your current kernel if the new one doesn't work.${NC}"
echo ""
echo -e "${BLUE}To boot the new kernel:${NC}"
echo "  1. Reboot your system"
echo "  2. At GRUB menu, select 'Linux $KERNEL_MAJOR.*$LOCALVERSION'"
echo "  3. If it boots successfully, you're good!"
echo "  4. If it fails, select your old kernel to boot back"