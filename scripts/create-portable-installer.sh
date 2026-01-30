#!/bin/bash
# Create portable kernel installer package
# This script packages the kernel and modules into a portable installer

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="6.18"
KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

# Auto-detect branch
BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")

# Get kernel release version
cd "$KERNEL_DIR"
KERNELRELEASE=$(make -s kernelrelease 2>/dev/null || echo "6.18.3-BobZKernel")

# Detect optimizations from config and branch
if grep -q "CONFIG_X86_NATIVE_CPU=y" .config; then
    MARCH_OPTIMIZATION="march=native (CPU-specific optimization)"
    ARCH_NOTE="Optimized for this CPU architecture"
elif [ "$BRANCH" = "pixel-slate" ]; then
    MARCH_OPTIMIZATION="march=skylake (Intel Skylake/Kaby Lake architecture)"
    ARCH_NOTE="Optimized for Intel Skylake/Kaby Lake (Pixel Slate: Core i5-8200Y)"
else
    MARCH_OPTIMIZATION="generic x86-64 (compatible with most x86-64 CPUs)"
    ARCH_NOTE="Compatible with most x86-64 processors"
fi

if grep -q "CONFIG_LTO_CLANG_FULL=y" .config; then
    LTO_STATUS="LTO Full (Link Time Optimization)"
elif grep -q "CONFIG_LTO_NONE=y" .config; then
    LTO_STATUS="LTO Disabled"
else
    LTO_STATUS="LTO status unknown"
fi

if grep -q "CONFIG_SCHED_BORE=y" .config; then
    BORE_STATUS="BORE Scheduler (Burst-Oriented Response Enhancer)"
else
    BORE_STATUS="Standard Linux Scheduler"
fi

INSTALLER_DIR="$BASE_DIR/installer-$KERNELRELEASE"

# Create clean version for package naming (remove duplicate BobZKernel)
# All branches now have CONFIG_LOCALVERSION="-BobZKernel" in their configs
# Strip it from the filename to avoid: BobZKernel-6.18.8-BobZKernel-pixel-slate+-installer.tar.gz
PACKAGE_VERSION=$(echo "$KERNELRELEASE" | sed 's/-BobZKernel//')
PACKAGE_NAME="BobZKernel-${PACKAGE_VERSION}-installer.tar.gz"

echo -e "${BLUE}Creating portable installer for kernel $KERNELRELEASE${NC}"
echo

# Clean up old installer directory
if [ -d "$INSTALLER_DIR" ]; then
    echo -e "${YELLOW}Removing old installer directory...${NC}"
    rm -rf "$INSTALLER_DIR"
fi

# Create installer structure
echo -e "${BLUE}Creating installer directory structure...${NC}"
mkdir -p "$INSTALLER_DIR"/{boot,lib/modules,scripts}

# Copy kernel image
echo -e "${BLUE}Copying kernel image...${NC}"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$INSTALLER_DIR/boot/vmlinuz-$KERNELRELEASE"
cp "$KERNEL_DIR/System.map" "$INSTALLER_DIR/boot/System.map-$KERNELRELEASE"
cp "$KERNEL_DIR/.config" "$INSTALLER_DIR/boot/config-$KERNELRELEASE"

# Copy modules
echo -e "${BLUE}Copying kernel modules (this may take a minute)...${NC}"
cd "$KERNEL_DIR"
make INSTALL_MOD_PATH="$INSTALLER_DIR" modules_install > /dev/null 2>&1

# Create version info file
echo -e "${BLUE}Creating version info...${NC}"
cat > "$INSTALLER_DIR/VERSION" <<EOF
Kernel: $KERNELRELEASE
Branch: $BRANCH
Built: $(date)
Optimizations:
- $BORE_STATUS
- BBRv3 TCP Congestion Control
- $MARCH_OPTIMIZATION
- $LTO_STATUS
- Custom CachyOS patches
- MODVERSIONS disabled for DKMS compatibility

Host System:
- CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
- Compiler: $(clang --version | head -1)
EOF

# Create the installer script
echo -e "${BLUE}Creating installer script...${NC}"
cat > "$INSTALLER_DIR/install.sh" <<'INSTALLER_SCRIPT'
#!/bin/bash
# BobZKernel Portable Installer
# Automatically detects distribution and installs kernel

set -e

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNELRELEASE=$(basename "$SCRIPT_DIR/boot"/vmlinuz-* 2>/dev/null | grep -v '\.old$' | head -1 | sed 's/vmlinuz-//')

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         BobZKernel Portable Installer                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Kernel Version: $KERNELRELEASE${NC}"
echo

# Display version info if available
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    cat "$SCRIPT_DIR/VERSION"
    echo
fi

# Detect distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_NAME="$NAME"
    else
        echo -e "${RED}Error: Cannot detect distribution${NC}"
        exit 1
    fi
}

# Detect bootloader
detect_bootloader() {
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    
    if command -v grub-mkconfig &> /dev/null; then
        BOOTLOADER="grub2"
    elif command -v grub2-mkconfig &> /dev/null; then
        BOOTLOADER="grub2"
    elif command -v update-grub &> /dev/null; then
        BOOTLOADER="grub"
    else
        BOOTLOADER="unknown"
    fi
}

# Install kernel files
install_kernel_files() {
    echo -e "${BLUE}Installing kernel files...${NC}"
    
    # Copy kernel image
    cp -v "$SCRIPT_DIR/boot/vmlinuz-$KERNELRELEASE" /boot/
    cp -v "$SCRIPT_DIR/boot/System.map-$KERNELRELEASE" /boot/
    cp -v "$SCRIPT_DIR/boot/config-$KERNELRELEASE" /boot/
    
    # Copy modules
    echo -e "${BLUE}Installing kernel modules...${NC}"
    cp -r "$SCRIPT_DIR/lib/modules/$KERNELRELEASE" /lib/modules/
    
    # Run depmod
    echo -e "${BLUE}Running depmod...${NC}"
    depmod -a "$KERNELRELEASE"
    
    echo -e "${GREEN}✓ Kernel files installed${NC}"
}

# Update initramfs
update_initramfs() {
    echo -e "${BLUE}Generating initramfs...${NC}"
    
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            if command -v update-initramfs &> /dev/null; then
                update-initramfs -c -k "$KERNELRELEASE"
            else
                echo -e "${YELLOW}Warning: update-initramfs not found${NC}"
            fi
            ;;
        fedora|rhel|centos|rocky|almalinux)
            if command -v dracut &> /dev/null; then
                dracut --force "/boot/initramfs-$KERNELRELEASE.img" "$KERNELRELEASE"
            else
                echo -e "${YELLOW}Warning: dracut not found${NC}"
            fi
            ;;
        arch|manjaro|endeavouros)
            if command -v mkinitcpio &> /dev/null; then
                mkinitcpio -k "$KERNELRELEASE" -g "/boot/initramfs-$KERNELRELEASE.img"
            else
                echo -e "${YELLOW}Warning: mkinitcpio not found${NC}"
            fi
            ;;
        opensuse*|sles)
            if command -v dracut &> /dev/null; then
                dracut --force "/boot/initrd-$KERNELRELEASE" "$KERNELRELEASE"
            else
                echo -e "${YELLOW}Warning: dracut not found${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown distribution, you may need to generate initramfs manually${NC}"
            ;;
    esac
    
    echo -e "${GREEN}✓ Initramfs generated${NC}"
}

# Update bootloader
update_bootloader() {
    echo -e "${BLUE}Updating bootloader configuration...${NC}"
    
    case "$BOOTLOADER" in
        grub|grub2)
            if command -v update-grub &> /dev/null; then
                update-grub
            elif command -v grub-mkconfig &> /dev/null; then
                grub-mkconfig -o /boot/grub/grub.cfg
            elif command -v grub2-mkconfig &> /dev/null; then
                grub2-mkconfig -o /boot/grub2/grub.cfg
            else
                echo -e "${YELLOW}Warning: Could not update GRUB${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown bootloader, please update manually${NC}"
            ;;
    esac
    
    echo -e "${GREEN}✓ Bootloader updated${NC}"
}

# Main installation
echo -e "${BLUE}Detecting system configuration...${NC}"
detect_distro
detect_bootloader

echo -e "${GREEN}Distribution: $DISTRO_NAME ($DISTRO_ID $DISTRO_VERSION)${NC}"
echo -e "${GREEN}Boot Mode: $BOOT_MODE${NC}"
echo -e "${GREEN}Bootloader: $BOOTLOADER${NC}"
echo

read -p "Do you want to proceed with installation? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Installation cancelled${NC}"
    exit 0
fi

echo
install_kernel_files
echo
update_initramfs
echo
update_bootloader

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation Complete!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Kernel $KERNELRELEASE has been installed successfully.${NC}"
echo -e "${YELLOW}Please reboot your system and select the new kernel from GRUB.${NC}"
echo
echo -e "${BLUE}Kernel optimizations:${NC}"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    grep -E "march|BORE|LTO|BBR" "$SCRIPT_DIR/VERSION" | sed 's/^/  /'
fi
echo

INSTALLER_SCRIPT

chmod +x "$INSTALLER_DIR/install.sh"

# Create uninstall script
echo -e "${BLUE}Creating uninstall script...${NC}"
cat > "$INSTALLER_DIR/uninstall.sh" <<'UNINSTALL_SCRIPT'
#!/bin/bash
# BobZKernel Uninstaller

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNELRELEASE=$(basename "$SCRIPT_DIR/boot"/vmlinuz-* 2>/dev/null | grep -v '\.old$' | head -1 | sed 's/vmlinuz-//')

echo -e "${YELLOW}This will remove kernel $KERNELRELEASE from your system.${NC}"
read -p "Are you sure? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo -e "${BLUE}Removing kernel files...${NC}"
rm -fv "/boot/vmlinuz-$KERNELRELEASE"
rm -fv "/boot/System.map-$KERNELRELEASE"
rm -fv "/boot/config-$KERNELRELEASE"
rm -fv "/boot/initrd.img-$KERNELRELEASE" "/boot/initramfs-$KERNELRELEASE.img" 2>/dev/null || true
rm -rfv "/lib/modules/$KERNELRELEASE"

echo -e "${BLUE}Updating bootloader...${NC}"
if command -v update-grub &> /dev/null; then
    update-grub
elif command -v grub-mkconfig &> /dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig &> /dev/null; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi

echo -e "${GREEN}Kernel $KERNELRELEASE has been removed.${NC}"
UNINSTALL_SCRIPT

chmod +x "$INSTALLER_DIR/uninstall.sh"

# Create README
echo -e "${BLUE}Creating README...${NC}"
cat > "$INSTALLER_DIR/README.md" <<README
# BobZKernel Portable Installer

This is a portable kernel installer package that can be used to install the BobZKernel on various Linux distributions.

## Features

- **$BORE_STATUS**
- **BBRv3**: Latest TCP congestion control algorithm
- **$MARCH_OPTIMIZATION**
- **$LTO_STATUS**
- **CachyOS patches**: Additional performance optimizations

## Requirements

- x86_64 CPU
- Linux distribution with:
  - GRUB bootloader
  - systemd or compatible init system
  - Support for kernel 6.18+

## Installation

1. Extract this package to any location
2. Run the installer as root:
   \`\`\`bash
   sudo ./install.sh
   \`\`\`
3. Reboot and select the BobZKernel from GRUB

## Supported Distributions

The installer auto-detects and supports:
- Ubuntu, Debian, Linux Mint, Pop!_OS
- Fedora, RHEL, CentOS, Rocky, AlmaLinux
- Arch, Manjaro, EndeavourOS
- openSUSE, SLES

## Uninstallation

To remove the kernel:
\`\`\`bash
sudo ./uninstall.sh
\`\`\`

## DKMS Modules

If you use DKMS modules (NVIDIA, VirtualBox, etc.), they will need to be rebuilt for this kernel:

\`\`\`bash
sudo dkms autoinstall -k \$(make -C . kernelrelease)
\`\`\`

Or manually:
\`\`\`bash
sudo dkms install -m MODULE_NAME -v <VERSION> -k <KERNEL_VERSION>
\`\`\`

## Important Notes

- This kernel is compiled with $MARCH_OPTIMIZATION
- CONFIG_MODVERSIONS is disabled for DKMS compatibility with LTO

## Troubleshooting

If the system doesn't boot:
1. Select your previous kernel from GRUB
2. Run the uninstall script
3. Check if your CPU is compatible

## Version Info

See the \`VERSION\` file for detailed build information.
README

# Create tarball
echo
echo -e "${BLUE}Creating tarball: $PACKAGE_NAME${NC}"
cd "$BASE_DIR"
tar -czf "$PACKAGE_NAME" -C "$INSTALLER_DIR" .

# Get size
PACKAGE_SIZE=$(du -h "$PACKAGE_NAME" | cut -f1)

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Portable Installer Created!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Package: $PACKAGE_NAME${NC}"
echo -e "${GREEN}Size: $PACKAGE_SIZE${NC}"
echo -e "${GREEN}Location: $BASE_DIR/$PACKAGE_NAME${NC}"
echo
echo -e "${BLUE}To use on another system:${NC}"
echo "  1. Copy $PACKAGE_NAME to the target system"
echo "  2. Extract: tar -xzf $PACKAGE_NAME"
echo "  3. Run: sudo ./install.sh"
echo
echo -e "${YELLOW}Note: Keep the installer directory for easy uninstallation${NC}"
echo
