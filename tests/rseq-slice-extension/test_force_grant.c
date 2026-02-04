// SPDX-License-Identifier: GPL-2.0+
/*
 * Force RSEQ Grant Test
 *
 * This test tries to force the exact conditions needed for a grant:
 * - Set request flag
 * - Trigger syscall (forces exit-to-user-mode path)
 * - Check if grant happened
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <errno.h>
#include <sched.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
# define PR_RSEQ_SLICE_EXTENSION_GET 1
# define PR_RSEQ_SLICE_EXTENSION_SET 2
# define PR_RSEQ_SLICE_EXT_ENABLE 0x01
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
    char end[];
} __attribute__((aligned(32)));

extern __thread struct rseq __rseq_abi __attribute__((weak));

static int test_with_syscall(const char *syscall_name, long syscall_num)
{
    int granted_before, granted_after;

    /* Clear state */
    __rseq_abi.slice_ctrl.all = 0;
    __asm__ __volatile__("" ::: "memory");

    /* Set request */
    __rseq_abi.slice_ctrl.request = 1;
    __asm__ __volatile__("" ::: "memory");

    granted_before = __rseq_abi.slice_ctrl.granted;

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
    granted_after = __rseq_abi.slice_ctrl.granted;

    printf("  %-20s: request=%d, granted_before=%d, granted_after=%d",
           syscall_name,
           __rseq_abi.slice_ctrl.request,
           granted_before,
           granted_after);

    if (granted_after) {
        printf(" ✓ GRANT!\n");
        return 1;
    } else {
        printf(" ✗\n");
        return 0;
    }
}

static int test_tight_loop(void)
{
    int grants = 0;
    int i;

    printf("\n[3] Tight loop with sched_yield (1000 iterations)...\n");

    for (i = 0; i < 1000; i++) {
        __rseq_abi.slice_ctrl.all = 0;
        __asm__ __volatile__("" ::: "memory");

        __rseq_abi.slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");

        /* Force reschedule */
        sched_yield();

        __asm__ __volatile__("" ::: "memory");
        if (__rseq_abi.slice_ctrl.granted) {
            grants++;
        }
    }

    printf("  Grants: %d / 1000 (%.1f%%)\n", grants, grants / 10.0);
    return grants;
}

static int test_getpid_spam(void)
{
    int grants = 0;
    int i;

    printf("\n[4] Spam getpid() syscall (10000 iterations)...\n");

    for (i = 0; i < 10000; i++) {
        __rseq_abi.slice_ctrl.all = 0;
        __rseq_abi.slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");

        getpid();  /* Lightweight syscall */

        __asm__ __volatile__("" ::: "memory");
        if (__rseq_abi.slice_ctrl.granted) {
            grants++;
        }
    }

    printf("  Grants: %d / 10000 (%.2f%%)\n", grants, grants / 100.0);
    return grants;
}

int main(void)
{
    int total_grants = 0;

    printf("RSEQ Time Slice Extension - Force Grant Test\n");
    printf("==============================================\n\n");

    if (!&__rseq_abi) {
        fprintf(stderr, "✗ glibc RSEQ not available\n");
        return 1;
    }

    /* Enable slice extensions */
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) < 0) {
        perror("prctl failed");
        return 1;
    }

    printf("✓ Slice extension enabled\n");
    printf("✓ RSEQ ABI at: %p\n", (void *)&__rseq_abi);
    printf("✓ Current CPU: %u\n\n", __rseq_abi.cpu_id);

    printf("[1] Testing with various syscalls:\n");
    total_grants += test_with_syscall("rseq_slice_yield", __NR_rseq_slice_yield);
    total_grants += test_with_syscall("sched_yield", __NR_sched_yield);
    total_grants += test_with_syscall("getpid", __NR_getpid);
    total_grants += test_with_syscall("gettid", __NR_gettid);

    printf("\n[2] Testing request -> syscall -> check pattern:\n");
    for (int i = 0; i < 10; i++) {
        total_grants += test_with_syscall("sched_yield", __NR_sched_yield);
    }

    total_grants += test_tight_loop();
    total_grants += test_getpid_spam();

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
        printf("- Add printk to rseq_grant_slice_extension() to see if it's called\n");
        return 1;
    }
}
