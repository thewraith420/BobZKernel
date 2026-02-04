// SPDX-License-Identifier: GPL-2.0+
/*
 * Debug RSEQ State
 *
 * Print detailed state to understand why grants aren't happening
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <signal.h>

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

int main(void)
{
    int rc;
    sigset_t set;

    printf("RSEQ State Debugger\n");
    printf("===================\n\n");

    if (!&__rseq_abi) {
        printf("✗ glibc RSEQ not available\n");
        return 1;
    }

    printf("[RSEQ Structure State]\n");
    printf("  Address:      %p\n", (void *)&__rseq_abi);
    printf("  cpu_id_start: %u (0x%x)\n", __rseq_abi.cpu_id_start, __rseq_abi.cpu_id_start);
    printf("  cpu_id:       %u (0x%x)\n", __rseq_abi.cpu_id, __rseq_abi.cpu_id);
    printf("  rseq_cs:      0x%lx\n", __rseq_abi.rseq_cs);
    printf("  flags:        0x%x\n", __rseq_abi.flags);
    printf("  node_id:      %u\n", __rseq_abi.node_id);
    printf("  mm_cid:       %u\n", __rseq_abi.mm_cid);
    printf("  slice_ctrl.all: 0x%x\n", __rseq_abi.slice_ctrl.all);
    printf("  slice_ctrl.request: %u\n", __rseq_abi.slice_ctrl.request);
    printf("  slice_ctrl.granted: %u\n\n", __rseq_abi.slice_ctrl.granted);

    /* Check if cpu_id looks valid */
    if (__rseq_abi.cpu_id > 1024) {
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
    printf("  Raw flags: 0x%x\n", __rseq_abi.flags);

    /* Bit 4 and 5 from rseq.h */
    #define RSEQ_CS_FLAG_SLICE_EXT_AVAILABLE (1U << 4)
    #define RSEQ_CS_FLAG_SLICE_EXT_ENABLED   (1U << 5)

    if (__rseq_abi.flags & RSEQ_CS_FLAG_SLICE_EXT_AVAILABLE) {
        printf("  ✓ SLICE_EXT_AVAILABLE bit set\n");
    } else {
        printf("  ✗ SLICE_EXT_AVAILABLE bit NOT set\n");
    }

    if (__rseq_abi.flags & RSEQ_CS_FLAG_SLICE_EXT_ENABLED) {
        printf("  ✓ SLICE_EXT_ENABLED bit set\n");
    } else {
        printf("  ✗ SLICE_EXT_ENABLED bit NOT set\n");
    }

    printf("\n[Test: Request and Check]\n");
    __rseq_abi.slice_ctrl.all = 0;
    __rseq_abi.slice_ctrl.request = 1;
    __asm__ __volatile__("" ::: "memory");

    printf("  Set request=1\n");
    printf("  slice_ctrl.all after: 0x%x\n", __rseq_abi.slice_ctrl.all);
    printf("  request=%u, granted=%u\n",
           __rseq_abi.slice_ctrl.request,
           __rseq_abi.slice_ctrl.granted);

    /* Try a syscall */
    printf("\n  Calling getpid()...\n");
    getpid();

    __asm__ __volatile__("" ::: "memory");
    printf("  After syscall:\n");
    printf("  slice_ctrl.all: 0x%x\n", __rseq_abi.slice_ctrl.all);
    printf("  request=%u, granted=%u\n",
           __rseq_abi.slice_ctrl.request,
           __rseq_abi.slice_ctrl.granted);

    if (__rseq_abi.slice_ctrl.granted) {
        printf("\n✓✓✓ GRANT DETECTED!\n");
    } else {
        printf("\n✗ No grant (this is the problem)\n");
    }

    return 0;
}
