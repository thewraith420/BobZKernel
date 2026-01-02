#!/bin/bash
# Patch DKMS sources for kernel compatibility issues
# Run this before dkms autoinstall to avoid build failures

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Patching DKMS Sources ===${NC}"

# NVIDIA driver: get_dev_pagemap API fix (kernel 6.18+)
if [ -f "/usr/src/nvidia-580.95.05/nvidia-uvm/uvm_va_range_device_p2p.c" ]; then
    echo -e "${BLUE}Patching NVIDIA: get_dev_pagemap API (6.18+)...${NC}"
    sudo sed -i 's/get_dev_pagemap(page_to_pfn(page), NULL)/get_dev_pagemap(page_to_pfn(page))/g' \
        /usr/src/nvidia-580.95.05/nvidia-uvm/uvm_va_range_device_p2p.c
    echo -e "${GREEN}✓ NVIDIA patched${NC}"
fi

# xpadneo: ida_simple_get/remove to ida_alloc/ida_free API fix (kernel 6.0+)
XPADNEO_SRC=$(ls -d /usr/src/hid-xpadneo-* 2>/dev/null | head -1)
if [ -f "$XPADNEO_SRC/src/hid-xpadneo.c" ]; then
    echo -e "${BLUE}Patching xpadneo: ida API (6.0+)...${NC}"
    
    # Add idr.h header if not present
    if ! grep -q "#include <linux/idr.h>" "$XPADNEO_SRC/src/hid-xpadneo.c"; then
        sudo sed -i '/#include <linux\/module.h>/a #include <linux\/idr.h>' \
            "$XPADNEO_SRC/src/hid-xpadneo.c"
    fi
    
    # Replace ida_simple_get with ida_alloc
    sudo sed -i 's/ida_simple_get(&xpadneo_device_id_allocator, 0, 0, GFP_KERNEL)/ida_alloc(\&xpadneo_device_id_allocator, GFP_KERNEL)/g' \
        "$XPADNEO_SRC/src/hid-xpadneo.c"
    
    # Replace ida_simple_remove with ida_free
    sudo sed -i 's/ida_simple_remove(&xpadneo_device_id_allocator, xdata->id)/ida_free(\&xpadneo_device_id_allocator, xdata->id)/g' \
        "$XPADNEO_SRC/src/hid-xpadneo.c"
    
    echo -e "${GREEN}✓ xpadneo patched${NC}"
fi

# VMware modules: function prototype fixes for Clang strict-prototypes
VMMON_SRC="/usr/lib/vmware/modules/source/vmmon.tar"
VMNET_SRC="/usr/lib/vmware/modules/source/vmnet.tar"

if [ -f "$VMMON_SRC" ] || [ -f "$VMNET_SRC" ]; then
    echo -e "${BLUE}Patching VMware: function prototypes...${NC}"
    
    # These will be auto-patched during build in /tmp, so just log
    echo -e "${YELLOW}Note: VMware modules require manual prototype fixes during build${NC}"
    echo -e "${YELLOW}(VNetFreeInterfaceList() → VNetFreeInterfaceList(void))${NC}"
    echo -e "${YELLOW}(SMACL_GetUptime() → SMACL_GetUptime(void))${NC}"
fi

echo -e "${GREEN}=== DKMS Source Patching Complete ===${NC}"
echo ""
