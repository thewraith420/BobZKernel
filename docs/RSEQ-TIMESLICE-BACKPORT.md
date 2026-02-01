# RSEQ Time Slice Extension Backport to 6.18.8

## Overview

The RSEQ Time Slice Extension is a new kernel feature being developed by Thomas Gleixner for Linux 7.0 (6.20). It provides "opportunistic priority ceiling without the overhead of an actual priority ceiling protocol" - essentially allowing critical sections to request brief time slice extensions to avoid being preempted mid-operation.

**Gaming Benefit**: Eliminates micro-stutters caused by background tasks stealing CPU time during critical frame calculations or audio processing.

## Patch Series Information

- **Version**: V6 (11 patches)
- **Author**: Thomas Gleixner
- **Target Kernel**: Linux 6.19-rc1 / 7.0
- **Upstream Status**: Under review, expected in 7.0 (April 2026)
- **Git Repository**: `git://git.kernel.org/pub/scm/linux/kernel/git/tglx/devel.git`
- **Branch**: `rseq/slice`

## Patch List (11 patches)

1. **b545599f7215** - rseq: Add fields and constants for time slice extension
2. **4562c1e5576d** - rseq: Provide static branch for time slice extensions
3. **1d9c474c7a05** - rseq: Add statistics for time slice extensions
4. **b7b27be2636a** - rseq: Add prctl() to enable time slice extensions
5. **9d8bb27ebab0** - rseq: Implement sys_rseq_slice_yield()
6. **6e87390567d1** - rseq: Implement syscall entry work for time slice extensions
7. **c3b2c0b3d780** - rseq: Implement time slice extension enforcement timer
8. **4287abafd9b6** - rseq: Reset slice extension when scheduled
9. **04c29fb4e2ed** - rseq: Implement rseq_grant_slice_extension()
10. **5af65b6241f7** - entry: Hook up rseq time slice extension
11. **baecc27d71da** - selftests/rseq: Implement time slice extension test

## Backport Status

**Branch**: `rseq-timeslice` (experimental)

### Initial Cherry-Pick Attempt

Attempted to cherry-pick all 11 commits from tglx/rseq/slice:

```bash
git cherry-pick b545599f7215..baecc27d71da
```

**Results**:
- ✅ **Patch 1/11**: Applied successfully
- ✅ **Patch 2/11**: Applied with minor conflict (include/linux/rseq_entry.h modify/delete resolved)
- ⚠️ **Patch 3/11**: Conflict in kernel/rseq.c (stopped here)
- ❓ **Patches 4-11**: Not attempted yet

### Detailed Analysis (Second Attempt)

Individual patch cherry-pick revealed deeper API incompatibilities:

**Patch 1/11 Conflicts Found**:
1. ✅ `include/linux/rseq_types.h` - Modify/delete (resolved by accepting file)
2. ✅ `init/Kconfig` - Added three new config options (resolved cleanly)
3. ⚠️ **`kernel/rseq.c` - Critical API Mismatch**:
   - **6.19 code uses**: `scoped_user_write_access()` macro with cleanup semantics
   - **6.18 has**: Traditional `access_ok()` + manual `put_user()` approach
   - **Impact**: Core RSEQ registration flow is fundamentally different
   - **Required**: Manual API translation, not simple conflict resolution

**Conclusion**: This backport requires significant manual adaptation of each patch to 6.18 APIs, not just conflict resolution.

### Key Differences Between 6.18 and 6.19

1. **RSEQ Infrastructure**: 6.19 has enhanced RSEQ support compared to 6.18
2. **Header Files**: `include/linux/rseq_entry.h` created by patch 2
3. **Scheduler Changes**: Core scheduler differences will cause conflicts
4. **Syscall Numbers**: New syscall #471 needs to be added to syscall tables

### Files Modified (from patch series)

- `Documentation/admin-guide/kernel-parameters.txt`
- `Documentation/admin-guide/sysctl/kernel.rst`
- `include/linux/rseq_entry.h` (new file)
- `include/linux/rseq_types.h`
- `include/uapi/linux/rseq.h`
- `kernel/rseq.c`
- `kernel/sched/core.c`
- `kernel/entry/common.c`
- Architecture-specific syscall tables
- Selftests

## Backport Strategy

### Option 1: Complete Manual Backport (Current Approach)

1. Cherry-pick patches one at a time from tglx/rseq/slice
2. Manually resolve conflicts as they arise
3. Test each patch to ensure it doesn't break existing functionality
4. Create a unified patch file for integration into build system

**Pros**: Full feature implementation, stays close to upstream
**Cons**: Time-consuming, requires deep kernel knowledge, higher risk

### Option 2: Wait for Mainline Integration

1. Wait for patches to land in Linux 7.0 (April 2026)
2. Backport from stable 7.0 release
3. Less conflict resolution needed as code will be tested

**Pros**: Safer, tested code, clearer migration path
**Cons**: Delayed availability (3+ months)

### Option 3: Incremental Backport

1. Apply core functionality patches (1-4) only
2. Skip advanced features (enforcement timer, selftests)
3. Create minimal working implementation

**Pros**: Faster to implement, lower risk
**Cons**: Incomplete feature set, may miss key benefits

## Integration Plan

Once backport is complete, integrate into build workflow similar to revocable:

1. Create patch file: `patches/0002-rseq-timeslice-extension.patch`
2. Update `scripts/update-and-build.sh` to apply patch after revocable
3. Add step: "Applying RSEQ Time Slice Extension"
4. Test on all branches (master, generic-build, pixel-slate, workpc)

## Testing Requirements

1. **Compilation**: Kernel must build without errors
2. **Boot**: System must boot successfully
3. **Functional**: RSEQ functionality must work (verify via `/proc/kallsyms`)
4. **Performance**: Test gaming workloads for stutter reduction
5. **Stability**: No crashes or hangs under normal operation

## References

- [LKML: Thomas Gleixner: [patch V6 00/11] rseq: Implement time slice extension mechanism](https://lkml.org/lkml/2025/12/15/1095)
- [LKML: Thomas Gleixner: [patch V6 07/11] rseq: Implement time slice extension enforcement timer](https://lkml.org/lkml/2025/12/15/1082)
- [Git Repository](git://git.kernel.org/pub/scm/linux/kernel/git/tglx/devel.git) (branch: rseq/slice)

## Next Steps

1. Review each patch individually to understand changes
2. Map 6.19 RSEQ infrastructure to 6.18 equivalents
3. Manually apply patches with adaptations for 6.18
4. Create comprehensive test plan
5. Document any behavioral differences from upstream

## Notes

- This is an **experimental feature** on a dedicated branch
- Fallback is simple: `git checkout master`
- Consider this a learning exercise and preparation for when feature goes mainline
- Gaming performance improvements may vary depending on workload
