#!/bin/bash
# Build VMware modules for new kernel
# Usage: ./build-vmware-modules.sh KERNEL_VERSION

KERNEL_VERSION="$1"

if [ -z "$KERNEL_VERSION" ]; then
    echo "Usage: $0 KERNEL_VERSION"
    exit 1
fi

# Check if VMware is installed
if [ ! -d "/usr/lib/vmware" ]; then
    echo "VMware not installed, skipping"
    exit 0
fi

echo "Building VMware modules for kernel $KERNEL_VERSION..."

# Try to rebuild VMware modules
if command -v vmware-modconfig >/dev/null 2>&1; then
    vmware-modconfig --console --install-all || {
        echo "Warning: VMware module build failed"
        exit 1
    }
else
    echo "vmware-modconfig not found, skipping"
    exit 0
fi

echo "VMware modules built successfully"
