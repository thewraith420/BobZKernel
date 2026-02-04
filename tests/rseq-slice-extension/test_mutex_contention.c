// SPDX-License-Identifier: GPL-2.0+
/*
 * Mutex Contention Test
 *
 * Creates heavy mutex contention to trigger RSEQ slice extension requests.
 * Use with the LD_PRELOAD wrapper to see grants.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>

#define NUM_THREADS 8
#define ITERATIONS 100000

static pthread_mutex_t shared_mutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned long shared_counter = 0;

void *worker(void *arg)
{
    int tid = *(int *)arg;

    printf("Thread %d starting...\n", tid);

    for (int i = 0; i < ITERATIONS; i++) {
        /* Lock - this is where RSEQ extension happens */
        pthread_mutex_lock(&shared_mutex);

        /* Critical section - do some work */
        shared_counter++;
        for (volatile int j = 0; j < 100; j++);

        /* Unlock */
        pthread_mutex_unlock(&shared_mutex);

        /* Simulate some work outside lock */
        for (volatile int j = 0; j < 50; j++);
    }

    printf("Thread %d complete\n", tid);
    return NULL;
}

int main(void)
{
    pthread_t threads[NUM_THREADS];
    int thread_ids[NUM_THREADS];

    printf("Mutex Contention Test\n");
    printf("======================\n");
    printf("Threads: %d\n", NUM_THREADS);
    printf("Iterations per thread: %d\n", ITERATIONS);
    printf("Total lock operations: %d\n\n", NUM_THREADS * ITERATIONS);

    printf("Starting threads...\n");
    for (int i = 0; i < NUM_THREADS; i++) {
        thread_ids[i] = i;
        pthread_create(&threads[i], NULL, worker, &thread_ids[i]);
    }

    printf("Threads running...\n\n");

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("\n======================\n");
    printf("Test Complete\n");
    printf("Final counter: %lu (expected: %d)\n",
           shared_counter, NUM_THREADS * ITERATIONS);

    if (shared_counter == NUM_THREADS * ITERATIONS) {
        printf("✓ Counter is correct\n");
    } else {
        printf("✗ Counter mismatch!\n");
    }

    return 0;
}
