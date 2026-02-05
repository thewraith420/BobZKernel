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

# Fix 6: Remove merge conflict marker from bore.c
sed -i '/<<<<<<< ours/,/>>>>>>> theirs/{/<<<<<<< ours/d; /=======/d; />>>>>>> theirs/d}' "$KERNEL_DIR/kernel/sched/bore.c"

# Fix 7: Remove duplicate 'static' from revocable.c (DEFINE_SRCU already includes static)
sed -i 's/^static DEFINE_SRCU(revocable_srcu);$/DEFINE_SRCU(revocable_srcu);/' "$KERNEL_DIR/drivers/base/revocable.c"

# Fix 8: Update hrtimer API in rseq.c (hrtimer_init → hrtimer_setup)
sed -i '/hrtimer_init(&st->timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);/{N;s/hrtimer_init(&st->timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);\n\t\tst->timer.function = rseq_slice_expired;/hrtimer_setup(\&st->timer, rseq_slice_expired, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);/}' "$KERNEL_DIR/kernel/rseq.c"

# Fix 9: Update sysctl registration API in rseq.c (register_sysctl → register_sysctl_init)
sed -i 's/register_sysctl("kernel", rseq_slice_ext_sysctl);/register_sysctl_init("kernel", rseq_slice_ext_sysctl);/' "$KERNEL_DIR/kernel/rseq.c"

echo "✓ Build conflicts fixed"
