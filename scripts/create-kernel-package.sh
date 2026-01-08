#!/bin/bash
# Package kernel in standard distribution format
# Creates a tar.gz package like most aftermarket kernel distributions

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

# Get kernel release
KERNELRELEASE=$(make -s kernelrelease 2>/dev/null)
if [ -z "$KERNELRELEASE" ]; then
    echo -e "${RED}Error: Could not determine kernel release${NC}"
    exit 1
fi

BUILD_TYPE="march-native"
PACKAGE_NAME="BobZKernel-${KERNELRELEASE}-${BUILD_TYPE}.tar.gz"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Creating Standard Kernel Package              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Kernel: $KERNELRELEASE${NC}"
echo -e "${GREEN}Build Type: $BUILD_TYPE${NC}"
echo

# Create temporary packaging directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

PKG_DIR="$TEMP_DIR/BobZKernel-${KERNELRELEASE}"
mkdir -p "$PKG_DIR"/{boot,lib/modules}

echo -e "${BLUE}Copying kernel image...${NC}"
cp arch/x86/boot/bzImage "$PKG_DIR/boot/vmlinuz-${KERNELRELEASE}"
cp System.map "$PKG_DIR/boot/System.map-${KERNELRELEASE}"
cp .config "$PKG_DIR/boot/config-${KERNELRELEASE}"

echo -e "${BLUE}Installing modules...${NC}"
make INSTALL_MOD_PATH="$PKG_DIR" modules_install > /dev/null 2>&1

# Clean up build artifacts from modules
echo -e "${BLUE}Cleaning module build artifacts...${NC}"
find "$PKG_DIR/lib/modules" -name "*.o" -delete
find "$PKG_DIR/lib/modules" -name ".*.cmd" -delete
find "$PKG_DIR/lib/modules" -name "*.ko.cmd" -delete
rm -f "$PKG_DIR/lib/modules/$KERNELRELEASE"/{build,source}

# Create metadata file
cat > "$PKG_DIR/KERNEL_INFO" <<EOF
Kernel Release: $KERNELRELEASE
Build Type: $BUILD_TYPE
Build Date: $(date -u +%Y-%m-%d)
Build Host: $(hostname)

Features:
- BORE Scheduler (Burst-Oriented Response Enhancer)
- BBRv3 TCP Congestion Control
- march=native -mtune=native (Intel Alderlake)
- LTO Full (Link Time Optimization)
- CachyOS Performance Patches
- CONFIG_MODVERSIONS disabled for DKMS compatibility

Compiler: $(clang --version | head -1)

Installation:
  1. Extract: tar -xzf $PACKAGE_NAME
  2. cd BobZKernel-${KERNELRELEASE}
  3. sudo cp boot/* /boot/
  4. sudo cp -r lib/modules/${KERNELRELEASE} /lib/modules/
  5. sudo depmod -a ${KERNELRELEASE}
  6. sudo update-initramfs -c -k ${KERNELRELEASE}  (Debian/Ubuntu)
     OR
     sudo dracut --force /boot/initramfs-${KERNELRELEASE}.img ${KERNELRELEASE}  (Fedora/RHEL)
     OR
     sudo mkinitcpio -k ${KERNELRELEASE} -g /boot/initramfs-${KERNELRELEASE}.img  (Arch)
  7. sudo update-grub

Warning:
  This kernel is optimized with march=native for Intel Alderlake.
  It may not boot on different CPU architectures.
EOF

# Create simple install script
cat > "$PKG_DIR/install.sh" <<'INSTALL_SCRIPT'
#!/bin/bash
# Simple installation script

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Must be run as root"
    echo "Usage: sudo ./install.sh"
    exit 1
fi

KERNELRELEASE=$(basename lib/modules/*)

echo "Installing BobZKernel $KERNELRELEASE..."

# Copy files
echo "Copying kernel files..."
cp -v boot/* /boot/

echo "Installing modules..."
cp -r lib/modules/$KERNELRELEASE /lib/modules/

echo "Running depmod..."
depmod -a $KERNELRELEASE

# Detect distro and generate initramfs
echo "Generating initramfs..."
if command -v update-initramfs &> /dev/null; then
    update-initramfs -c -k $KERNELRELEASE
elif command -v dracut &> /dev/null; then
    dracut --force /boot/initramfs-$KERNELRELEASE.img $KERNELRELEASE
elif command -v mkinitcpio &> /dev/null; then
    mkinitcpio -k $KERNELRELEASE -g /boot/initramfs-$KERNELRELEASE.img
else
    echo "Warning: Could not detect initramfs tool, please generate manually"
fi

# Update bootloader
echo "Updating bootloader..."
if command -v update-grub &> /dev/null; then
    update-grub
elif command -v grub-mkconfig &> /dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig &> /dev/null; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
else
    echo "Warning: Could not detect bootloader tool, please update manually"
fi

echo
echo "Installation complete!"
echo "Reboot and select kernel $KERNELRELEASE from GRUB menu"
INSTALL_SCRIPT

chmod +x "$PKG_DIR/install.sh"

# Create the tarball
echo -e "${BLUE}Creating tarball...${NC}"
cd "$TEMP_DIR"
tar -czf "$BASE_DIR/$PACKAGE_NAME" "BobZKernel-${KERNELRELEASE}"

PACKAGE_SIZE=$(du -h "$BASE_DIR/$PACKAGE_NAME" | cut -f1)

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Kernel Package Created!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Package: $PACKAGE_NAME${NC}"
echo -e "${GREEN}Size: $PACKAGE_SIZE${NC}"
echo -e "${GREEN}Location: $BASE_DIR/$PACKAGE_NAME${NC}"
echo
echo -e "${BLUE}Package Contents:${NC}"
echo "  boot/vmlinuz-${KERNELRELEASE}"
echo "  boot/System.map-${KERNELRELEASE}"
echo "  boot/config-${KERNELRELEASE}"
echo "  lib/modules/${KERNELRELEASE}/"
echo "  KERNEL_INFO"
echo "  install.sh"
echo
echo -e "${BLUE}To install on any system:${NC}"
echo "  tar -xzf $PACKAGE_NAME"
echo "  cd BobZKernel-${KERNELRELEASE}"
echo "  sudo ./install.sh"
echo
echo -e "${BLUE}Or copy to Ventoy USB:${NC}"
echo "  cp $PACKAGE_NAME /media/bob/Ventoy/Kernels/"
echo
