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
#include <sched.h>
#include <time.h>

#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_GET 1
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01

#define __NR_rseq_slice_yield 471

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
} __attribute__((aligned(32)));

extern ptrdiff_t __rseq_offset __attribute__((weak));

static struct rseq *get_rseq(void)
{
    char *tls_base;
    asm("mov %%fs:0, %0" : "=r"(tls_base));
    return (struct rseq *)(tls_base + __rseq_offset);
}

int main(void)
{
    struct rseq *r = get_rseq();
    int grants = 0;
    int rc;
    
    printf("Testing RSEQ grants with proper struct access\n");
    printf("==============================================\n\n");
    
    printf("RSEQ struct at: %p\n", r);
    printf("  cpu_id: %u\n", r->cpu_id);
    printf("  flags: 0x%x\n", r->flags);
    printf("  slice_ctrl offset in struct: %zu\n", offsetof(struct rseq, slice_ctrl));
    
    // Enable slice extension
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET, PR_RSEQ_SLICE_EXT_ENABLE, 0, 0);
    if (rc < 0) {
        printf("Failed to enable slice extension: %m\n");
        return 1;
    }
    printf("\n✓ Slice extension enabled\n");
    printf("  flags after enable: 0x%x\n\n", r->flags);
    
    // Test 1: Simple test with sched_yield
    printf("Test 1: sched_yield loop (100 iterations)\n");
    for (int i = 0; i < 100; i++) {
        // Set request
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");
        
        // Yield CPU (this should trigger need_resched)
        sched_yield();
        
        // Check grant
        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants++;
            r->slice_ctrl.granted = 0;  // Clear it
        }
    }
    printf("  Grants: %d / 100\n\n", grants);
    
    // Test 2: Using rseq_slice_yield syscall
    int grants2 = 0;
    printf("Test 2: rseq_slice_yield syscall (100 iterations)\n");
    for (int i = 0; i < 100; i++) {
        r->slice_ctrl.request = 1;
        __asm__ __volatile__("" ::: "memory");
        
        syscall(__NR_rseq_slice_yield);
        
        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants2++;
            r->slice_ctrl.granted = 0;
        }
    }
    printf("  Grants: %d / 100\n\n", grants2);
    
    // Test 3: CPU-bound loop that should trigger preemption
    int grants3 = 0;
    printf("Test 3: CPU-bound work to trigger preemption (1 second)\n");
    volatile unsigned long counter = 0;
    time_t start = time(NULL);
    while (time(NULL) - start < 1) {
        r->slice_ctrl.request = 1;
        
        // Do some work
        for (int j = 0; j < 10000; j++) {
            counter++;
        }
        
        __asm__ __volatile__("" ::: "memory");
        if (r->slice_ctrl.granted) {
            grants3++;
            r->slice_ctrl.granted = 0;
        }
    }
    printf("  Grants: %d (counter=%lu)\n\n", grants3, counter);
    
    printf("==============================================\n");
    printf("Total grants: %d\n", grants + grants2 + grants3);
    
    if (grants + grants2 + grants3 > 0) {
        printf("✓ SUCCESS: Got at least one grant!\n");
        return 0;
    } else {
        printf("✗ FAIL: No grants received\n");
        return 1;
    }
}
