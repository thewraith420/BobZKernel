// SPDX-License-Identifier: GPL-2.0+
/*
 * RSEQ Time Slice Extension - LD_PRELOAD Mutex Wrapper
 *
 * This library intercepts pthread_mutex_lock and requests RSEQ time slice
 * extensions during lock acquisition to reduce lock contention micro-stutters.
 *
 * Build:
 *   gcc -shared -fPIC -O2 -o librseq_mutex_wrapper.so rseq_mutex_wrapper.c -ldl -lpthread
 *
 * Use:
 *   LD_PRELOAD=./librseq_mutex_wrapper.so ./your_program
 */

#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <string.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
# define PR_RSEQ_SLICE_EXTENSION_SET 2
# define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

/* RSEQ structure - must match kernel definition */
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

/* glibc provides this */
extern __thread struct rseq __rseq_abi __attribute__((weak));

/* Function pointers to real implementations */
static int (*real_pthread_mutex_lock)(pthread_mutex_t *mutex) = NULL;
static int (*real_pthread_mutex_unlock)(pthread_mutex_t *mutex) = NULL;

/* Statistics */
static volatile unsigned long total_locks = 0;
static volatile unsigned long granted_locks = 0;
static volatile unsigned long enabled = 0;

/* Enable RSEQ slice extension once per thread */
static __thread int slice_extension_enabled = 0;

static void enable_slice_extension_once(void)
{
    if (slice_extension_enabled)
        return;

    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) == 0) {
        slice_extension_enabled = 1;
        __sync_fetch_and_add(&enabled, 1);
    }
}

/* Constructor to print initialization info */
__attribute__((constructor))
static void init_wrapper(void)
{
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "RSEQ Mutex Wrapper Loaded\n");
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "This wrapper intercepts pthread_mutex_lock\n");
    fprintf(stderr, "and requests RSEQ time slice extensions.\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Kernel: %s\n", "6.18.8-BobZKernel+");
    fprintf(stderr, "Feature: RSEQ Time Slice Extension\n");
    fprintf(stderr, "===========================================\n\n");
}

/* Destructor to print statistics */
__attribute__((destructor))
static void fini_wrapper(void)
{
    fprintf(stderr, "\n");
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "RSEQ Mutex Wrapper Statistics\n");
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "Total mutex locks:     %lu\n", total_locks);
    fprintf(stderr, "Grants detected:       %lu\n", granted_locks);
    fprintf(stderr, "Threads enabled:       %lu\n", enabled);
    if (total_locks > 0) {
        fprintf(stderr, "Grant rate:            %.2f%%\n",
                (granted_locks * 100.0) / total_locks);
    }
    fprintf(stderr, "===========================================\n");
}

/* Intercepted pthread_mutex_lock */
int pthread_mutex_lock(pthread_mutex_t *mutex)
{
    int result;

    /* Get real function on first call */
    if (!real_pthread_mutex_lock) {
        real_pthread_mutex_lock = dlsym(RTLD_NEXT, "pthread_mutex_lock");
        if (!real_pthread_mutex_lock) {
            fprintf(stderr, "FATAL: Could not find pthread_mutex_lock\n");
            return -1;
        }
    }

    /* Check if RSEQ is available */
    if (!&__rseq_abi) {
        /* No RSEQ support, just call real function */
        return real_pthread_mutex_lock(mutex);
    }

    /* Enable slice extension for this thread */
    enable_slice_extension_once();

    /* Count this lock attempt */
    __sync_fetch_and_add(&total_locks, 1);

    /* Clear any previous state */
    __rseq_abi.slice_ctrl.all = 0;
    __asm__ __volatile__("" ::: "memory");

    /* Request slice extension before acquiring lock */
    __rseq_abi.slice_ctrl.request = 1;
    __asm__ __volatile__("" ::: "memory");

    /* Acquire the mutex */
    result = real_pthread_mutex_lock(mutex);

    /* Check if we got a grant (must check before any syscall!) */
    __asm__ __volatile__("" ::: "memory");
    if (__rseq_abi.slice_ctrl.granted) {
        __sync_fetch_and_add(&granted_locks, 1);

        /* Optional: Print when we get a grant (verbose) */
        /* fprintf(stderr, "✓ Grant detected in thread %d\n", gettid()); */
    }

    /* Clear request */
    __rseq_abi.slice_ctrl.all = 0;

    return result;
}

/* Also intercept unlock for completeness */
int pthread_mutex_unlock(pthread_mutex_t *mutex)
{
    if (!real_pthread_mutex_unlock) {
        real_pthread_mutex_unlock = dlsym(RTLD_NEXT, "pthread_mutex_unlock");
        if (!real_pthread_mutex_unlock) {
            fprintf(stderr, "FATAL: Could not find pthread_mutex_unlock\n");
            return -1;
        }
    }

    return real_pthread_mutex_unlock(mutex);
}
