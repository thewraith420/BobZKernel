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

#ifndef PR_RSEQ_SLICE_ENABLE
#define PR_RSEQ_SLICE_ENABLE 73
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

/* Glibc 2.35+ automatically registers RSEQ, use its structure */
static __thread volatile struct rseq *__rseq_abi_ptr = NULL;

/* Fallback structure if glibc doesn't have RSEQ */
static __thread volatile struct rseq __rseq_abi_fallback = {
    .cpu_id = UINT32_MAX,
};

/* Statistics */
struct test_stats {
    unsigned long requests;
    unsigned long grants;
    unsigned long denials;
    unsigned long iterations;
};

/* Access glibc's RSEQ area via __rseq_abi symbol */
extern __thread volatile struct rseq __rseq_abi __attribute__((weak));

static int rseq_register(void)
{
    int rc;

    /* Check if glibc provides __rseq_abi */
    if (&__rseq_abi != NULL) {
        printf("Using glibc's RSEQ registration\n");
        __rseq_abi_ptr = (struct rseq *)&__rseq_abi;

        if (__rseq_abi_ptr->cpu_id == RSEQ_CPU_ID_REGISTRATION_FAILED) {
            printf("RSEQ registration failed by glibc\n");
            return -1;
        }

        printf("RSEQ already registered by glibc (OK)\n");
        return 0;
    }

    /* Fallback: manual registration */
    printf("DEBUG: sizeof(struct rseq) = %zu\n", sizeof(__rseq_abi_fallback));
    printf("DEBUG: RSEQ_SIG = 0x%x\n", RSEQ_SIG);

    __rseq_abi_ptr = &__rseq_abi_fallback;
    rc = syscall(__NR_rseq, __rseq_abi_ptr, sizeof(__rseq_abi_fallback), 0, RSEQ_SIG);
    if (rc) {
        if (errno == EBUSY) {
            printf("RSEQ already registered (OK)\n");
            return 0;
        }
        printf("rseq registration failed: %s (errno=%d)\n", strerror(errno), errno);
        return -1;
    }

    printf("RSEQ registered successfully\n");
    return 0;
}

static int rseq_unregister(void)
{
    /* Don't unregister if using glibc's RSEQ */
    if (__rseq_abi_ptr == (struct rseq *)&__rseq_abi)
        return 0;

    return syscall(__NR_rseq, __rseq_abi_ptr, sizeof(__rseq_abi_fallback),
                   RSEQ_FLAG_UNREGISTER, RSEQ_SIG);
}

static int enable_slice_extension(void)
{
    int rc = prctl(PR_RSEQ_SLICE_ENABLE, 1, 0, 0, 0);
    if (rc < 0) {
        perror("prctl(PR_RSEQ_SLICE_ENABLE) failed");
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

/* Test 1: Basic grant functionality */
static int test_basic_grant(void)
{
    printf("\n=== Test 1: Basic Grant Functionality ===\n");

    clear_request();
    request_slice_extension();

    /* Give kernel a chance to process */
    usleep(1000);

    if (check_grant()) {
        printf("✓ Slice extension granted\n");
        clear_request();
        return 0;
    } else {
        printf("✗ Slice extension NOT granted (may be under load)\n");
        return -1;
    }
}

/* Test 2: Multiple requests */
static int test_multiple_requests(struct test_stats *stats)
{
    int i, grants = 0;
    const int iterations = 1000;

    printf("\n=== Test 2: Multiple Requests (%d iterations) ===\n", iterations);

    memset(stats, 0, sizeof(*stats));

    for (i = 0; i < iterations; i++) {
        clear_request();
        request_slice_extension();

        /* Small delay to allow grant processing */
        for (volatile int j = 0; j < 1000; j++);

        if (check_grant()) {
            grants++;
            stats->grants++;
        } else {
            stats->denials++;
        }
        stats->requests++;
        stats->iterations++;

        clear_request();
    }

    printf("Requests: %lu, Grants: %lu, Denials: %lu\n",
           stats->requests, stats->grants, stats->denials);
    printf("Grant rate: %.2f%%\n",
           (stats->grants * 100.0) / stats->requests);

    if (grants > 0) {
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
    int i;

    /* Register RSEQ for this thread */
    if (rseq_register() < 0)
        return NULL;

    if (enable_slice_extension() < 0)
        return NULL;

    for (i = 0; i < 10000; i++) {
        clear_request();
        request_slice_extension();

        /* Do some work */
        for (volatile int j = 0; j < 100; j++);

        if (check_grant()) {
            __sync_fetch_and_add(&stats->grants, 1);
        } else {
            __sync_fetch_and_add(&stats->denials, 1);
        }
        __sync_fetch_and_add(&stats->requests, 1);

        clear_request();
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
