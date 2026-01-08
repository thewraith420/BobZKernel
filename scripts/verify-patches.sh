#!/bin/bash
# Verify that patches were applied correctly and catch common issues
# Usage: ./verify-patches.sh [6.14|6.18]

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

echo -e "${BLUE}=== Patch Verification Script ===${NC}"
echo "Checking kernel source: $KERNEL_DIR"
echo ""

cd "$KERNEL_DIR"

ISSUES_FOUND=0

# Check 1: BORE scheduler - nsecs_per_tick definition
echo -e "${BLUE}[1/5] Checking BORE scheduler nsecs_per_tick...${NC}"
if grep -q "CONFIG_SCHED_BORE" .config 2>/dev/null || grep -q "CONFIG_SCHED_BORE=y" arch/x86/configs/* 2>/dev/null; then
    if grep -q "nsecs_per_tick.*=" kernel/sched/fair.c; then
        echo -e "${GREEN}✓ nsecs_per_tick defined${NC}"
    else
        echo -e "${RED}✗ ISSUE: nsecs_per_tick not defined in kernel/sched/fair.c${NC}"
        echo -e "${YELLOW}  Fix: Add 'static const unsigned int nsecs_per_tick = 1000000000ULL / HZ;'${NC}"
        ((ISSUES_FOUND++))
    fi
else
    echo -e "${YELLOW}⊘ BORE scheduler not enabled, skipping${NC}"
fi

# Check 2: BORE scheduler - sysctl_sched_min_base_slice
echo -e "${BLUE}[2/5] Checking BORE scheduler sysctl_sched_min_base_slice...${NC}"
if grep -q "CONFIG_SCHED_BORE" .config 2>/dev/null || grep -q "CONFIG_SCHED_BORE=y" arch/x86/configs/* 2>/dev/null; then
    if grep -q "sysctl_sched_min_base_slice" kernel/sched/fair.c; then
        echo -e "${GREEN}✓ sysctl_sched_min_base_slice referenced${NC}"

        # Check if it's actually defined
        if grep -q "^unsigned int sysctl_sched_min_base_slice" kernel/sched/fair.c; then
            echo -e "${GREEN}✓ sysctl_sched_min_base_slice defined${NC}"
        else
            echo -e "${RED}✗ ISSUE: sysctl_sched_min_base_slice used but not defined${NC}"
            echo -e "${YELLOW}  Fix: Add 'unsigned int sysctl_sched_min_base_slice = CONFIG_MIN_BASE_SLICE_NS;'${NC}"
            ((ISSUES_FOUND++))
        fi
    fi
else
    echo -e "${YELLOW}⊘ BORE scheduler not enabled, skipping${NC}"
fi

# Check 3: unprivileged_userns_clone duplicate definition
echo -e "${BLUE}[3/5] Checking for duplicate unprivileged_userns_clone...${NC}"
FORK_COUNT=$(grep -c "^int unprivileged_userns_clone\|^static int unprivileged_userns_clone" kernel/fork.c 2>/dev/null || true)
USERNS_COUNT=$(grep -c "^int unprivileged_userns_clone" kernel/user_namespace.c 2>/dev/null || true)

if [ "$FORK_COUNT" -gt 0 ] && [ "$USERNS_COUNT" -gt 0 ]; then
    echo -e "${RED}✗ ISSUE: unprivileged_userns_clone defined in BOTH fork.c and user_namespace.c${NC}"
    echo -e "${YELLOW}  Fix: Remove definition from kernel/fork.c (keep only in user_namespace.c)${NC}"
    ((ISSUES_FOUND++))
elif [ "$FORK_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Defined in fork.c only (unusual but may be OK)${NC}"
elif [ "$USERNS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Defined in user_namespace.c only (correct)${NC}"
else
    echo -e "${YELLOW}⊘ Not defined in either file${NC}"
fi

# Check 4: CONFIG_SCHED_BORE vs CONFIG_CACHY in fair.c
echo -e "${BLUE}[4/5] Checking scheduler config consistency...${NC}"
if grep -q "#ifdef CONFIG_CACHY" kernel/sched/fair.c; then
    if grep -q "CONFIG_SCHED_BORE=y" .config 2>/dev/null; then
        echo -e "${RED}✗ ISSUE: CONFIG_CACHY used in code but CONFIG_SCHED_BORE enabled${NC}"
        echo -e "${YELLOW}  Fix: Replace CONFIG_CACHY with CONFIG_SCHED_BORE in kernel/sched/fair.c${NC}"
        ((ISSUES_FOUND++))
    else
        echo -e "${YELLOW}⚠ CONFIG_CACHY found in code${NC}"
    fi
elif grep -q "#ifdef CONFIG_SCHED_BORE" kernel/sched/fair.c; then
    echo -e "${GREEN}✓ Using CONFIG_SCHED_BORE (correct)${NC}"
else
    echo -e "${YELLOW}⊘ Neither CONFIG_CACHY nor CONFIG_SCHED_BORE found${NC}"
fi

# Check 5: Verify config options are set
echo -e "${BLUE}[5/5] Checking kernel config options...${NC}"
if [ -f ".config" ]; then
    MISSING_OPTIONS=()

    # Check for key optimizations
    grep -q "CONFIG_X86_NATIVE_CPU=y" .config || MISSING_OPTIONS+=("CONFIG_X86_NATIVE_CPU")
    grep -q "CONFIG_LTO_CLANG_FULL=y" .config || MISSING_OPTIONS+=("CONFIG_LTO_CLANG_FULL")
    grep -q "CONFIG_HZ_1000=y" .config || MISSING_OPTIONS+=("CONFIG_HZ_1000")

    if [ ${#MISSING_OPTIONS[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ All key optimization options enabled${NC}"
    else
        echo -e "${YELLOW}⚠ Missing optimization options:${NC}"
        for opt in "${MISSING_OPTIONS[@]}"; do
            echo -e "  ${YELLOW}  - $opt${NC}"
        done
    fi
else
    echo -e "${YELLOW}⊘ .config not found (run make olddefconfig first)${NC}"
fi

echo ""
echo -e "${BLUE}=== Verification Summary ===${NC}"
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No issues found! Patches look good.${NC}"
    echo ""
    echo -e "${BLUE}Ready to build:${NC}"
    echo "  ./scripts/build-kernel.sh"
    exit 0
else
    echo -e "${RED}✗ Found $ISSUES_FOUND issue(s) that need fixing${NC}"
    echo ""
    echo -e "${YELLOW}Fix these issues before building, or the build will fail.${NC}"
    echo -e "${YELLOW}You can run this script again after making fixes.${NC}"
    exit 1
fi
