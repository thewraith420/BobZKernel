#!/bin/bash
# Create rseq-only patch, excluding scheduler internals

cd /home/bob/buildstuff/BobZKernel

# Only rseq-specific files, NO kernel/sched/* changes
FILES=(
    "init/Kconfig"
    "include/linux/rseq.h"
    "include/linux/rseq_entry.h"
    "include/linux/rseq_types.h"
    "include/linux/syscalls.h"
    "include/linux/thread_info.h"
    "include/uapi/linux/prctl.h"
    "arch/x86/entry/syscalls/syscall_32.tbl"
    "arch/x86/entry/syscalls/syscall_64.tbl"
    "include/uapi/asm-generic/unistd.h"
    "kernel/rseq.c"
    "kernel/sys.c"
    "kernel/sys_ni.c"
    "kernel/entry/common.c"
    "kernel/entry/syscall-common.c"
    "Documentation/admin-guide/kernel-parameters.txt"
    "Documentation/admin-guide/sysctl/kernel.rst"
)

{
    for file in "${FILES[@]}"; do
        if [ -f "builds/linux-6.19/$file" ] && [ -f "patches/rseq-timeslice-v6-upstream/tglx-rseq-slice/$file" ]; then
            diff -u "builds/linux-6.19/$file" "patches/rseq-timeslice-v6-upstream/tglx-rseq-slice/$file" | \
            sed "s|builds/linux-6.19/|a/|g; s|patches/rseq-timeslice-v6-upstream/tglx-rseq-slice/|b/|g"
        fi
    done
} > patches/cachyos-6.19/9002-rseq-timeslice-v6-clean.patch

wc -l patches/cachyos-6.19/9002-rseq-timeslice-v6-clean.patch
echo "Clean rseq-only patch created (no scheduler changes)"
