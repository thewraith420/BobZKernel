#!/bin/bash
# Backport cluster-aware IRQ optimization to Linux 6.18.x
# Based on Wangyang Guo's patch for 6.20+
# Auto-applies the optimization if lib/group_cpus.c doesn't have it

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$BASE_DIR/builds/linux-6.18"
GROUP_CPUS_C="$KERNEL_DIR/lib/group_cpus.c"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}=== Cluster-Aware IRQ Backport for 6.18.x ===${NC}"

# Check if file exists
if [ ! -f "$GROUP_CPUS_C" ]; then
    echo -e "${YELLOW}⊘ lib/group_cpus.c not found - skipping${NC}"
    exit 0
fi

# Check if already applied
if grep -q "__try_group_cluster_cpus" "$GROUP_CPUS_C" 2>/dev/null; then
    echo -e "${GREEN}✓ Cluster-aware optimization already applied${NC}"
    exit 0
fi

echo -e "${BLUE}Applying cluster-aware IRQ optimization backport...${NC}"

# Run the Python backport script
python3 "$SCRIPT_DIR/cluster-aware-backport.py" "$GROUP_CPUS_C"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Cluster-aware IRQ backport applied successfully${NC}"
else
    echo -e "${YELLOW}⚠ Backport script failed${NC}"
    exit 1
fi
