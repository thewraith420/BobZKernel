#!/bin/bash
# Backup all BobZKernel system configuration files
# Run this after making system changes to preserve them

set -e

BACKUP_DIR="/home/bob/buildstuff/BobzKernel/system-configs"
DATE=$(date +%Y%m%d-%H%M%S)

echo "=== BobZKernel System Configuration Backup ==="
echo "Creating backup in: $BACKUP_DIR"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup GRUB configuration
echo "Backing up GRUB configuration..."
cp /etc/default/grub "$BACKUP_DIR/grub-default"

# Backup initramfs configuration
echo "Backing up initramfs configuration..."
cp /etc/initramfs-tools/initramfs.conf "$BACKUP_DIR/initramfs.conf"

# Backup initramfs hooks
echo "Backing up initramfs hooks..."
mkdir -p "$BACKUP_DIR/hooks"
cp /etc/initramfs-tools/hooks/exclude-* "$BACKUP_DIR/hooks/" 2>/dev/null || true

# Backup modprobe blacklists
echo "Backing up modprobe configuration..."
mkdir -p "$BACKUP_DIR/modprobe.d"
cp /etc/modprobe.d/blacklist-nouveau.conf "$BACKUP_DIR/modprobe.d/" 2>/dev/null || true

# Backup TLP configuration
echo "Backing up TLP configuration..."
cp /etc/tlp.conf "$BACKUP_DIR/tlp.conf" 2>/dev/null || true

# Backup fstab (for EFI mount options)
echo "Backing up fstab..."
cp /etc/fstab "$BACKUP_DIR/fstab"

# Create restore script
echo "Creating restore script..."
cat > "$BACKUP_DIR/restore-configs.sh" << 'RESTORE_EOF'
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
RESTORE_EOF

chmod +x "$BACKUP_DIR/restore-configs.sh"

echo ""
echo "=== Backup Complete! ==="
echo "Backed up to: $BACKUP_DIR"
echo ""
echo "Files backed up:"
echo "  - GRUB configuration"
echo "  - Initramfs configuration"
echo "  - Initramfs hooks (exclude-nvidia, exclude-i915, exclude-nouveau)"
echo "  - Modprobe blacklists"
echo "  - TLP configuration"
echo "  - fstab"
echo ""
echo "To restore these configurations on a fresh system:"
echo "  sudo $BACKUP_DIR/restore-configs.sh"
