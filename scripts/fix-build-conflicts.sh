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

# Fix 3: Resolve rseq.c conflicts (keep theirs = patched version)
sed -i '/<<<<<<< ours/,/=======/{/<<<<<<< ours/d; /=======/d; d}' "$KERNEL_DIR/kernel/rseq.c"
sed -i '/>>>>>>> theirs/d' "$KERNEL_DIR/kernel/rseq.c"

# Fix 3.5: Resolve sys.c conflicts (RSEQ prctl)
sed -i '/<<<<<<< ours/,/>>>>>>> theirs/{/<<<<<<< ours/d; /=======/d; />>>>>>> theirs/d}' "$KERNEL_DIR/kernel/sys.c"

# Fix 4: Fix fair.c - remove duplicate unconditional migration_cost definition
# Only remove the standalone line: __read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;
# That appears BEFORE the CONFIG_CACHY ifdef block
sed -i '/^__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;$/d' "$KERNEL_DIR/kernel/sched/fair.c"

# Fix 5: Apply vruntime field name fixes (scheduler EEVDF vs BORE compatibility)
sed -i 's/cfs_rq->min_vruntime\([^_]\)/cfs_rq->zero_vruntime\1/g' "$KERNEL_DIR/kernel/sched/fair.c"
sed -i 's/cfs_rq->min_vruntime_fi\([^_]\)/cfs_rq->zero_vruntime_fi\1/g' "$KERNEL_DIR/kernel/sched/fair.c"

# Fix 10: Repair broken comment block around base_slice (prevents stray #endif)
perl -0777 -i -pe 's|/\*\n \* Minimal preemption granularity for CPU-bound tasks:\n#ifdef CONFIG_SCHED_BORE|/*\n * Minimal preemption granularity for CPU-bound tasks:\n *\n * BORE : base_slice = minimum multiple of nsecs_per_tick >= min_base_slice\n * (default min_base_slice = 2000000 constant, units: nanoseconds)\n * EEVDF: default 0.70 msec * (1 + ilog(ncpus)), units: nanoseconds\n */\n#ifdef CONFIG_SCHED_BORE|g' "$KERNEL_DIR/kernel/sched/fair.c"

# Fix 6: Remove merge conflict marker from bore.c
sed -i '/<<<<<<< ours/,/>>>>>>> theirs/{/<<<<<<< ours/d; /=======/d; />>>>>>> theirs/d}' "$KERNEL_DIR/kernel/sched/bore.c"

# Fix 7: Fix revocable.c - remove conflict markers and duplicate 'static'
sed -i '/<<<<<<< ours/,/>>>>>>> theirs/{/<<<<<<< ours/d; /=======/d; />>>>>>> theirs/d}' "$KERNEL_DIR/drivers/base/revocable.c"
# Also remove any stray partial conflict markers (=======, >>>>>>> theirs) left without <<<<<<< ours
sed -i '/^=======$/d' "$KERNEL_DIR/drivers/base/revocable.c"
sed -i '/^>>>>>>> theirs$/d' "$KERNEL_DIR/drivers/base/revocable.c"
sed -i 's/^static DEFINE_SRCU(revocable_srcu);$/DEFINE_SRCU(revocable_srcu);/' "$KERNEL_DIR/drivers/base/revocable.c"
# Remove any duplicate DEFINE_SRCU lines that may remain
awk '!seen[$0]++ || !/^DEFINE_SRCU\(revocable_srcu\);$/' "$KERNEL_DIR/drivers/base/revocable.c" > "$KERNEL_DIR/drivers/base/revocable.c.tmp" && mv "$KERNEL_DIR/drivers/base/revocable.c.tmp" "$KERNEL_DIR/drivers/base/revocable.c"

# Fix 8: Update hrtimer API in rseq.c (hrtimer_init → hrtimer_setup)
# If the old two-line pattern exists, convert it to new API
sed -i '/hrtimer_init(&st->timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);/{N;s/hrtimer_init(&st->timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);\n\t\tst->timer.function = rseq_slice_expired;/hrtimer_setup(\&st->timer, rseq_slice_expired, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);/}' "$KERNEL_DIR/kernel/rseq.c"
# If timer init is completely missing from the loop, add it with new API
if ! grep -q "hrtimer_setup.*st->timer" "$KERNEL_DIR/kernel/rseq.c"; then
    sed -i '/for_each_possible_cpu(cpu) {/{N;s|\(for_each_possible_cpu(cpu) {\)\n\([ \t]*struct slice_timer \*st = per_cpu_ptr(&slice_timer, cpu);\)|\1\n\2\n\t\thrtimer_setup(\&st->timer, rseq_slice_expired, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);|}' "$KERNEL_DIR/kernel/rseq.c"
fi

# Fix 9: Update sysctl registration API in rseq.c (register_sysctl → register_sysctl_init)
# Handle with or without leading tabs/spaces
sed -i 's/register_sysctl("kernel", rseq_slice_ext_sysctl);/register_sysctl_init("kernel", rseq_slice_ext_sysctl);/' "$KERNEL_DIR/kernel/rseq.c"
# If the register_sysctl_init line is completely missing, add it
if ! grep -q "register_sysctl_init.*rseq_slice_ext_sysctl" "$KERNEL_DIR/kernel/rseq.c"; then
    sed -i '/if (rseq_slice_extension_enabled())$/a\\t\tregister_sysctl_init("kernel", rseq_slice_ext_sysctl);' "$KERNEL_DIR/kernel/rseq.c"
fi

# Fix 11: Add missing #endif for CONFIG_RSEQ_SLICE_EXTENSION at end of rseq.c
if ! grep -q "^#endif /\* CONFIG_RSEQ_SLICE_EXTENSION \*/$" "$KERNEL_DIR/kernel/rseq.c"; then
    echo "" >> "$KERNEL_DIR/kernel/rseq.c"
    echo "#endif /* CONFIG_RSEQ_SLICE_EXTENSION */" >> "$KERNEL_DIR/kernel/rseq.c"
fi

# Fix 12: Remove empty terminator from sysctl array (register_sysctl_init uses ARRAY_SIZE)
# The empty {} causes validation errors because it's counted in ARRAY_SIZE and checked
# Uses -0777 to slurp whole file for multi-line match; braces escaped to avoid regex error
perl -0777 -i -pe 's/\t\},\n\t\{\}\n\};/\t}\n};/g' "$KERNEL_DIR/kernel/rseq.c"

echo "✓ Build conflicts fixed"
