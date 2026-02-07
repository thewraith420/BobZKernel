// SPDX-License-Identifier: GPL-2.0+
/*
 * Force RSEQ Grant Test
 *
 * This test tries to force the exact conditions needed for a grant:
 * - Use proper TLS access via __rseq_offset (not __rseq_abi directly)
 * - Set request flag
 * - Do CPU-bound work to trigger actual preemption (need_resched)
 * - Check if grant happened
 *
 * Key insight: Grants only happen when the scheduler WANTS to preempt
 * the task (sets _TIF_NEED_RESCHED), not when the task voluntarily yields.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <errno.h>
#include <sched.h>
#include <time.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_GET 1
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

#ifndef __NR_rseq_slice_yield
#define __NR_rseq_slice_yield 470
#endif

struct rseq_slice_ctrl {
    union {
        uint32_t all;
        struct {
            uint8_t request;
            uint8_t granted;
            uint16_t __reserved;
        };
    };
};

struct rseq {
    uint32_t cpu_id_start;
    uint32_t cpu_id;
    uint64_t rseq_cs;
    uint32_t flags;
    uint32_t node_id;
    uint32_t mm_cid;
    struct rseq_slice_ctrl slice_ctrl;
} __attribute__((aligned(32)));

/* Use __rseq_offset to properly locate RSEQ struct in TLS */
extern ptrdiff_t __rseq_offset __attribute__((weak));

static struct rseq *get_rseq(void)
{
    char *tls_base;
    asm("mov %%fs:0, %0" : "=r"(tls_base));
    return (struct rseq *)(tls_base + __rseq_offset);
}

static int test_with_syscall(struct rseq *r, const char *syscall_name, long syscall_num)
{
    int granted_before, granted_after;

    /* Clear state */
    r->slice_ctrl.all = 0;
    __asm__ __volatile__("" ::: "memory");

    /* Set request */
    r->slice_ctrl.request = 1;
    __asm__ __volatile__("" ::: "memory");

    granted_before = r->slice_ctrl.granted;

    /* Make syscall to trigger exit-to-user-mode */
    if (syscall_num == __NR_rseq_slice_yield) {
        syscall(__NR_rseq_slice_yield);
    } else if (syscall_num == __NR_sched_yield) {
        sched_yield();
    } else {
        syscall(syscall_num);
    }

    /* Check grant after syscall */
    __asm__ __volatile__("" ::: "memory");
    granted_after = r->slice_ctrl.granted;

    printf("  %-20s: request=%d, granted_before=%d, granted_after=%d",
           syscall_name,
           r->slice_ctrl.request,
           granted_before,
           granted_after);

    if (granted_after) {
        printf(" ✓ GRANT!\n");
        r->slice_ctrl.granted = 0;  /* Clear for next test */
        return 1;
    } else {
        printf(" ✗\n");
        return 0;
    }
}

static int test_sched_yield_loop(struct rseq *r)
{
    int grants = 0;

    printf("\n[2] sched_yield loop (1000 iterations)...\n");
    printf("    Note: sched_yield rarely triggers grants (voluntary yield)\n");

    for (int i = 0; i < 1000; i++) {
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");

        sched_yield();

        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants++;
            r->slice_ctrl.granted = 0;
        }
    }

    printf("  Grants: %d / 1000 (%.1f%%)\n", grants, grants / 10.0);
    return grants;
}

static int test_cpu_bound_work(struct rseq *r, int duration_sec)
{
    int grants = 0;
    volatile unsigned long counter = 0;
    time_t start = time(NULL);

    printf("\n[3] CPU-bound work to trigger preemption (%d second%s)...\n",
           duration_sec, duration_sec > 1 ? "s" : "");
    printf("    This is where grants SHOULD happen (scheduler preemption)\n");

    while (time(NULL) - start < duration_sec) {
        r->slice_ctrl.request = 1;

        /* Do some CPU work */
        for (int j = 0; j < 10000; j++) {
            counter++;
        }

        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants++;
            r->slice_ctrl.granted = 0;
        }
    }

    printf("  Grants: %d (iterations=%lu)\n", grants, counter);
    return grants;
}

static int test_getpid_spam(struct rseq *r)
{
    int grants = 0;

    printf("\n[4] getpid() syscall spam (10000 iterations)...\n");
    printf("    Note: Lightweight syscalls rarely trigger preemption\n");

    for (int i = 0; i < 10000; i++) {
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");

        getpid();

        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants++;
            r->slice_ctrl.granted = 0;
        }
    }

    printf("  Grants: %d / 10000 (%.2f%%)\n", grants, grants / 100.0);
    return grants;
}

int main(void)
{
    struct rseq *r;
    int total_grants = 0;
    int rc;

    printf("RSEQ Time Slice Extension - Force Grant Test\n");
    printf("==============================================\n\n");

    /* Check for __rseq_offset availability */
    if (!&__rseq_offset) {
        fprintf(stderr, "✗ glibc RSEQ offset not available\n");
        return 1;
    }

    /* Get proper RSEQ struct pointer via TLS offset */
    r = get_rseq();

    printf("RSEQ struct at: %p (via __rseq_offset=%td)\n", (void *)r, __rseq_offset);
    printf("  cpu_id: %u\n", r->cpu_id);
    printf("  flags: 0x%x\n", r->flags);
    printf("  slice_ctrl offset: %zu\n\n", offsetof(struct rseq, slice_ctrl));

    /* Enable slice extensions */
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
               PR_RSEQ_SLICE_EXT_ENABLE, 0, 0);
    if (rc < 0) {
        perror("prctl failed to enable slice extension");
        return 1;
    }

    printf("✓ Slice extension enabled\n");
    printf("  flags after enable: 0x%x\n", r->flags);
    printf("  SLICE_EXT_AVAILABLE (0x10): %s\n", (r->flags & 0x10) ? "YES" : "NO");
    printf("  SLICE_EXT_ENABLED (0x20): %s\n\n", (r->flags & 0x20) ? "YES" : "NO");

    printf("[1] Testing with various syscalls:\n");
    total_grants += test_with_syscall(r, "rseq_slice_yield", __NR_rseq_slice_yield);
    total_grants += test_with_syscall(r, "sched_yield", __NR_sched_yield);
    total_grants += test_with_syscall(r, "getpid", __NR_getpid);
    total_grants += test_with_syscall(r, "gettid", __NR_gettid);

    total_grants += test_sched_yield_loop(r);
    total_grants += test_cpu_bound_work(r, 2);  /* 2 seconds of CPU work */
    total_grants += test_getpid_spam(r);

    printf("\n==============================================\n");
    if (total_grants > 0) {
        printf("✓✓✓ SUCCESS! Got %d grants total!\n", total_grants);
        printf("\nRSEQ Time Slice Extension IS WORKING!\n");
        printf("The kernel grant logic is functional.\n");
        return 0;
    } else {
        printf("✗✗✗ FAIL: No grants received (%d total)\n", total_grants);
        printf("\nPossible issues:\n");
        printf("1. Grant logic not being called in exit-to-user-mode\n");
        printf("2. Conditions for grant not being met\n");
        printf("3. Bug in grant implementation\n");
        printf("\nDebugging steps:\n");
        printf("- Check kernel logs: dmesg | grep -i rseq\n");
        printf("- Verify grant function exists: sudo grep rseq_grant /proc/kallsyms\n");
        printf("- Check sysctl: cat /proc/sys/kernel/rseq_slice_extension_nsec\n");
        return 1;
    }
}
