#!/bin/bash
# nvidia-randstruct-fix.sh - Fix RANDSTRUCT struct layout mismatch between
# NVIDIA kernel modules (nvidia-modeset has a precompiled binary blob that
# was compiled WITHOUT RANDSTRUCT, but nvidia-drm is compiled WITH it).
#
# ROOT CAUSE: CONFIG_RANDSTRUCT_FULL=y causes struct NvKmsKapiCallbacks
# field order to be randomized in nvidia-drm.ko, but the precompiled
# nv-modeset-kernel.o_binary in nvidia-modeset.ko uses the original order.
# This causes suspend callbacks to call the wrong function (probe instead
# of suspendResume), resulting in a NULL pointer dereference and system hang.
#
# FIX: Add __no_randomize_layout to all structs shared across the module
# boundary with the precompiled binary blob.
#
# Usage:
#   sudo ./nvidia-randstruct-fix.sh apply    # Apply the fix
#   sudo ./nvidia-randstruct-fix.sh revert   # Revert to original
#   sudo ./nvidia-randstruct-fix.sh rebuild  # Rebuild DKMS after fixing

set -euo pipefail

# Auto-detect installed nvidia source directory (use latest version)
NVIDIA_SRC=$(ls -d /usr/src/nvidia-* 2>/dev/null | sort -V | tail -1)
if [ -z "$NVIDIA_SRC" ] || [ ! -d "$NVIDIA_SRC" ]; then
    echo "ERROR: No nvidia source found in /usr/src/nvidia-*"
    exit 1
fi
NVIDIA_VER=$(basename "$NVIDIA_SRC" | sed 's/^nvidia-//')
echo "Detected nvidia version: $NVIDIA_VER (source: $NVIDIA_SRC)"

KAPI_H="$NVIDIA_SRC/kernel-open/common/inc/nvkms-kapi.h"
MODESET_H="$NVIDIA_SRC/kernel-open/common/inc/nv-modeset-interface.h"
KERNEL_VER=$(uname -r)

backup() {
    for f in "$KAPI_H" "$MODESET_H"; do
        if [ -f "$f" ] && [ ! -f "$f.orig-randstruct" ]; then
            cp "$f" "$f.orig-randstruct"
            echo "Backed up: $f"
        fi
    done
}

apply_fix() {
    backup

    echo "=== Fixing NvKmsKapiCallbacks in nvkms-kapi.h ==="
    python3 - "$KAPI_H" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

# Ensure compiler.h is included for __no_randomize_layout
if '#include <linux/compiler.h>' not in content:
    # Add it near the top, after the header guard or first includes
    # Find a good insertion point
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('#ifndef') or line.startswith('#define _NVKMS'):
            insert_idx = i + 1
        if line.startswith('#include'):
            insert_idx = i + 1
            break
    if insert_idx == 0:
        insert_idx = 2  # after header guard
    lines.insert(insert_idx, '#include <linux/compiler.h>  /* __no_randomize_layout */')
    content = '\n'.join(lines)

# Fix struct NvKmsKapiCallbacks
old = '''struct NvKmsKapiCallbacks {
    void (*suspendResume)(NvBool suspend);
    void (*remove)(NvU32 gpuId);
    void (*probe)(const struct NvKmsKapiGpuInfo *gpu_info);
};'''
new = '''struct NvKmsKapiCallbacks {
    void (*suspendResume)(NvBool suspend);
    void (*remove)(NvU32 gpuId);
    void (*probe)(const struct NvKmsKapiGpuInfo *gpu_info);
} __no_randomize_layout;'''
content = content.replace(old, new, 1)

# Fix struct NvKmsKapiFunctionsTable - also crosses the binary blob boundary
old = 'struct NvKmsKapiFunctionsTable {'
new = 'struct __no_randomize_layout NvKmsKapiFunctionsTable {'
if old in content:
    content = content.replace(old, new, 1)

# Fix struct NvKmsKapiGpuInfo - passed as argument across boundary
old = '''struct NvKmsKapiGpuInfo {
    nv_gpu_info_t gpuInfo;
    MIGDeviceId   migDevice;
};'''
new = '''struct NvKmsKapiGpuInfo {
    nv_gpu_info_t gpuInfo;
    MIGDeviceId   migDevice;
} __no_randomize_layout;'''
if old in content:
    content = content.replace(old, new, 1)

with open(f, 'w') as fh:
    fh.write(content)
print(f"Fixed {f}")
PYEOF

    echo "=== Fixing nvidia_modeset_callbacks_t and nvidia_modeset_rm_ops_t in nv-modeset-interface.h ==="
    python3 - "$MODESET_H" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

# Ensure compiler.h is included
if '#include <linux/compiler.h>' not in content:
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('#include') or line.startswith('#define _NV_MODESET'):
            insert_idx = i + 1
    if insert_idx == 0:
        insert_idx = 2
    lines.insert(insert_idx, '#include <linux/compiler.h>  /* __no_randomize_layout */')
    content = '\n'.join(lines)

# Fix nvidia_modeset_callbacks_t
old = '} nvidia_modeset_callbacks_t;'
new = '} __no_randomize_layout nvidia_modeset_callbacks_t;'
content = content.replace(old, new, 1)

# Fix nvidia_modeset_rm_ops_t
old = '} nvidia_modeset_rm_ops_t;'
new = '} __no_randomize_layout nvidia_modeset_rm_ops_t;'
content = content.replace(old, new, 1)

with open(f, 'w') as fh:
    fh.write(content)
print(f"Fixed {f}")
PYEOF

    echo ""
    echo "=== RANDSTRUCT fix applied! ==="
    echo "Run: sudo $0 rebuild"
}

revert_fix() {
    for f in "$KAPI_H" "$MODESET_H"; do
        if [ -f "$f.orig-randstruct" ]; then
            cp "$f.orig-randstruct" "$f"
            rm "$f.orig-randstruct"
            echo "Reverted: $f"
        fi
    done
    echo "=== Fix reverted ==="
}

rebuild_dkms() {
    echo "=== Removing old DKMS build for $KERNEL_VER ==="
    dkms remove "nvidia/$NVIDIA_VER" -k "$KERNEL_VER" 2>/dev/null || true

    echo "=== Building nvidia DKMS for $KERNEL_VER ==="
    dkms build "nvidia/$NVIDIA_VER" -k "$KERNEL_VER"

    echo "=== Installing nvidia DKMS for $KERNEL_VER ==="
    dkms install "nvidia/$NVIDIA_VER" -k "$KERNEL_VER"

    echo ""
    echo "=== DKMS rebuild complete ==="
    echo "To test: sudo rtcwake -m mem -s 10 -v"
}

case "${1:-}" in
    apply)
        apply_fix
        ;;
    revert)
        revert_fix
        ;;
    rebuild)
        rebuild_dkms
        ;;
    all)
        apply_fix
        rebuild_dkms
        ;;
    *)
        echo "Usage: $0 {apply|revert|rebuild|all}"
        echo "  apply   - Apply __no_randomize_layout fix to nvidia headers"
        echo "  revert  - Revert to original headers"
        echo "  rebuild - Rebuild DKMS modules"
        echo "  all     - Apply fix and rebuild"
        exit 1
        ;;
esac
