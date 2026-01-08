#!/bin/bash
# Build VMware modules for new kernel (Manual Method)
# Usage: ./build-vmware-modules.sh KERNEL_VERSION

KERNEL_VERSION="$1"

if [ -z "$KERNEL_VERSION" ]; then
    echo "Usage: $0 KERNEL_VERSION"
    exit 1
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

VMWARE_SOURCE_DIR="/usr/lib/vmware/modules/source"

# Check if VMware source exists
if [ ! -d "$VMWARE_SOURCE_DIR" ]; then
    echo "VMware module sources not found at $VMWARE_SOURCE_DIR. Skipping."
    exit 0
fi

echo "Building VMware modules for kernel $KERNEL_VERSION..."

# Verify headers exist
HEADERS_DIR="/lib/modules/$KERNEL_VERSION/build"
if [ ! -d "$HEADERS_DIR" ]; then
    echo "Error: Kernel headers not found at $HEADERS_DIR"
    exit 1
fi

# Destination directory for modules
DEST_DIR="/lib/modules/$KERNEL_VERSION/misc"
mkdir -p "$DEST_DIR"

# Create a temporary directory for building
BUILD_DIR=$(mktemp -d)
# Trap to cleanup temp dir on exit
trap 'rm -rf "$BUILD_DIR"' EXIT

# List of modules to build
MODULES=("vmmon" "vmnet")

# Check if other modules exist and add them if present
for mod in vmci vsock; do
    if [ -f "$VMWARE_SOURCE_DIR/$mod.tar" ]; then
        MODULES+=("$mod")
    fi
done

SUCCESS=true

for mod in "${MODULES[@]}"; do
    echo "Processing $mod..."
    
    cd "$BUILD_DIR"
    if [ ! -f "$VMWARE_SOURCE_DIR/$mod.tar" ]; then
        echo "Source for $mod not found. Skipping."
        continue
    fi

    # Extract
    tar xf "$VMWARE_SOURCE_DIR/$mod.tar"
    
    # The source is usually in a subdirectory named "$mod-only"
    if [ ! -d "$mod-only" ]; then
        echo "Error: Unexpected source structure for $mod."
        SUCCESS=false
        continue
    fi
    
    cd "$mod-only"
    
    # Build
    echo "  Compiling $mod..."
    # Use standard Kbuild syntax
    # We rely on environment variables (LLVM=1, CC=clang, etc.) if set by parent script
    if make -C "$HEADERS_DIR" M="$PWD" modules >/dev/null 2>&1; then
        echo "  Build successful."
    else
        echo "  Error: Compilation failed for $mod."
        echo "  Retrying with output enabled to show errors:"
        make -C "$HEADERS_DIR" M="$PWD" modules
        SUCCESS=false
        continue
    fi
    
    # Install
    echo "  Installing $mod.ko to $DEST_DIR..."
    if [ -f "$mod.ko" ]; then
        cp "$mod.ko" "$DEST_DIR/"
    else
        echo "  Error: $mod.ko not found after build."
        SUCCESS=false
    fi
done

if [ "$SUCCESS" = true ]; then
    echo "Updating module dependencies..."
    depmod -a "$KERNEL_VERSION"
    echo "VMware modules built and installed successfully for $KERNEL_VERSION."
else
    echo "Some VMware modules failed to build."
    exit 1
fi
