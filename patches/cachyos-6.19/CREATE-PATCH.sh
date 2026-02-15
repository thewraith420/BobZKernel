#!/bin/bash
# Script to create focused rseq timeslice patch from tglx tree

cd /home/bob/buildstuff/BobZKernel

# Key files that changed for rseq slice extension
FILES=(
    "init/Kconfig"
    "include/linux/rseq.h"
    "include/linux/rseq_entry.h"
    "include/linux/rseq_types.h"
    "include/linux/sched.h"
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

echo "Creating focused rseq timeslice patch..."

{
    echo "diff --git a/README b/README"
    echo "RSEQ Time Slice Extension for Linux 6.19"
    echo ""
    echo "Based on Thomas Gleixner's rseq/slice branch (v6.19-rc1)"
    echo "Source: git://git.kernel.org/pub/scm/linux/kernel/git/tglx/devel.git rseq/slice"
    echo ""
    
    for file in "${FILES[@]}"; do
        if [ -f "builds/linux-6.19/$file" ] && [ -f "patches/rseq-timeslice-v6-upstream/tglx-rseq-slice/$file" ]; then
            diff -u "builds/linux-6.19/$file" "patches/rseq-timeslice-v6-upstream/tglx-rseq-slice/$file"
        fi
    done
} > patches/cachyos-6.19/9002-rseq-timeslice-v6-native.patch

wc -l patches/cachyos-6.19/9002-rseq-timeslice-v6-native.patch
echo "Patch created!"
