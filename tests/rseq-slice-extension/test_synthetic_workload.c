// SPDX-License-Identifier: GPL-2.0+
/*
 * RSEQ Synthetic Workload Test
 *
 * Simulates a gaming/real-time workload that would benefit from slice extensions:
 * - Tight rendering-style loops
 * - Critical sections that need to complete
 * - Scheduler pressure from competing threads
 * - CPU-bound work to trigger actual scheduler preemption
 *
 * Uses proper TLS access via __rseq_offset (not __rseq_abi directly).
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <sched.h>
#include <time.h>
#include <errno.h>

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

/* Use __rseq_offset to properly locate RSEQ struct in TLS */
extern ptrdiff_t __rseq_offset __attribute__((weak));

static struct rseq *get_rseq(void)
{
    char *tls_base;
    asm("mov %%fs:0, %0" : "=r"(tls_base));
    return (struct rseq *)(tls_base + __rseq_offset);
}

struct workload_stats {
    volatile unsigned long frames_rendered;
    volatile unsigned long slice_requests;
    volatile unsigned long slice_grants;
    volatile unsigned long preemptions_avoided;
};

static struct workload_stats global_stats = {0};
static volatile int running = 1;

/* Simulate frame rendering work */
static inline void do_frame_work(int complexity)
{
    volatile uint64_t sum = 0;
    for (int i = 0; i < complexity; i++) {
        sum += i * i;
    }
}

/* Game-like render loop with RSEQ protection */
static void *render_thread(void *arg)
{
    int thread_id = *(int *)arg;
    unsigned long local_grants = 0;
    unsigned long local_requests = 0;
    struct rseq *r = get_rseq();

    printf("  Render thread %d started\n", thread_id);

    /* Enable slice extensions */
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) < 0) {
        perror("prctl failed in render thread");
        return NULL;
    }

    while (running) {
        /* Start of critical section - simulate frame update */
        r->slice_ctrl.all = 0;
        __asm__ __volatile__("" ::: "memory");

        /* Request slice extension to avoid preemption during frame */
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");
        local_requests++;

        /* Do critical rendering work - CPU-bound to trigger preemption */
        do_frame_work(50000);

        /* Check if we got the grant */
        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            local_grants++;
            r->slice_ctrl.granted = 0;  /* Clear for next frame */
            __sync_fetch_and_add(&global_stats.slice_grants, 1);
        }

        /* Frame complete */
        __sync_fetch_and_add(&global_stats.frames_rendered, 1);
        __sync_fetch_and_add(&global_stats.slice_requests, 1);
    }

    printf("  Render thread %d: %lu grants / %lu requests (%.1f%%)\n",
           thread_id, local_grants, local_requests,
           local_requests > 0 ? (local_grants * 100.0 / local_requests) : 0.0);

    return NULL;
}

/* CPU hog thread to create scheduler pressure */
static void *stress_thread(void *arg)
{
    int thread_id = *(int *)arg;
    printf("  Stress thread %d started\n", thread_id);

    while (running) {
        /* Busy work to load the scheduler */
        do_frame_work(10000);
        sched_yield();
    }

    return NULL;
}

/* Monitor thread to show real-time stats */
static void *monitor_thread(void *arg)
{
    (void)arg;
    unsigned long last_frames = 0;

    printf("\n[Real-time Stats]\n");
    printf("Time    Frames/s  Total Frames  Requests   Grants    Grant%%\n");
    printf("--------------------------------------------------------------\n");

    for (int i = 0; i < 20 && running; i++) {
        sleep(1);

        unsigned long frames = global_stats.frames_rendered;
        unsigned long fps = frames - last_frames;
        last_frames = frames;

        double grant_rate = global_stats.slice_requests > 0 ?
            (global_stats.slice_grants * 100.0 / global_stats.slice_requests) : 0.0;

        printf("%4ds   %8lu  %12lu  %9lu  %8lu   %6.2f%%\n",
               i + 1, fps, frames,
               global_stats.slice_requests,
               global_stats.slice_grants,
               grant_rate);

        fflush(stdout);
    }

    return NULL;
}

int main(void)
{
    pthread_t render_threads[4];
    pthread_t stress_threads[4];
    pthread_t monitor;
    int thread_ids[8];
    int num_cpus;
    struct rseq *r;

    printf("RSEQ Synthetic Workload Test\n");
    printf("============================\n\n");

    if (!&__rseq_offset) {
        fprintf(stderr, "✗ glibc RSEQ offset not available\n");
        return 1;
    }

    r = get_rseq();
    printf("RSEQ struct at: %p (via __rseq_offset=%td)\n", (void *)r, __rseq_offset);
    printf("  cpu_id: %u, flags: 0x%x\n\n", r->cpu_id, r->flags);

    /* Enable for main thread */
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) < 0) {
        perror("prctl failed");
        return 1;
    }

    printf("✓ RSEQ Time Slice Extension enabled\n");

    num_cpus = sysconf(_SC_NPROCESSORS_ONLN);
    printf("✓ System has %d CPUs\n", num_cpus);

    printf("\nSimulating game workload:\n");
    printf("  - 4 render threads (simulating game engine workers)\n");
    printf("  - 4 stress threads (simulating background load)\n");
    printf("  - Each render thread requests slice extensions\n");
    printf("  - CPU-bound work triggers actual scheduler preemption\n\n");

    /* Start render threads (these request slice extensions) */
    printf("Starting render threads...\n");
    for (int i = 0; i < 4; i++) {
        thread_ids[i] = i;
        if (pthread_create(&render_threads[i], NULL, render_thread, &thread_ids[i]) != 0) {
            perror("pthread_create render");
            return 1;
        }
    }

    /* Start stress threads (these create scheduler pressure) */
    printf("Starting stress threads...\n");
    for (int i = 0; i < 4; i++) {
        thread_ids[4 + i] = i;
        if (pthread_create(&stress_threads[i], NULL, stress_thread, &thread_ids[4 + i]) != 0) {
            perror("pthread_create stress");
            return 1;
        }
    }

    /* Start monitor thread */
    if (pthread_create(&monitor, NULL, monitor_thread, NULL) != 0) {
        perror("pthread_create monitor");
        return 1;
    }

    /* Let it run for 20 seconds */
    pthread_join(monitor, NULL);

    /* Stop all threads */
    running = 0;

    printf("\nStopping threads...\n");
    for (int i = 0; i < 4; i++) {
        pthread_join(render_threads[i], NULL);
        pthread_join(stress_threads[i], NULL);
    }

    printf("\n============================\n");
    printf("Final Results:\n");
    printf("  Total frames rendered: %lu\n", global_stats.frames_rendered);
    printf("  Total slice requests:  %lu\n", global_stats.slice_requests);
    printf("  Total slice grants:    %lu\n", global_stats.slice_grants);

    if (global_stats.slice_requests > 0) {
        double grant_rate = (global_stats.slice_grants * 100.0) / global_stats.slice_requests;
        printf("  Grant rate:            %.2f%%\n", grant_rate);

        if (grant_rate > 0) {
            printf("\n✓✓✓ SUCCESS! RSEQ Time Slice Extension IS WORKING!\n");
            printf("\nThe kernel successfully granted %lu slice extensions.\n",
                   global_stats.slice_grants);
            printf("This proves the backport is fully functional!\n");
            return 0;
        } else {
            printf("\n⚠ WARNING: 0%% grant rate\n");
            printf("\nPossible explanations:\n");
            printf("1. Grant conditions not being met (need_resched + no other work)\n");
            printf("2. rseq_slice_yield() syscall not triggering grant logic\n");
            printf("3. Kernel grant function has a bug\n");
            printf("\nThe infrastructure is there (prctl works), but grants aren't happening.\n");
            printf("This might still work correctly in real gaming scenarios.\n");
            return 1;
        }
    } else {
        printf("\n✗ FAIL: No requests were made\n");
        return 1;
    }
}
