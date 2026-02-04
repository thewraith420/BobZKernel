// SPDX-License-Identifier: GPL-2.0+
/*
 * Realistic RSEQ Time Slice Extension Test
 *
 * This test creates realistic conditions where slice extensions would be granted:
 * - Multiple threads competing for CPU
 * - Triggers need_resched conditions
 * - Measures actual grant rates under load
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
#include <pthread.h>
#include <sched.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
# define PR_RSEQ_SLICE_EXTENSION_GET 1
# define PR_RSEQ_SLICE_EXTENSION_SET 2
# define PR_RSEQ_SLICE_EXT_ENABLE 0x01
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

struct test_stats {
    volatile unsigned long requests;
    volatile unsigned long grants;
    volatile unsigned long work_iterations;
};

static void *worker_thread(void *arg)
{
    struct test_stats *stats = (struct test_stats *)arg;
    int i;

    /* Enable slice extensions for this thread */
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) < 0) {
        perror("prctl failed in worker");
        return NULL;
    }

    for (i = 0; i < 10000; i++) {
        /* Clear previous state */
        __rseq_abi.slice_ctrl.all = 0;
        __asm__ __volatile__("" ::: "memory");

        /* Request slice extension */
        __rseq_abi.slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");

        __sync_fetch_and_add(&stats->requests, 1);

        /* Do some work to potentially trigger need_resched */
        for (volatile int j = 0; j < 10000; j++) {
            __sync_fetch_and_add(&stats->work_iterations, 1);
        }

        /* Check if granted */
        __asm__ __volatile__("" ::: "memory");
        if (__rseq_abi.slice_ctrl.granted) {
            __sync_fetch_and_add(&stats->grants, 1);
        }

        /* Yield to trigger scheduler */
        sched_yield();
    }

    return NULL;
}

int main(void)
{
    pthread_t threads[8];
    struct test_stats stats = {0};
    int i, num_cpus;

    printf("RSEQ Time Slice Extension - Realistic Test\n");
    printf("===========================================\n\n");

    if (!&__rseq_abi) {
        fprintf(stderr, "✗ glibc RSEQ not available\n");
        return 1;
    }

    /* Enable for main thread */
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) < 0) {
        perror("prctl failed");
        return 1;
    }

    printf("✓ Slice extension enabled\n");

    num_cpus = sysconf(_SC_NPROCESSORS_ONLN);
    printf("✓ System has %d CPUs\n", num_cpus);

    /* Create more threads than CPUs to force contention */
    int num_threads = num_cpus * 2;
    if (num_threads > 8) num_threads = 8;

    printf("✓ Creating %d worker threads...\n\n", num_threads);

    for (i = 0; i < num_threads; i++) {
        if (pthread_create(&threads[i], NULL, worker_thread, &stats) != 0) {
            perror("pthread_create");
            return 1;
        }
    }

    printf("Running test");
    fflush(stdout);

    /* Print progress */
    for (i = 0; i < 10; i++) {
        sleep(1);
        printf(".");
        fflush(stdout);
    }
    printf("\n\n");

    for (i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("Test Results:\n");
    printf("=============\n");
    printf("Total requests:      %lu\n", stats.requests);
    printf("Total grants:        %lu\n", stats.grants);
    printf("Work iterations:     %lu\n", stats.work_iterations);
    printf("Grant rate:          %.2f%%\n",
           stats.requests > 0 ? (stats.grants * 100.0) / stats.requests : 0.0);

    printf("\n");
    if (stats.grants > 0) {
        printf("✓ SUCCESS: RSEQ Time Slice Extension is WORKING!\n");
        printf("\n");
        printf("The kernel successfully granted %lu slice extensions.\n", stats.grants);
        printf("This confirms the backport is functional.\n");
        return 0;
    } else if (stats.requests > 0) {
        printf("⚠ PARTIAL: Requests made but no grants received\n");
        printf("\n");
        printf("This could mean:\n");
        printf("1. The kernel compiled without CONFIG_RSEQ_SLICE_EXTENSION=y\n");
        printf("2. The exit-to-user-mode loop isn't calling the grant function\n");
        printf("3. Test conditions don't trigger the grant logic\n");
        printf("\n");
        printf("Check: cat /proc/sys/kernel/rseq_slice_extension_nsec\n");
        return 1;
    } else {
        printf("✗ FAIL: No requests were made\n");
        return 1;
    }
}
