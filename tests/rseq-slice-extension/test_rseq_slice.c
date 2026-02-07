// SPDX-License-Identifier: GPL-2.0+
/*
 * RSEQ Time Slice Extension Test
 *
 * This test validates the RSEQ time slice extension feature by:
 * 1. Registering with RSEQ
 * 2. Enabling slice extensions via prctl
 * 3. Requesting and verifying slice extension grants
 * 4. Testing that extensions work under load
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
#include <time.h>
#include <sched.h>
#include <pthread.h>

/* RSEQ constants from include/uapi/linux/rseq.h */
#define RSEQ_CPU_ID_UNINITIALIZED        (-1)
#define RSEQ_CPU_ID_REGISTRATION_FAILED  (-2)
#define RSEQ_FLAG_UNREGISTER (1 << 0)

#ifndef __NR_rseq
#define __NR_rseq 334
#endif

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

/* RSEQ structure from include/uapi/linux/rseq.h */
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

struct rseq_cs {
    uint32_t version;
    uint32_t flags;
    uint64_t start_ip;
    uint64_t post_commit_offset;
    uint64_t abort_ip;
} __attribute__((aligned(32)));

struct rseq {
    uint32_t cpu_id_start;
    uint32_t cpu_id;
    uint64_t rseq_cs;
    uint32_t flags;
    uint32_t node_id;
    uint32_t mm_cid;
    struct rseq_slice_ctrl slice_ctrl;
    uint8_t end[];
} __attribute__((aligned(32)));

/* Use __rseq_offset to properly locate RSEQ struct in TLS */
extern ptrdiff_t __rseq_offset __attribute__((weak));

static struct rseq *get_rseq(void)
{
    char *tls_base;
    asm("mov %%fs:0, %0" : "=r"(tls_base));
    return (struct rseq *)(tls_base + __rseq_offset);
}

/* Thread-local pointer to RSEQ struct */
static __thread volatile struct rseq *__rseq_abi_ptr = NULL;

/* Statistics */
struct test_stats {
    unsigned long requests;
    unsigned long grants;
    unsigned long denials;
    unsigned long iterations;
};

static int rseq_register(void)
{
    /* Check if glibc provides __rseq_offset */
    if (!&__rseq_offset) {
        printf("glibc RSEQ offset not available\n");
        return -1;
    }

    __rseq_abi_ptr = get_rseq();
    printf("Using glibc's RSEQ via __rseq_offset=%td\n", __rseq_offset);
    printf("RSEQ struct at: %p\n", (void *)__rseq_abi_ptr);

    if (__rseq_abi_ptr->cpu_id == RSEQ_CPU_ID_REGISTRATION_FAILED) {
        printf("RSEQ registration failed by glibc\n");
        return -1;
    }

    printf("RSEQ registered by glibc (cpu_id=%u)\n", __rseq_abi_ptr->cpu_id);
    return 0;
}

static int rseq_unregister(void)
{
    /* Don't unregister - glibc manages it */
    return 0;
}

static int enable_slice_extension(void)
{
    int rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
                   PR_RSEQ_SLICE_EXT_ENABLE, 0, 0);
    if (rc < 0) {
        perror("prctl(PR_RSEQ_SLICE_EXTENSION) failed");
        return -1;
    }

    printf("Slice extension enabled via prctl\n");
    return 0;
}

static inline void request_slice_extension(void)
{
    __rseq_abi_ptr->slice_ctrl.request = 1;
    __asm__ __volatile__("" ::: "memory");
}

static inline int check_grant(void)
{
    __asm__ __volatile__("" ::: "memory");
    return __rseq_abi_ptr->slice_ctrl.granted;
}

static inline void clear_request(void)
{
    __rseq_abi_ptr->slice_ctrl.all = 0;
    __asm__ __volatile__("" ::: "memory");
}

/* Test 1: Basic grant functionality with CPU-bound work */
static int test_basic_grant(void)
{
    int grants = 0;
    volatile unsigned long counter = 0;
    time_t start;

    printf("\n=== Test 1: Basic Grant Functionality (CPU-bound) ===\n");

    start = time(NULL);
    while (time(NULL) - start < 1) {
        clear_request();
        request_slice_extension();

        /* CPU-bound work to trigger actual preemption */
        for (int j = 0; j < 10000; j++) {
            counter++;
        }

        __asm__ __volatile__("" ::: "memory");
        if (check_grant()) {
            grants++;
            __rseq_abi_ptr->slice_ctrl.granted = 0;
        }
    }

    printf("  Iterations: %lu, Grants: %d\n", counter, grants);
    if (grants > 0) {
        printf("✓ Slice extension granted (%d times)\n", grants);
        return 0;
    } else {
        printf("✗ Slice extension NOT granted (may need more CPU contention)\n");
        return -1;
    }
}

/* Test 2: Multiple requests with CPU-bound work */
static int test_multiple_requests(struct test_stats *stats)
{
    volatile unsigned long counter = 0;
    time_t start;

    printf("\n=== Test 2: Multiple Requests (2 seconds CPU-bound) ===\n");

    memset(stats, 0, sizeof(*stats));

    start = time(NULL);
    while (time(NULL) - start < 2) {
        clear_request();
        request_slice_extension();
        stats->requests++;

        /* CPU-bound work to trigger actual preemption */
        for (int j = 0; j < 10000; j++) {
            counter++;
        }

        __asm__ __volatile__("" ::: "memory");
        if (check_grant()) {
            stats->grants++;
            __rseq_abi_ptr->slice_ctrl.granted = 0;
        } else {
            stats->denials++;
        }
        stats->iterations++;
    }

    printf("Requests: %lu, Grants: %lu, Denials: %lu\n",
           stats->requests, stats->grants, stats->denials);
    printf("Grant rate: %.2f%%\n",
           stats->requests > 0 ? (stats->grants * 100.0) / stats->requests : 0.0);

    if (stats->grants > 0) {
        printf("✓ Multiple grants working\n");
        return 0;
    } else {
        printf("✗ No grants received\n");
        return -1;
    }
}

/* Test 3: Stress test with CPU work */
static void *stress_worker(void *arg)
{
    struct test_stats *stats = (struct test_stats *)arg;
    volatile unsigned long counter = 0;
    time_t start;
    struct rseq *r;

    /* Get RSEQ pointer for this thread */
    r = get_rseq();

    if (enable_slice_extension() < 0)
        return NULL;

    /* Run CPU-bound work for 2 seconds */
    start = time(NULL);
    while (time(NULL) - start < 2) {
        r->slice_ctrl.all = 0;
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");

        /* CPU-bound work */
        for (int j = 0; j < 10000; j++) {
            counter++;
        }

        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            __sync_fetch_and_add(&stats->grants, 1);
            r->slice_ctrl.granted = 0;
        } else {
            __sync_fetch_and_add(&stats->denials, 1);
        }
        __sync_fetch_and_add(&stats->requests, 1);
    }

    return NULL;
}

static int test_stress(void)
{
    pthread_t threads[4];
    struct test_stats stats = {0};
    int i;

    printf("\n=== Test 3: Stress Test (4 threads) ===\n");

    for (i = 0; i < 4; i++) {
        if (pthread_create(&threads[i], NULL, stress_worker, &stats) != 0) {
            perror("pthread_create");
            return -1;
        }
    }

    for (i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("Total requests: %lu, Grants: %lu, Denials: %lu\n",
           stats.requests, stats.grants, stats.denials);
    printf("Grant rate: %.2f%%\n",
           (stats.grants * 100.0) / stats.requests);

    if (stats.grants > 0) {
        printf("✓ Stress test passed\n");
        return 0;
    } else {
        printf("✗ Stress test failed - no grants\n");
        return -1;
    }
}

/* Test 4: Check sysctl configuration */
static int test_sysctl(void)
{
    FILE *f;
    unsigned int nsec;

    printf("\n=== Test 4: Sysctl Configuration ===\n");

    f = fopen("/proc/sys/kernel/rseq_slice_extension_nsec", "r");
    if (!f) {
        perror("Cannot read sysctl");
        return -1;
    }

    if (fscanf(f, "%u", &nsec) != 1) {
        fclose(f);
        printf("✗ Cannot parse sysctl value\n");
        return -1;
    }
    fclose(f);

    printf("Current slice extension: %u ns (%.1f µs)\n",
           nsec, nsec / 1000.0);

    if (nsec >= 10000 && nsec <= 50000) {
        printf("✓ Sysctl value in expected range (10-50 µs)\n");
        return 0;
    } else {
        printf("⚠ Sysctl value outside expected range\n");
        return -1;
    }
}

int main(void)
{
    int failed = 0;
    struct test_stats stats;

    printf("RSEQ Time Slice Extension Test Suite\n");
    printf("=====================================\n");

    /* Register with RSEQ */
    if (rseq_register() < 0) {
        fprintf(stderr, "Failed to register with RSEQ\n");
        return 1;
    }

    /* Enable slice extensions */
    if (enable_slice_extension() < 0) {
        fprintf(stderr, "Failed to enable slice extensions\n");
        return 1;
    }

    /* Run tests */
    if (test_sysctl() < 0)
        failed++;

    if (test_basic_grant() < 0)
        failed++;

    if (test_multiple_requests(&stats) < 0)
        failed++;

    if (test_stress() < 0)
        failed++;

    /* Cleanup */
    rseq_unregister();

    printf("\n=====================================\n");
    if (failed == 0) {
        printf("✓ All tests PASSED\n");
        return 0;
    } else {
        printf("✗ %d test(s) FAILED\n", failed);
        return 1;
    }
}
