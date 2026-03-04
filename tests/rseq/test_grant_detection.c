#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <linux/prctl.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <elf.h>
#include <sys/auxv.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <sched.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_GET 1
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

#ifndef RSEQ_SIG
#define RSEQ_SIG 0x53053053
#endif

#ifndef __NR_rseq
#define __NR_rseq 334
#endif

#ifndef __NR_rseq_slice_yield
#define __NR_rseq_slice_yield 471
#endif

struct rseq_slice_ctrl {
	union {
		__u32 all;
		struct {
			__u8 request;
			__u8 granted;
			__u16 __reserved;
		};
	};
};

struct rseq {
	__u32 cpu_id_start;
	__u32 cpu_id;
	__u64 rseq_cs;
	__u32 flags;
	__u32 node_id;
	__u32 mm_cid;
	struct rseq_slice_ctrl slice_ctrl;
	char end[];
} __attribute__((aligned(32)));

// Thread-local rseq area (glibc provides this in 2.41+)
extern __thread volatile struct rseq __rseq_abi __attribute__((weak));

static long prctl_rseq_set(unsigned long flags)
{
	return syscall(SYS_prctl, PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET, flags, 0, 0);
}

int main(void)
{
	printf("=== RSEQ Slice Extension Grant Detection Test ===\n\n");

	// Check if glibc provides rseq
	if (&__rseq_abi == NULL) {
		fprintf(stderr, "Error: glibc 2.41+ required for __rseq_abi\n");
		return 1;
	}

	printf("rseq area: %p\n", (void *)&__rseq_abi);
	printf("Initial slice_ctrl.all: 0x%08x\n", __rseq_abi.slice_ctrl.all);
	printf("Initial request: %u, granted: %u\n\n", 
	       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);

	// Enable the extension
	if (prctl_rseq_set(PR_RSEQ_SLICE_EXT_ENABLE) != 0) {
		fprintf(stderr, "Failed to enable RSEQ slice extension: %s\n", strerror(errno));
		return 1;
	}
	printf("✓ RSEQ slice extension enabled\n\n");

	// Request a grant
	printf("Requesting grant...\n");
	__rseq_abi.slice_ctrl.request = 1;
	
	// Busy loop to give the kernel a chance to grant
	printf("Spinning to trigger grant...\n");
	volatile unsigned long counter = 0;
	unsigned int granted_seen = 0;
	
	for (int i = 0; i < 1000000; i++) {
		counter++;
		
		// Check if granted
		if (__rseq_abi.slice_ctrl.granted && !granted_seen) {
			granted_seen = 1;
			printf("\n🎉 GRANT DETECTED!\n");
			printf("   slice_ctrl.all: 0x%08x\n", __rseq_abi.slice_ctrl.all);
			printf("   request: %u, granted: %u\n", 
			       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);
			printf("   iteration: %d\n\n", i);
			break;
		}
		
		// Periodically print status
		if (i % 100000 == 0 && i > 0) {
			printf("  [%d] slice_ctrl: 0x%08x (req=%u grant=%u)\n", 
			       i, __rseq_abi.slice_ctrl.all,
			       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);
		}
	}

	if (!granted_seen) {
		printf("\n❌ No grant detected after 1M iterations\n");
		printf("Final slice_ctrl.all: 0x%08x\n", __rseq_abi.slice_ctrl.all);
		printf("Final request: %u, granted: %u\n", 
		       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);
		return 1;
	}

	// Test yield
	printf("Testing rseq_slice_yield syscall...\n");
	long yielded = syscall(__NR_rseq_slice_yield);
	printf("rseq_slice_yield returned: %ld\n", yielded);
	
	printf("\nAfter yield:\n");
	printf("  slice_ctrl.all: 0x%08x\n", __rseq_abi.slice_ctrl.all);
	printf("  request: %u, granted: %u\n\n", 
	       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);

	printf("=== Test PASSED ===\n");
	return 0;
}
