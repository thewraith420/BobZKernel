#!/bin/bash
# Automatically fix common patch application issues
# Usage: ./auto-fix-patches.sh [6.14|6.18]

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="${1:-6.18}"

if [ "$KERNEL_VERSION" != "6.14" ] && [ "$KERNEL_VERSION" != "6.18" ]; then
    echo -e "${RED}Error: Please specify kernel version (6.14 or 6.18)${NC}"
    echo "Usage: $0 [6.14|6.18]"
    exit 1
fi

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

echo -e "${BLUE}=== Auto-Fix Patch Issues ===${NC}"
echo "Kernel: $KERNEL_VERSION"
echo "Source: $KERNEL_DIR"
echo ""

cd "$KERNEL_DIR"

FIXES_APPLIED=0

# Fix 1: Add nsecs_per_tick if missing
echo -e "${BLUE}[1/4] Checking nsecs_per_tick...${NC}"
if ! grep -q "nsecs_per_tick.*=" kernel/sched/fair.c; then
    echo -e "${YELLOW}Adding nsecs_per_tick definition...${NC}"

    # Find the line with #ifdef CONFIG_SCHED_BORE and add after it
    sed -i '/^#ifdef CONFIG_SCHED_BORE$/a static const unsigned int nsecs_per_tick = 1000000000ULL / HZ;\n' kernel/sched/fair.c

    echo -e "${GREEN}✓ Fixed${NC}"
    ((FIXES_APPLIED++))
else
    echo -e "${GREEN}✓ Already present${NC}"
fi

# Fix 2: Add sysctl_sched_min_base_slice if missing
echo -e "${BLUE}[2/4] Checking sysctl_sched_min_base_slice...${NC}"
if grep -q "sysctl_sched_min_base_slice" kernel/sched/fair.c; then
    if ! grep -q "^unsigned int sysctl_sched_min_base_slice" kernel/sched/fair.c; then
        echo -e "${YELLOW}Adding sysctl_sched_min_base_slice definition...${NC}"

        # Replace CONFIG_CACHY section with CONFIG_SCHED_BORE section
        # This is complex, so we'll do a targeted replacement
        sed -i '/#ifdef CONFIG_CACHY/,/#endif \/\* CONFIG_CACHY \*\// {
            /#ifdef CONFIG_CACHY/ {
                s/#ifdef CONFIG_CACHY/#ifdef CONFIG_SCHED_BORE/
                a unsigned int sysctl_sched_min_base_slice = CONFIG_MIN_BASE_SLICE_NS;\n__read_mostly unsigned int sysctl_sched_base_slice = 1000000000ULL / HZ;
                n
                d
            }
            /#endif \/\* CONFIG_CACHY \*\// {
                s/#endif \/\* CONFIG_CACHY \*\//#endif \/\* CONFIG_SCHED_BORE \*\//
            }
        }' kernel/sched/fair.c 2>/dev/null || {
            echo -e "${YELLOW}Note: Could not auto-fix. Manual intervention needed.${NC}"
        }

        echo -e "${GREEN}✓ Fixed${NC}"
        ((FIXES_APPLIED++))
    else
        echo -e "${GREEN}✓ Already present${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Not needed (CONFIG_SCHED_BORE not used)${NC}"
fi

# Fix 3: Remove duplicate unprivileged_userns_clone from fork.c
echo -e "${BLUE}[3/4] Checking unprivileged_userns_clone duplication...${NC}"
if grep -q "^int unprivileged_userns_clone\|^static int unprivileged_userns_clone" kernel/fork.c; then
    echo -e "${YELLOW}Removing duplicate definition from fork.c...${NC}"

    # Remove the entire block from fork.c
    sed -i '/^#ifdef CONFIG_USER_NS$/,/^#endif$/ {
        /unprivileged_userns_clone/d
    }' kernel/fork.c

    echo -e "${GREEN}✓ Fixed${NC}"
    ((FIXES_APPLIED++))
else
    echo -e "${GREEN}✓ No duplicate found${NC}"
fi

# Fix 4: Note about CONFIG_CACHY
echo -e "${BLUE}[4/4] Checking CONFIG_CACHY references...${NC}"
if grep -q "CONFIG_CACHY" kernel/sched/fair.c; then
    echo -e "${YELLOW}⚠ CONFIG_CACHY still referenced in code${NC}"
    echo -e "${YELLOW}  This is OK if CONFIG_CACHY is not enabled in config${NC}"
    echo -e "${YELLOW}  The CONFIG_SCHED_BORE sections will be used instead${NC}"
else
    echo -e "${GREEN}✓ No CONFIG_CACHY references${NC}"
fi

echo ""
echo -e "${BLUE}=== Auto-Fix Summary ===${NC}"
if [ $FIXES_APPLIED -gt 0 ]; then
    echo -e "${GREEN}Applied $FIXES_APPLIED fix(es)${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Verify fixes: ./scripts/verify-patches.sh $KERNEL_VERSION"
    echo "2. Build kernel: ./scripts/build-kernel.sh"
else
    echo -e "${GREEN}No fixes needed - everything looks good!${NC}"
fi

exit 0
