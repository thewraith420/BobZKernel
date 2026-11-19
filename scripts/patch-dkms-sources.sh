#!/bin/bash
# Patch DKMS sources for kernel API compatibility
# This script applies compatibility patches to DKMS module sources before building

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Checking DKMS sources for required patches...${NC}"

# Patch any NVIDIA driver for kernel 6.18+ API changes (if needed)
NVIDIA_PATCHED=false
for NVIDIA_SRC in /usr/src/nvidia-*; do
    if [ -d "$NVIDIA_SRC" ] && [ -f "$NVIDIA_SRC/dkms.conf" ]; then
        NVIDIA_VERSION=$(basename "$NVIDIA_SRC" | sed 's/nvidia-//')
        echo -e "${YELLOW}Checking NVIDIA $NVIDIA_VERSION for kernel compatibility patches...${NC}"

        # Fix get_dev_pagemap() API change (2 args -> 1 arg in kernel 6.18)
        # This affects some older drivers like 580.95.05
        if [ -f "$NVIDIA_SRC/nvidia-uvm/uvm_va_range_device_p2p.c" ]; then
            if grep -q "get_dev_pagemap(page_to_pfn(page), NULL)" "$NVIDIA_SRC/nvidia-uvm/uvm_va_range_device_p2p.c" 2>/dev/null; then
                sed -i 's/get_dev_pagemap(page_to_pfn(page), NULL)/get_dev_pagemap(page_to_pfn(page))/g' \
                    "$NVIDIA_SRC/nvidia-uvm/uvm_va_range_device_p2p.c"
                echo -e "${GREEN}  ✓ Fixed get_dev_pagemap() API in $NVIDIA_VERSION${NC}"
                NVIDIA_PATCHED=true
            else
                echo -e "${GREEN}  ✓ No patches needed for $NVIDIA_VERSION${NC}"
            fi
        else
            echo -e "${GREEN}  ✓ No patches needed for $NVIDIA_VERSION${NC}"
        fi

        # Fix dmem_cgroup_register_region() API change (kernel 7.3 takes a
        # struct dmem_cgroup_init instead of a bare size). Version-guarded,
        # so the same source still builds for older kernels.
        OS_IFACE="$NVIDIA_SRC/kernel-open/nvidia/os-interface.c"
        # Exact old form only: 620+ ships its own fix with a similar-looking line.
        if [ -f "$OS_IFACE" ] && grep -qxF "    void *region = dmem_cgroup_register_region(size, name);" "$OS_IFACE"; then
            python3 - "$OS_IFACE" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f) as fh:
    content = fh.read()
old = "    void *region = dmem_cgroup_register_region(size, name);\n"
new = """#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 3, 0)
    struct dmem_cgroup_init init = { .size = size };
    void *region = dmem_cgroup_register_region(&init, "%s", name);
#else
    void *region = dmem_cgroup_register_region(size, "%s", name);
#endif
"""
if content.count(old) != 1:
    sys.exit("unexpected os-interface.c layout, not patching")
with open(f, "w") as fh:
    fh.write(content.replace(old, new))
PYEOF
            echo -e "${GREEN}  ✓ Fixed dmem_cgroup_register_region() API (7.3) in $NVIDIA_VERSION${NC}"
            NVIDIA_PATCHED=true
        fi
    fi
done

if [ "$NVIDIA_PATCHED" = false ]; then
    echo -e "${GREEN}  No NVIDIA patches required${NC}"
fi

# Currently no patches needed for xpadneo or LenovoLegionLinux
# This section is a placeholder for future compatibility fixes

echo -e "${GREEN}✓ DKMS source patching complete${NC}"
