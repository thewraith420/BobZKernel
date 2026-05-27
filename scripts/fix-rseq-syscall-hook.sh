#!/bin/bash
# Auto-fix for RSEQ syscall work hook
# This fixes the syscall-common.c changes that may fail to apply due to version differences

set -e

KERNEL_DIR="${1:-/home/bob/buildstuff/BobZKernel/builds/linux-6.19}"
SYSCALL_FILE="$KERNEL_DIR/kernel/entry/syscall-common.c"

echo "Checking RSEQ syscall work hook in $SYSCALL_FILE..."

# Check if the hook is already present
if grep -q "rseq_syscall_enter_work" "$SYSCALL_FILE"; then
    echo "✓ RSEQ syscall work hook already present"
    exit 0
fi

echo "✗ RSEQ syscall work hook missing - applying fix..."

# Check if rseq.h include is present
if ! grep -q '#include <linux/rseq.h>' "$SYSCALL_FILE"; then
    echo "  Adding #include <linux/rseq.h>..."
    sed -i '/#include <linux\/entry-common.h>/a #include <linux/rseq.h>' "$SYSCALL_FILE"
fi

# Add the syscall work hook after syscall_enter_audit
if grep -q "syscall_enter_audit(regs, syscall);" "$SYSCALL_FILE"; then
    echo "  Adding RSEQ syscall work hook..."
    sed -i '/syscall_enter_audit(regs, syscall);/a \\n\t/* Handle RSEQ slice extension work */\n\tif (work \& SYSCALL_WORK_SYSCALL_RSEQ_SLICE)\n\t\trseq_syscall_enter_work(syscall);' "$SYSCALL_FILE"
else
    echo "ERROR: Could not find syscall_enter_audit line to patch"
    exit 1
fi

# Verify the fix was applied
if grep -q "rseq_syscall_enter_work" "$SYSCALL_FILE"; then
    echo "✓ RSEQ syscall work hook successfully applied"
    exit 0
else
    echo "ERROR: Fix application failed"
    exit 1
fi
