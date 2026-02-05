#!/bin/bash
# Apply CachyOS patches to kernel source
# Usage: ./apply-patches.sh [6.14|6.18] [--continue-on-failure] [--force]

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="${1:-6.18}"
CONTINUE_ON_FAILURE=false
FORCE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        6.14|6.18)
            KERNEL_VERSION="$arg"
            ;;
        --continue-on-failure)
            CONTINUE_ON_FAILURE=true
            ;;
        --force)
            FORCE=true
            ;;
    esac
done

if [ "$KERNEL_VERSION" != "6.14" ] && [ "$KERNEL_VERSION" != "6.18" ]; then
    echo -e "${RED}Error: Please specify kernel version (6.14 or 6.18)${NC}"
    echo "Usage: $0 [6.14|6.18] [--continue-on-failure] [--force]"
    exit 1
fi

KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"
PATCH_DIR="$BASE_DIR/patches/cachyos-$KERNEL_VERSION"
PATCH_CONFIG="$BASE_DIR/patches/patch-config.sh"

echo -e "${BLUE}=== CachyOS Patch Application Script ===${NC}"
echo "Kernel: $KERNEL_VERSION"
echo "Source: $KERNEL_DIR"
echo "Patches: $PATCH_DIR"
echo "Continue on failure: $CONTINUE_ON_FAILURE"
echo ""

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: Kernel directory not found: $KERNEL_DIR${NC}"
    exit 1
fi

# Check if patch directory exists
if [ ! -d "$PATCH_DIR" ]; then
    echo -e "${RED}Error: Patch directory not found: $PATCH_DIR${NC}"
    exit 1
fi

cd "$KERNEL_DIR"

# First, apply numbered patches from root patches directory
echo -e "${BLUE}=== Applying numbered patches from root patches directory ===${NC}"
NUMBERED_PATCH_COUNT=0
for patch in "$BASE_DIR/patches"/000[1-9]-*.patch; do
    if [ -f "$patch" ]; then
        PATCH_NAME=$(basename "$patch")
        echo -e "${BLUE}Applying: $PATCH_NAME${NC}"
        if git apply --check "$patch" 2>/dev/null; then
            git apply "$patch"
            echo -e "${GREEN}✓ Applied cleanly${NC}"
            ((NUMBERED_PATCH_COUNT++))
        else
            echo -e "${YELLOW}⊘ Patch already applied or conflicts exist, skipping${NC}"
        fi
    fi
done
echo "Applied $NUMBERED_PATCH_COUNT numbered patches"
echo ""

# Check if there are uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    if [ "$FORCE" = true ]; then
        echo -e "${YELLOW}Warning: Uncommitted changes detected - committing automatically${NC}"
        git add -A
        git commit -m "Auto-commit before applying patches" || true
    else
        echo -e "${YELLOW}Warning: You have uncommitted changes in the kernel tree${NC}"
        echo -e "${YELLOW}Patches may not apply cleanly. Consider using --force to auto-commit.${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Load patch configuration if it exists
if [ -f "$PATCH_CONFIG" ]; then
    source "$PATCH_CONFIG"
    PATCHES_TO_APPLY=($(get_patches_for_version "$KERNEL_VERSION"))
    echo -e "${BLUE}Using patch configuration from patch-config.sh${NC}"
    echo "Patches configured: ${#PATCHES_TO_APPLY[@]}"
    echo ""
else
    # Fallback: apply all patches in directory
    echo -e "${YELLOW}No patch configuration found, applying all patches in order${NC}"
    PATCHES_TO_APPLY=()
    for patch in "$PATCH_DIR"/*.patch; do
        if [ -f "$patch" ]; then
            PATCHES_TO_APPLY+=("$(basename "$patch"):optional")
        fi
    done
fi

# Apply patches in order
PATCH_COUNT=0
FAILED_PATCHES=()
SKIPPED_PATCHES=()

for patch_entry in "${PATCHES_TO_APPLY[@]}"; do
    # Parse patch entry (format: "filename:priority")
    PATCH_FILE="${patch_entry%%:*}"
    PRIORITY="${patch_entry##*:}"
    PATCH_PATH="$PATCH_DIR/$PATCH_FILE"
    
    # Skip if patch file doesn't exist
    if [ ! -f "$PATCH_PATH" ]; then
        echo -e "${YELLOW}⊘ Skipping: $PATCH_FILE (not found)${NC}"
        SKIPPED_PATCHES+=("$PATCH_FILE (not found)")
        continue
    fi

    # Skip if marked as skip in config
    if [ "$PRIORITY" = "skip" ]; then
        echo -e "${YELLOW}⊘ Skipping: $PATCH_FILE (configured to skip)${NC}"
        SKIPPED_PATCHES+=("$PATCH_FILE (configured)")
        continue
    fi

    echo -e "${BLUE}Applying: $PATCH_FILE [$PRIORITY]${NC}"

    # Try to apply the patch
    if git apply --check "$PATCH_PATH" 2>&1 | grep -q "error:"; then
        echo -e "${YELLOW}⚠ Direct apply failed, trying 3-way merge...${NC}"
        
        # Try with 3-way merge
        if git apply --3way "$PATCH_PATH" 2>&1; then
            echo -e "${GREEN}✓ Applied with 3-way merge${NC}"
            ((PATCH_COUNT++))
        else
            echo -e "${RED}✗ 3-way merge also failed${NC}"
            
            if [ "$PRIORITY" = "required" ]; then
                echo -e "${RED}ERROR: Required patch failed!${NC}"
                FAILED_PATCHES+=("$PATCH_FILE (required)")
                if [ "$CONTINUE_ON_FAILURE" = false ]; then
                    echo -e "${RED}Aborting due to required patch failure${NC}"
                    echo "Use --continue-on-failure to skip failed patches"
                    exit 1
                fi
            else
                echo -e "${YELLOW}⊘ Skipping optional patch${NC}"
                SKIPPED_PATCHES+=("$PATCH_FILE (conflicts)")
            fi
        fi
    else
        # Apply cleanly
        git apply "$PATCH_PATH"
        echo -e "${GREEN}✓ Applied cleanly${NC}"
        ((PATCH_COUNT++))
    fi
    echo ""
done

echo -e "${BLUE}=== Patch Application Summary ===${NC}"
echo "Successfully applied: $PATCH_COUNT patches"

if [ ${#SKIPPED_PATCHES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped patches: ${#SKIPPED_PATCHES[@]}${NC}"
    for skipped in "${SKIPPED_PATCHES[@]}"; do
        echo -e "  ${YELLOW}⊘ $skipped${NC}"
    done
fi

if [ ${#FAILED_PATCHES[@]} -gt 0 ]; then
    echo -e "${RED}Failed required patches: ${#FAILED_PATCHES[@]}${NC}"
    for failed in "${FAILED_PATCHES[@]}"; do
        echo -e "  ${RED}✗ $failed${NC}"
    done
    echo ""
    echo -e "${RED}CRITICAL: Required patches failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Patch application complete!${NC}"
echo ""

# Fix known BORE/CachyOS conflict in kernel/sched/fair.c
FAIR_C="$KERNEL_DIR/kernel/sched/fair.c"
if grep -q "<<<<<<" "$FAIR_C" 2>/dev/null; then
    echo -e "${YELLOW}Fixing known BORE patch conflict in fair.c...${NC}"
    # Remove conflict markers and keep BORE version
    sed -i '/^<<<<<<< ours$/,/^>>>>>>> theirs$/c\
#ifdef CONFIG_SCHED_BORE\
static const unsigned int nsecs_per_tick = 1000000000ULL / HZ;\
unsigned int sysctl_sched_min_base_slice = CONFIG_MIN_BASE_SLICE_NS;\
__read_mostly uint sysctl_sched_base_slice = nsecs_per_tick;\
#else /* !CONFIG_SCHED_BORE */\
unsigned int sysctl_sched_base_slice = 700000ULL;\
static unsigned int normalized_sysctl_sched_base_slice = 700000ULL;\
#endif /* CONFIG_SCHED_BORE */\
\
__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;' "$FAIR_C"
    echo -e "${GREEN}✓ BORE conflict auto-resolved${NC}"
fi

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Build kernel: ./scripts/build-kernel.sh $KERNEL_VERSION"

