#!/bin/bash
# Manually fix merge conflicts and issues after patch application

KERNEL_DIR="${1:-/home/bob/buildstuff/BobZKernel/builds/linux-6.18}"

echo "Fixing build conflicts in $KERNEL_DIR..."

# Fix 1: Resolve init/Kconfig conflict markers
sed -i '/<<<<<<< ours/,/=======/{/<<<<<<< ours/d; /=======/d}' "$KERNEL_DIR/init/Kconfig"
sed -i '/>>>>>>> theirs/d' "$KERNEL_DIR/init/Kconfig"

# Fix 2: Resolve thread_info.h conflict markers (use theirs - better alignment)
sed -i '/<<<<<<< ours/,/=======/{/<<<<<<< ours/d; /=======/d; d}' "$KERNEL_DIR/include/linux/thread_info.h"
sed -i '/>>>>>>> theirs/d' "$KERNEL_DIR/include/linux/thread_info.h"

# Fix 3: Resolve rseq.c conflicts
sed -i '/<<<<<<< ours/,/>>>>>>> theirs/d' "$KERNEL_DIR/kernel/rseq.c"

# Fix 4: Fix fair.c - remove duplicate unconditional migration_cost definition
# Only remove the standalone line: __read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;
# That appears BEFORE the CONFIG_CACHY ifdef block
sed -i '/^__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;$/d' "$KERNEL_DIR/kernel/sched/fair.c"

# Fix 5: Apply vruntime field name fixes (scheduler EEVDF vs BORE compatibility)
sed -i 's/cfs_rq->min_vruntime\([^_]\)/cfs_rq->zero_vruntime\1/g' "$KERNEL_DIR/kernel/sched/fair.c"
sed -i 's/cfs_rq->min_vruntime_fi\([^_]\)/cfs_rq->zero_vruntime_fi\1/g' "$KERNEL_DIR/kernel/sched/fair.c"

echo "✓ Build conflicts fixed"
