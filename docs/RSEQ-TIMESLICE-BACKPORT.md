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
**Patch File**: `patches/0002-rseq-timeslice-extension.patch`

### Manual Backport Progress

Given the significant API differences between 6.18 and 6.19, a manual backport approach was taken:

**Completed Patches**:
- ✅ **Patch 1/11** (b545599f7215): Add fields and constants for time slice extension
  - Adapted `scoped_user_write_access()` to `put_user()` API
  - Created `include/linux/rseq_types.h` with slice structures
  - Added CONFIG_RSEQ_SLICE_EXTENSION to Kconfig
  - Added documentation (Documentation/userspace-api/rseq.rst)

- ✅ **Patch 2/11** (4562c1e5576d): Provide static branch for time slice extensions
  - Created minimal `include/linux/rseq_entry.h` (6.18 doesn't have full RSEQ infrastructure)
  - Added `rseq_slice_ext=` kernel parameter support
  - Added DEFINE_STATIC_KEY_TRUE(rseq_slice_extension_key)

- ⏭️ **Patch 3/11** (1d9c474c7a05): Add statistics for time slice extensions
  - **SKIPPED** - CONFIG_RSEQ_STATS infrastructure doesn't exist in 6.18
  - Not essential for core functionality

- ✅ **Patch 4/11** (b7b27be2636a): Add prctl() to enable time slice extensions
  - Added PR_RSEQ_SLICE_EXTENSION prctl command
  - Added `rseq_slice` field to task_struct (6.18 uses flat structure, not rseq_data)
  - Adapted to use `current->rseq` instead of `current->rseq.usrptr`
  - Fixed rseq_slice_state structure (u16 with enabled/granted, not u32)

**Remaining Patches (TODO)**:
- ❓ **Patch 5/11** (9d8bb27ebab0): Implement sys_rseq_slice_yield()
  - New syscall implementation needed
  - Syscall number allocation required

- ❓ **Patch 6/11** (6e87390567d1): Implement syscall entry work for time slice extensions
  - Entry/exit path modifications

- ❓ **Patch 7/11** (c3b2c0b3d780): Implement time slice extension enforcement timer
  - Timer infrastructure for enforcement

- ❓ **Patch 8/11** (4287abafd9b6): Reset slice extension when scheduled
  - Scheduler integration

- ❓ **Patch 9/11** (04c29fb4e2ed): Implement rseq_grant_slice_extension()
  - Core granting logic

- ❓ **Patch 10/11** (5af65b6241f7): entry: Hook up rseq time slice extension
  - Entry code integration

- ❓ **Patch 11/11** (baecc27d71da): selftests/rseq: Implement time slice extension test
  - Testing infrastructure

### Current Status Summary

**Patches Backported**: 3 out of 11 (patches 1, 2, 4)
**Functionality Level**: ~27% - Basic infrastructure only, no runtime functionality yet
**Build Integration**: Patch applied automatically on rseq-timeslice branch
**Compilation Status**: Not tested - remaining patches needed for complete feature

### Key Differences Between 6.18 and 6.19

1. **RSEQ Infrastructure**: 6.19 has enhanced RSEQ support compared to 6.18
2. **Header Files**: `include/linux/rseq_entry.h` doesn't exist in 6.18
3. **Scheduler Changes**: Core scheduler differences will cause conflicts
4. **Syscall Numbers**: New syscall #471 needs to be added to syscall tables

### Detailed API Adaptations for 6.18

#### 1. User Space Access API Changes

**6.19 Upstream Code**:
```c
scoped_user_write_access(&rseq->flags, &rseq->slice_ctrl.all, efault) {
    unsafe_put_user(rseqfl, &rseq->flags, efault);
    unsafe_put_user(0U, &rseq->slice_ctrl.all, efault);
}
```

**6.18 Adapted Code**:
```c
if (put_user(rseqfl, &rseq->flags))
    return -EFAULT;
if (put_user(0U, &rseq->slice_ctrl.all))
    return -EFAULT;
```

**Rationale**: 6.18 doesn't have the `scoped_user_write_access()` macro which provides automatic cleanup semantics. Reverted to traditional `put_user()` approach.

#### 2. Task Structure Differences

**6.19 Structure** (struct rseq_data):
```c
struct rseq_data {
    struct rseq __user *usrptr;
    u32 len;
    u32 sig;
    struct rseq_event event;
    struct rseq_ids ids;
    struct rseq_slice slice;
};
```

**6.18 Adapted** (direct fields in task_struct):
```c
struct task_struct {
    ...
    struct rseq __user *rseq;      // Direct pointer, not in rseq_data
    u32 rseq_len;
    u32 rseq_sig;
    struct rseq_slice rseq_slice;  // Added field for slice extension
    ...
};
```

**Code Adaptations**:
- `current->rseq.usrptr` → `current->rseq`
- `current->rseq.slice` → `current->rseq_slice`
- `current->rseq.len` → `current->rseq_len`

#### 3. RSEQ Slice State Structure

**Initial Incorrect Structure** (from early patch inspection):
```c
union rseq_slice_state {
    u32 all;
    struct {
        u8 request;
        u8 granted;
        u16 __reserved;
    };
};
```

**Corrected Structure** (actual 6.19 definition):
```c
union rseq_slice_state {
    u16 state;
    struct {
        u8 enabled;   // Not "request"
        u8 granted;
    };
};
```

#### 4. Minimal Header Creation

Created minimal `include/linux/rseq_entry.h` with only what's needed for timeslice:

```c
#ifdef CONFIG_RSEQ_SLICE_EXTENSION
DECLARE_STATIC_KEY_TRUE(rseq_slice_extension_key);

static __always_inline bool rseq_slice_extension_enabled(void)
{
    return static_branch_likely(&rseq_slice_extension_key);
}
#endif
```

**Omitted from 6.18 backport** (exists in full 6.19 version):
- `struct rseq_stats` - Requires CONFIG_RSEQ_STATS infrastructure
- `rseq_exit_to_user_mode_restart()` - Requires GENERIC_ENTRY changes
- `rseq_update_user_cs()` - Complex fast-path RSEQ logic
- Event tracking infrastructure - Part of broader 6.19 RSEQ rewrite

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
