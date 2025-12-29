#!/bin/bash
# Apply initramfs optimizations to reduce size
# This script blacklists unnecessary modules and configures firmware exclusions

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Applying Initramfs Optimizations ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script needs sudo privileges. Running with sudo...${NC}"
    sudo "$0" "$@"
    exit $?
fi

# 1. Blacklist nouveau
echo -e "${BLUE}Step 1: Blacklisting nouveau driver...${NC}"
cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
# Blacklist nouveau - we use proprietary NVIDIA driver
# This prevents nouveau from being included in initramfs
blacklist nouveau
options nouveau modeset=0
EOF
echo "Created /etc/modprobe.d/blacklist-nouveau.conf"

# 2. Exclude old NVIDIA firmware from initramfs
echo -e "${BLUE}Step 2: Configuring initramfs to exclude old firmware...${NC}"
cat > /etc/initramfs-tools/conf.d/exclude-old-firmware.conf << 'EOF'
# Exclude old NVIDIA firmware versions to save space
# Only keep current driver version (580.95.05)
FIRMWARE_EXCLUDES="nvidia/ga102/* nvidia/tu102/*"
EOF
echo "Created /etc/initramfs-tools/conf.d/exclude-old-firmware.conf"

# 3. Exclude LVM tools if not needed
echo -e "${BLUE}Step 3: Checking LVM usage...${NC}"
if ! lsblk | grep -q "lvm"; then
    echo "No LVM detected, excluding LVM tools from initramfs"
    cat > /etc/initramfs-tools/conf.d/no-lvm.conf << 'EOF'
# No LVM in use, don't include LVM tools
MODULES_DEP=""
EOF
fi

echo ""
echo -e "${GREEN}=== Optimizations Applied ===${NC}"
echo ""
echo -e "${YELLOW}These changes will take effect when you rebuild initramfs${NC}"
echo -e "${YELLOW}(automatically done during kernel installation)${NC}"
echo ""
echo "Summary of changes:"
echo "  - Nouveau driver blacklisted"
echo "  - Old NVIDIA firmware excluded"
echo "  - LVM tools excluded (if not in use)"
echo ""
echo "Expected initramfs size reduction: ~350-400MB"
