#!/bin/bash
# Patch DKMS sources for kernel API compatibility
# This script applies compatibility patches to DKMS module sources before building

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Checking DKMS sources for required patches...${NC}"

# Patch NVIDIA 580.95.05 for kernel 6.18+ API changes
NVIDIA_SRC="/usr/src/nvidia-580.95.05"
if [ -d "$NVIDIA_SRC" ]; then
    echo -e "${YELLOW}Patching NVIDIA 580.95.05 for kernel 6.18 compatibility...${NC}"

    # Fix get_dev_pagemap() API change (2 args -> 1 arg in kernel 6.18)
    if grep -q "get_dev_pagemap(page_to_pfn(page), NULL)" "$NVIDIA_SRC/nvidia-uvm/uvm_va_range_device_p2p.c" 2>/dev/null; then
        sed -i 's/get_dev_pagemap(page_to_pfn(page), NULL)/get_dev_pagemap(page_to_pfn(page))/g' \
            "$NVIDIA_SRC/nvidia-uvm/uvm_va_range_device_p2p.c"
        echo -e "${GREEN}  ✓ Fixed get_dev_pagemap() API${NC}"
    fi
fi

# Currently no patches needed for xpadneo or LenovoLegionLinux
# This section is a placeholder for future compatibility fixes

echo -e "${GREEN}✓ DKMS source patching complete${NC}"
