# RSEQ Timeslice Extension Patches

## Patch Files

### 0001-revocable-resource-management.patch
Revocable resource management infrastructure (not RSEQ-related).

### 0002-rseq-timeslice-extension.patch
**Main RSEQ timeslice extension backport** from Linux 7.0 to 6.18.

This is the primary patch that adds:
- RSEQ time slice extension infrastructure
- prctl() API (PR_RSEQ_SLICE_EXTENSION)
- sys_rseq_slice_yield() syscall
- Scheduler integration
- Grant logic
- Timer enforcement

**Known Issue**: This patch was created against an older kernel baseline
and may not apply cleanly to `include/uapi/linux/rseq.h` due to upstream
changes (mm_cid field addition, flags documentation updates).

### 0003-rseq-timeslice-debian-fixes.patch
**Supplemental fix patch** for building on Debian 13 with updated kernel baseline.

This patch ensures these critical files have correct content:
- `include/linux/rseq_entry.h` - Complete rseq_grant_slice_extension() function
- `include/uapi/linux/rseq.h` - RSEQ slice extension UAPI structures and flags

**Why needed**: When the main RSEQ patch (0002) fails to apply cleanly due to
baseline mismatches, this patch fills in the gaps.

## Application Order

Patches are applied in numerical order by `scripts/apply-patches.sh`:
1. 0001-revocable-resource-management.patch
2. 0002-rseq-timeslice-extension.patch
3. 0003-rseq-timeslice-debian-fixes.patch (NEW)

The third patch is idempotent - if the second patch applied cleanly, the
third patch will detect the changes are already present and succeed with
no modifications.

## Testing

After applying all patches, verify RSEQ infrastructure:

```bash
# Check kernel symbols
sudo grep rseq_slice /proc/kallsyms

# Check sysctl
cat /proc/sys/kernel/rseq_slice_extension_nsec

# Run test suite (after kernel is built and installed)
cd /home/bob/buildstuff/BobZKernel/tests/rseq-slice-extension
./run_all_tests.sh
```

## Maintenance

If you update to a newer kernel version (e.g., 6.18.9+):

1. The patches will attempt to apply automatically
2. If patch 0002 fails, patch 0003 will ensure critical files are correct
3. You may need to resolve conflicts manually if structure layouts change significantly
4. Commit any manual fixes to the kernel source tree

## glibc 2.41 Compatibility

This setup is specifically tested with:
- Debian 13 (Trixie)
- glibc 2.41 (first version with proper RSEQ userspace support)
- Clang 19 for kernel, GCC for host tools (objtool)

The GCC-for-host-tools requirement is handled in `scripts/build-kernel.sh`
to work around glibc 2.41 time64 symbol issues.
