// SPDX-License-Identifier: GPL-2.0+
/*
 * Debug RSEQ State
 *
 * Print detailed state to understand the RSEQ time slice extension.
 * Uses proper TLS access via __rseq_offset.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <signal.h>
#include <time.h>

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

/* Use __rseq_offset to properly locate RSEQ struct in TLS */
extern ptrdiff_t __rseq_offset __attribute__((weak));

static struct rseq *get_rseq(void)
{
    char *tls_base;
    asm("mov %%fs:0, %0" : "=r"(tls_base));
    return (struct rseq *)(tls_base + __rseq_offset);
}

int main(void)
{
    int rc;
    sigset_t set;
    struct rseq *r;

    printf("RSEQ State Debugger\n");
    printf("===================\n\n");

    if (!&__rseq_offset) {
        printf("✗ glibc RSEQ offset not available\n");
        return 1;
    }

    r = get_rseq();

    printf("[RSEQ Structure State]\n");
    printf("  Address:      %p (via __rseq_offset=%td)\n", (void *)r, __rseq_offset);
    printf("  cpu_id_start: %u (0x%x)\n", r->cpu_id_start, r->cpu_id_start);
    printf("  cpu_id:       %u (0x%x)\n", r->cpu_id, r->cpu_id);
    printf("  rseq_cs:      0x%lx\n", (unsigned long)r->rseq_cs);
    printf("  flags:        0x%x\n", r->flags);
    printf("  node_id:      %u\n", r->node_id);
    printf("  mm_cid:       %u\n", r->mm_cid);
    printf("  slice_ctrl.all: 0x%x\n", r->slice_ctrl.all);
    printf("  slice_ctrl.request: %u\n", r->slice_ctrl.request);
    printf("  slice_ctrl.granted: %u\n\n", r->slice_ctrl.granted);

    /* Check if cpu_id looks valid */
    if (r->cpu_id > 1024) {
        printf("⚠ WARNING: cpu_id looks invalid (>1024)\n");
        printf("  This suggests RSEQ might not be properly registered\n\n");
    }

    printf("[Slice Extension State]\n");
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_GET, 0, 0, 0);
    if (rc >= 0) {
        printf("  Enabled: %s (flags=0x%x)\n",
               (rc & PR_RSEQ_SLICE_EXT_ENABLE) ? "YES" : "NO", rc);
    } else {
        printf("  ERROR: prctl GET failed\n");
    }

    /* Enable it */
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
               PR_RSEQ_SLICE_EXT_ENABLE, 0, 0);
    if (rc < 0) {
        printf("  ERROR: prctl SET failed\n");
        return 1;
    }

    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_GET, 0, 0, 0);
    printf("  After enable: flags=0x%x\n\n", rc);

    printf("[Signal State]\n");
    sigemptyset(&set);
    if (sigpending(&set) == 0) {
        printf("  Pending signals: ");
        int has_pending = 0;
        for (int sig = 1; sig < 32; sig++) {
            if (sigismember(&set, sig)) {
                printf("%d ", sig);
                has_pending = 1;
            }
        }
        if (!has_pending) {
            printf("none");
        }
        printf("\n");
    }

    printf("\n[RSEQ Flags Decoded]\n");
    printf("  Raw flags: 0x%x\n", r->flags);

    /* Bit 4 and 5 from rseq.h */
    #define RSEQ_CS_FLAG_SLICE_EXT_AVAILABLE (1U << 4)
    #define RSEQ_CS_FLAG_SLICE_EXT_ENABLED   (1U << 5)

    if (r->flags & RSEQ_CS_FLAG_SLICE_EXT_AVAILABLE) {
        printf("  ✓ SLICE_EXT_AVAILABLE bit set\n");
    } else {
        printf("  ✗ SLICE_EXT_AVAILABLE bit NOT set\n");
    }

    if (r->flags & RSEQ_CS_FLAG_SLICE_EXT_ENABLED) {
        printf("  ✓ SLICE_EXT_ENABLED bit set\n");
    } else {
        printf("  ✗ SLICE_EXT_ENABLED bit NOT set\n");
    }

    printf("\n[Test: CPU-bound work to trigger grants]\n");
    r->slice_ctrl.all = 0;
    r->slice_ctrl.request = 1;
    __asm__ __volatile__("" ::: "memory");

    printf("  Set request=1\n");

    /* Do CPU-bound work to trigger actual preemption */
    int grants = 0;
    volatile unsigned long counter = 0;
    time_t start = time(NULL);
    printf("  Running CPU-bound work for 2 seconds...\n");

    while (time(NULL) - start < 2) {
        r->slice_ctrl.request = 1;
        for (int j = 0; j < 10000; j++) {
            counter++;
        }
        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants++;
            r->slice_ctrl.granted = 0;
        }
    }

    printf("  Iterations: %lu\n", counter);
    printf("  Grants detected: %d\n", grants);

    if (grants > 0) {
        printf("\n✓✓✓ GRANT DETECTED! Got %d grants.\n", grants);
        return 0;
    } else {
        printf("\n⚠ No grants during test (may need more CPU contention)\n");
        return 1;
    }
}
