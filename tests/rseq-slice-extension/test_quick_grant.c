// SPDX-License-Identifier: GPL-2.0+
/*
 * Quick RSEQ Grant Test - 5 second version
 *
 * Uses proper TLS access via __rseq_offset and CPU-bound work
 * to trigger actual scheduler preemption (not voluntary yield).
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/prctl.h>
#include <sched.h>
#include <time.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
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

/* Use __rseq_offset to properly locate RSEQ struct in TLS */
extern ptrdiff_t __rseq_offset __attribute__((weak));

static struct rseq *get_rseq(void)
{
    char *tls_base;
    asm("mov %%fs:0, %0" : "=r"(tls_base));
    return (struct rseq *)(tls_base + __rseq_offset);
}

static volatile int running = 1;
static volatile unsigned long total_requests = 0;
static volatile unsigned long total_grants = 0;

static void *worker(void *arg)
{
    int tid = *(int*)arg;
    unsigned long local_grants = 0;
    unsigned long local_requests = 0;
    struct rseq *r = get_rseq();

    prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
          PR_RSEQ_SLICE_EXT_ENABLE, 0, 0);

    while (running) {
        r->slice_ctrl.all = 0;
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");
        local_requests++;

        /* CPU-bound work to trigger actual scheduler preemption */
        for (volatile int i = 0; i < 50000; i++);

        /* Check grant */
        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            local_grants++;
            r->slice_ctrl.granted = 0;  /* Clear for next iteration */
        }
    }

    __sync_fetch_and_add(&total_requests, local_requests);
    __sync_fetch_and_add(&total_grants, local_grants);

    if (local_grants > 0) {
        printf("  Thread %d: Got %lu grants!\n", tid, local_grants);
    }

    return NULL;
}

int main(void)
{
    pthread_t threads[4];
    int ids[4] = {0, 1, 2, 3};
    struct rseq *r;

    printf("Quick RSEQ Grant Test (5 seconds)\n");
    printf("==================================\n\n");

    if (!&__rseq_offset) {
        printf("✗ glibc RSEQ offset not available\n");
        return 1;
    }

    r = get_rseq();
    printf("RSEQ struct at: %p (via __rseq_offset=%td)\n", (void *)r, __rseq_offset);
    printf("  cpu_id: %u, flags: 0x%x\n\n", r->cpu_id, r->flags);

    printf("Starting 4 worker threads (CPU-bound work)...\n");
    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, worker, &ids[i]);
    }

    /* Run for 5 seconds with progress dots */
    for (int i = 0; i < 5; i++) {
        sleep(1);
        printf(".");
        fflush(stdout);
    }
    printf("\n\nStopping...\n");

    running = 0;

    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("\n==================================\n");
    printf("Results:\n");
    printf("  Requests: %lu\n", total_requests);
    printf("  Grants:   %lu\n", total_grants);

    if (total_requests > 0) {
        printf("  Rate:     %.2f%%\n", (total_grants * 100.0) / total_requests);
    }

    if (total_grants > 0) {
        printf("\n✓✓✓ SUCCESS! Got %lu grants!\n", total_grants);
        printf("RSEQ Time Slice Extension is WORKING!\n");
        return 0;
    } else {
        printf("\n⚠ No grants (infrastructure works, but conditions not met)\n");
        return 1;
    }
}
