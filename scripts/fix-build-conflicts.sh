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
# First conflict: use hrtimer_init version
sed -i '833,838{/<<<<<<< ours/,/=======/d; />>>>>>> theirs/d}' "$KERNEL_DIR/kernel/rseq.c"
# Second conflict: keep the stub syscall
sed -i '845,859{/<<<<<<< ours/d; /=======.*/,/>>>>>>> theirs/d}' "$KERNEL_DIR/kernel/rseq.c"

# Fix 4: Fix fair.c - broken comment and duplicate migration_cost
sed -i '84{s|^/\*$|/*\n * Minimal preemption granularity for CPU-bound tasks:\n * BORE : base_slice = minimum multiple of nsecs_per_tick >= min_base_slice\n * (default min_base_slice = 2000000 constant, units: nanoseconds)\n * EEVDF: default 0.70 msec * (1 + ilog(ncpus)), units: nanoseconds\n */|}' "$KERNEL_DIR/kernel/sched/fair.c"
# Remove the incomplete comment line
sed -i '/^ \* Minimal preemption granularity for CPU-bound tasks:$/,/^#ifdef CONFIG_SCHED_BORE$/{/^ \* Minimal preemption granularity for CPU-bound tasks:$/d; /^#ifdef CONFIG_SCHED_BORE$/!d}' "$KERNEL_DIR/kernel/sched/fair.c"
# Remove duplicate migration_cost
sed -i '/^__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;$/d' "$KERNEL_DIR/kernel/sched/fair.c"

# Fix 5: Apply vruntime field name fixes
sed -i 's/cfs_rq->min_vruntime\([^_]\)/cfs_rq->zero_vruntime\1/g' "$KERNEL_DIR/kernel/sched/fair.c"
sed -i 's/cfs_rq->min_vruntime_fi\([^_]\)/cfs_rq->zero_vruntime_fi\1/g' "$KERNEL_DIR/kernel/sched/fair.c"

echo "✓ Build conflicts fixed"
