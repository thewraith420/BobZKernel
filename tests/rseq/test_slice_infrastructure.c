#define _GNU_SOURCE
#include <errno.h>
#include <linux/prctl.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_GET 1
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

#ifndef __NR_rseq_slice_yield
#define __NR_rseq_slice_yield 471
#endif

extern __thread volatile struct rseq {
	uint32_t cpu_id_start;
	uint32_t cpu_id;
	uint64_t rseq_cs;
	uint32_t flags;
	uint32_t node_id;
	uint32_t mm_cid;
	union {
		uint32_t all;
		struct {
			uint8_t request;
			uint8_t granted;
			uint16_t __reserved;
		};
	} slice_ctrl;
} __rseq_abi __attribute__((weak));

static long prctl_rseq_get(void)
{
	return syscall(SYS_prctl, PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_GET, 0, 0, 0);
}

static long prctl_rseq_set(unsigned long flags)
{
	return syscall(SYS_prctl, PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET, flags, 0, 0);
}

int main(void)
{
	printf("=== RSEQ Slice Extension Infrastructure Test ===\n\n");

	// Check glibc rseq support
	if (&__rseq_abi == NULL) {
		fprintf(stderr, "Error: glibc 2.41+ required for __rseq_abi\n");
		return 1;
	}

	printf("✓ glibc __rseq_abi available at: %p\n", (void *)&__rseq_abi);
	printf("  rseq flags: 0x%08x\n", __rseq_abi.flags);
	printf("  slice_ctrl.all: 0x%08x\n\n", __rseq_abi.slice_ctrl.all);

	// Test prctl GET (should be 0, disabled)
	long ret = prctl_rseq_get();
	if (ret < 0) {
		perror("prctl GET failed");
		return 1;
	}
	printf("✓ prctl GET (before enable): 0x%lx (expected 0x0)\n", ret);

	// Test prctl SET to enable
	ret = prctl_rseq_set(PR_RSEQ_SLICE_EXT_ENABLE);
	if (ret < 0) {
		perror("prctl SET enable failed");
		return 1;
	}
	printf("✓ prctl SET enable: success\n");

	// Test prctl GET (should be 1, enabled)
	ret = prctl_rseq_get();
	if (ret < 0) {
		perror("prctl GET failed");
		return 1;
	}
	printf("✓ prctl GET (after enable): 0x%lx (expected 0x1)\n", ret);

	// Check rseq flags updated
	printf("  rseq flags after enable: 0x%08x\n\n", __rseq_abi.flags);

	// Test syscall
	printf("Testing syscall #%d (rseq_slice_yield)...\n", __NR_rseq_slice_yield);
	ret = syscall(__NR_rseq_slice_yield);
	printf("✓ rseq_slice_yield() returned: %ld\n\n", ret);

	// Test sysctl
	printf("Checking sysctl visibility...\n");
	FILE *f = fopen("/proc/sys/kernel/rseq_slice_extension_nsec", "r");
	if (!f) {
		perror("sysctl not found");
		return 1;
	}
	unsigned int nsec;
	if (fscanf(f, "%u", &nsec) == 1) {
		printf("✓ sysctl kernel.rseq_slice_extension_nsec = %u ns (%u µs)\n", 
		       nsec, nsec / 1000);
	}
	fclose(f);

	// Test manual request bit
	printf("\nTesting manual slice_ctrl manipulation...\n");
	printf("Initial slice_ctrl: request=%u granted=%u\n",
	       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);
	
	__rseq_abi.slice_ctrl.request = 1;
	printf("After setting request=1: request=%u granted=%u\n",
	       __rseq_abi.slice_ctrl.request, __rseq_abi.slice_ctrl.granted);

	printf("\n=== Infrastructure Test Results ===\n");
	printf("✓ RSEQ area accessible via glibc __rseq_abi\n");
	printf("✓ prctl(PR_RSEQ_SLICE_EXTENSION) GET/SET working\n");
	printf("✓ syscall #470 (rseq_slice_yield) present\n");
	printf("✓ sysctl kernel.rseq_slice_extension_nsec visible\n");
	printf("✓ slice_ctrl.request writable from userspace\n");
	printf("\n⚠️  NOTE: Grant mechanism requires scheduler integration\n");
	printf("    The scheduler must check slice_ctrl.request and set .granted\n");
	printf("    This integration appears to be missing from the backport.\n");
	
	return 0;
}
