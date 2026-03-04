#define _GNU_SOURCE
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

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_GET 1
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

#ifndef RSEQ_SIG
#define RSEQ_SIG 0x53053053
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

#ifndef __NR_rseq
#define __NR_rseq 334
#endif

#ifndef __NR_rseq_slice_yield
#define __NR_rseq_slice_yield 471
#endif

static struct rseq *rseq_area;
static size_t rseq_area_len;
static size_t rseq_area_align;
static unsigned int rseq_sig = RSEQ_SIG;

static int rseq_register_current(void)
{
	return syscall(__NR_rseq, rseq_area, rseq_area_len, 0, rseq_sig);
}

static long prctl_rseq_get(void)
{
	return prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_GET, 0, 0, 0);
}

static long prctl_rseq_set(unsigned long flags)
{
	return prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET, flags, 0, 0);
}

int main(void)
{
	printf("rseq slice extension test\n");

	unsigned long aux_len = 0;
	unsigned long aux_align = 0;

#ifdef AT_RSEQ_FEATURE_SIZE
	aux_len = getauxval(AT_RSEQ_FEATURE_SIZE);
#endif
#ifdef AT_RSEQ_ALIGN
	aux_align = getauxval(AT_RSEQ_ALIGN);
#endif

	printf("auxv: feature_size=%lu align=%lu\n", aux_len, aux_align);

	rseq_area_len = aux_len ? aux_len : sizeof(struct rseq);
	rseq_area_align = aux_align ? aux_align : 32;

	if (posix_memalign((void **)&rseq_area, rseq_area_align, rseq_area_len) != 0) {
		fprintf(stderr, "posix_memalign failed\n");
		return 1;
	}
	memset(rseq_area, 0, rseq_area_len);
	printf("rseq area addr: %p (len=%zu align=%zu sig=0x%x)\n",
	       (void *)rseq_area, rseq_area_len, rseq_area_align, rseq_sig);

	if (rseq_register_current() != 0) {
		if (errno == EBUSY || errno == EINVAL) {
			printf("rseq already registered by libc (continuing)\n");
		} else {
			fprintf(stderr, "rseq register failed: %s\n", strerror(errno));
			return 1;
		}
	} else {
		printf("rseq register: OK\n");
	}

	long get_before = prctl_rseq_get();
	if (get_before < 0) {
		if (errno == ENXIO) {
			fprintf(stderr, "prctl GET failed: rseq not registered\n");
			return 1;
		}
		fprintf(stderr, "prctl GET failed: %s\n", strerror(errno));
		return 1;
	}
	printf("prctl GET before: 0x%lx\n", get_before);

	if (prctl_rseq_set(PR_RSEQ_SLICE_EXT_ENABLE) != 0) {
		fprintf(stderr, "prctl SET failed: %s\n", strerror(errno));
		return 1;
	}
	printf("prctl SET enable: OK\n");

	long get_after = prctl_rseq_get();
	if (get_after < 0) {
		fprintf(stderr, "prctl GET after failed: %s\n", strerror(errno));
		return 1;
	}
	printf("prctl GET after: 0x%lx\n", get_after);

	long yielded = syscall(__NR_rseq_slice_yield);
	if (yielded < 0) {
		fprintf(stderr, "rseq_slice_yield failed: %s\n", strerror(errno));
		return 1;
	}
	printf("rseq_slice_yield returned: %ld\n", yielded);

	return 0;
}
