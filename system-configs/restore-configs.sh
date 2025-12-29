#!/bin/bash
# Restore BobZKernel system configurations
# Run with sudo

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

BACKUP_DIR="$(dirname "$0")"

echo "=== Restoring BobZKernel System Configurations ==="
echo "From: $BACKUP_DIR"
echo ""

# Restore GRUB
echo "Restoring GRUB configuration..."
cp "$BACKUP_DIR/grub-default" /etc/default/grub
update-grub

# Restore initramfs config
echo "Restoring initramfs configuration..."
cp "$BACKUP_DIR/initramfs.conf" /etc/initramfs-tools/initramfs.conf

# Restore hooks
echo "Restoring initramfs hooks..."
cp "$BACKUP_DIR/hooks/"* /etc/initramfs-tools/hooks/ 2>/dev/null || true
chmod +x /etc/initramfs-tools/hooks/exclude-*

# Restore modprobe config
echo "Restoring modprobe configuration..."
cp "$BACKUP_DIR/modprobe.d/"* /etc/modprobe.d/ 2>/dev/null || true

# Restore TLP
if [ -f "$BACKUP_DIR/tlp.conf" ]; then
    echo "Restoring TLP configuration..."
    cp "$BACKUP_DIR/tlp.conf" /etc/tlp.conf
fi

# Restore fstab
echo "Restoring fstab..."
cp "$BACKUP_DIR/fstab" /etc/fstab

# Rebuild initramfs
echo "Rebuilding initramfs..."
KERNEL_VERSION=$(uname -r)
update-initramfs -u -k "$KERNEL_VERSION"

echo ""
echo "=== Restore Complete! ==="
echo "Configurations have been restored."
echo "Reboot to apply all changes."
