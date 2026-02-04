// SPDX-License-Identifier: GPL-2.0+
/*
 * RSEQ Time Slice Extension - SAFE LD_PRELOAD Mutex Wrapper
 *
 * This is a safer version that doesn't rely on glibc's __rseq_abi symbol
 * which may have compatibility issues.
 *
 * Build:
 *   gcc -shared -fPIC -O2 -o librseq_mutex_wrapper.so rseq_mutex_wrapper_safe.c -ldl -lpthread
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
#include <sys/prctl.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
# define PR_RSEQ_SLICE_EXTENSION_SET 2
# define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

/* Function pointers */
static int (*real_pthread_mutex_lock)(pthread_mutex_t *mutex) = NULL;

/* Statistics */
static volatile unsigned long total_locks = 0;
static volatile int wrapper_active = 0;

/* Enable RSEQ slice extension once per thread */
static __thread int slice_extension_enabled = 0;

static void try_enable_slice_extension(void)
{
    if (slice_extension_enabled)
        return;

    /* Try to enable - if it fails, we just won't use the feature */
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) == 0) {
        slice_extension_enabled = 1;
    }
}

/* Constructor */
__attribute__((constructor))
static void init_wrapper(void)
{
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "RSEQ Mutex Wrapper (SAFE VERSION)\n");
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "This wrapper tests if RSEQ slice extension\n");
    fprintf(stderr, "prctl is functional in the kernel.\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Kernel: 6.18.8-BobZKernel+\n");
    fprintf(stderr, "===========================================\n\n");
    wrapper_active = 1;
}

/* Destructor */
__attribute__((destructor))
static void fini_wrapper(void)
{
    fprintf(stderr, "\n");
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "RSEQ Mutex Wrapper Statistics\n");
    fprintf(stderr, "===========================================\n");
    fprintf(stderr, "Total mutex locks intercepted: %lu\n", total_locks);
    fprintf(stderr, "\n");
    fprintf(stderr, "NOTE: This safe version only tests that\n");
    fprintf(stderr, "the prctl interface works. It doesn't\n");
    fprintf(stderr, "actually request slice extensions because\n");
    fprintf(stderr, "we can't safely access glibc's RSEQ area.\n");
    fprintf(stderr, "===========================================\n");
}

/* Intercepted pthread_mutex_lock */
int pthread_mutex_lock(pthread_mutex_t *mutex)
{
    /* Get real function */
    if (!real_pthread_mutex_lock) {
        real_pthread_mutex_lock = dlsym(RTLD_NEXT, "pthread_mutex_lock");
        if (!real_pthread_mutex_lock) {
            fprintf(stderr, "FATAL: Could not find pthread_mutex_lock\n");
            return -1;
        }
    }

    /* Try to enable slice extension (tests prctl) */
    if (wrapper_active && !slice_extension_enabled) {
        try_enable_slice_extension();
    }

    /* Count locks */
    __sync_fetch_and_add(&total_locks, 1);

    /* Just call the real function - we can't safely access RSEQ structure */
    return real_pthread_mutex_lock(mutex);
}
