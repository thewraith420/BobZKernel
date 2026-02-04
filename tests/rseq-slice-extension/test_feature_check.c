// SPDX-License-Identifier: GPL-2.0+
/*
 * RSEQ Feature Check - Verify kernel support
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/prctl.h>
#include <errno.h>
#include <string.h>

#ifndef PR_RSEQ_SLICE_EXTENSION
#define PR_RSEQ_SLICE_EXTENSION 79
# define PR_RSEQ_SLICE_EXTENSION_GET 1
# define PR_RSEQ_SLICE_EXTENSION_SET 2
# define PR_RSEQ_SLICE_EXT_ENABLE 0x01
#endif

int main(void)
{
    int rc;
    unsigned long flags;

    printf("RSEQ Time Slice Extension - Feature Check\n");
    printf("==========================================\n\n");

    /* Test 1: Check sysctl exists */
    printf("[1] Checking sysctl...\n");
    FILE *f = fopen("/proc/sys/kernel/rseq_slice_extension_nsec", "r");
    if (f) {
        unsigned int nsec;
        if (fscanf(f, "%u", &nsec) == 1) {
            printf("    ✓ Sysctl exists: %u ns\n", nsec);
        } else {
            printf("    ✗ Sysctl exists but can't read value\n");
        }
        fclose(f);
    } else {
        printf("    ✗ Sysctl not found\n");
        printf("    Kernel may not have CONFIG_RSEQ_SLICE_EXTENSION=y\n");
        return 1;
    }

    /* Test 2: Try to get current setting */
    printf("\n[2] Testing PR_RSEQ_SLICE_EXTENSION_GET...\n");
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_GET,
               0, 0, 0);
    if (rc >= 0) {
        printf("    ✓ prctl GET succeeded\n");
        printf("    Current flags: 0x%x\n", rc);
        if (rc & PR_RSEQ_SLICE_EXT_ENABLE) {
            printf("    Slice extension is ENABLED\n");
        } else {
            printf("    Slice extension is DISABLED\n");
        }
        flags = rc;
    } else {
        printf("    ✗ prctl GET failed: %s\n", strerror(errno));
        if (errno == EINVAL) {
            printf("    Kernel doesn't recognize PR_RSEQ_SLICE_EXTENSION\n");
            printf("    This kernel may not have the RSEQ patches\n");
            return 1;
        }
    }

    /* Test 3: Try to enable */
    printf("\n[3] Testing PR_RSEQ_SLICE_EXTENSION_SET...\n");
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
               PR_RSEQ_SLICE_EXT_ENABLE, 0, 0);
    if (rc == 0) {
        printf("    ✓ prctl SET succeeded\n");
    } else {
        printf("    ✗ prctl SET failed: %s\n", strerror(errno));
        return 1;
    }

    /* Test 4: Verify it's enabled */
    printf("\n[4] Verifying enabled state...\n");
    rc = prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_GET,
               0, 0, 0);
    if (rc >= 0) {
        printf("    ✓ prctl GET succeeded\n");
        printf("    Current flags: 0x%x\n", rc);
        if (rc & PR_RSEQ_SLICE_EXT_ENABLE) {
            printf("    ✓ Slice extension is NOW ENABLED\n");
        } else {
            printf("    ✗ Slice extension still DISABLED (unexpected)\n");
            return 1;
        }
    } else {
        printf("    ✗ prctl GET failed: %s\n", strerror(errno));
        return 1;
    }

    printf("\n==========================================\n");
    printf("✓ ALL CHECKS PASSED\n");
    printf("\nThe RSEQ Time Slice Extension feature is present\n");
    printf("and the prctl interface is working correctly.\n");
    printf("\nNext step: Test actual grant functionality\n");
    printf("(Grants may still be 0 if kernel logic has issues)\n");

    return 0;
}
