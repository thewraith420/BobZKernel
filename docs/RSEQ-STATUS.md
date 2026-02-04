# RSEQ Time Slice Extension Backport - Current Status

## Summary

**Patches Complete**: 4 out of 11 (36% complete)
**Functionality**: Basic infrastructure + syscall interface  
**Runtime Status**: Non-functional - requires scheduler/entry integration (patches 6-11)

## Completed Work

### ✅ Patch 1/11: Core Infrastructure
- Added `slice_ctrl` structure to `struct rseq` 
- Created `include/linux/rseq_types.h`
- Added CONFIG_RSEQ_SLICE_EXTENSION Kconfig option
- User documentation in Documentation/userspace-api/rseq.rst
- **API Adaptation**: Replaced 6.19's `scoped_user_write_access()` with 6.18's `put_user()`

### ✅ Patch 2/11: Static Branch Control
- Created minimal `include/linux/rseq_entry.h`
- Added `rseq_slice_ext=` kernel parameter
- DEFINE_STATIC_KEY_TRUE(rseq_slice_extension_key)

### ⏭️ Patch 3/11: Statistics (SKIPPED)
- Requires CONFIG_RSEQ_STATS infrastructure not present in 6.18
- Not essential for functionality

### ✅ Patch 4/11: User Control via prctl()
- PR_RSEQ_SLICE_EXTENSION prctl command (GET/SET)
- Added `rseq_slice` field to task_struct
- **API Adaptation**: Uses `current->rseq` not `current->rseq.usrptr` (6.18's flat structure)

### ✅ Patch 5/11: sys_rseq_slice_yield() Syscall  
- New syscall #470 for yielding after time slice extension
- Added to x86_64 and x86_32 syscall tables
- SYSCALL_DEFINE0(rseq_slice_yield) implementation
- **API Adaptation**: Uses `current->rseq_slice.yielded` not `current->rseq.slice.yielded`

## Remaining Work (Non-Functional Without These)

### ❓ Patch 6/11: Syscall Entry Work
**Complexity**: High  
**Files**: kernel/entry/syscall-common.c, include/linux/entry-common.h, include/linux/thread_info.h  
**Purpose**: Hook syscall entry to handle time slice revocation on syscalls  
**Challenge**: 6.18 vs 6.19 entry infrastructure differences  
**Estimated Effort**: 4-6 hours

### ❓ Patch 7/11: Enforcement Timer
**Complexity**: High  
**Files**: kernel/rseq.c, include/linux/hrtimer.h  
**Purpose**: Enforce time limit on slice extensions (~30µs)  
**Challenge**: Timer integration, interrupt handling  
**Estimated Effort**: 3-4 hours

### ❓ Patch 8/11: Scheduler Integration - Reset on Schedule
**Complexity**: High  
**Files**: kernel/sched/core.c  
**Purpose**: Clear slice extension state when task is scheduled out  
**Challenge**: BORE scheduler modifications, context switch integration  
**Estimated Effort**: 3-4 hours

### ❓ Patch 9/11: Grant Logic
**Complexity**: Very High  
**Files**: kernel/rseq.c, kernel/sched/core.c  
**Purpose**: Core logic to grant time slice extensions on interrupt  
**Challenge**: Interrupt path integration, scheduling policy interaction  
**Estimated Effort**: 6-8 hours

### ❓ Patch 10/11: Entry Path Hooks
**Complexity**: High  
**Files**: kernel/entry/common.c, arch/x86/entry/*.c  
**Purpose**: Hook entry points to check for extension requests  
**Challenge**: x86-specific entry code, interrupt vs syscall paths  
**Estimated Effort**: 4-5 hours

### ❓ Patch 11/11: Selftests
**Complexity**: Medium  
**Files**: tools/testing/selftests/rseq/*  
**Purpose**: Testing infrastructure  
**Estimated Effort**: 2-3 hours

## Total Remaining Effort Estimate

**Hours**: 22-30 hours of focused kernel development work  
**Risk Level**: High - touches core scheduler and entry paths  
**Testing Required**: Extensive - boot testing, stress testing, gaming workloads

## Current Build Status

- **Patch File**: `patches/0002-rseq-timeslice-extension.patch` (499 lines)
- **Build Integration**: Automated on `rseq-timeslice` branch
- **Compilation**: Untested - would likely fail due to incomplete infrastructure
- **Runtime**: Non-functional without patches 6-11

## Recommendations

### Option 1: Continue Backport (High Effort)
- Commit to completing patches 6-11
- Expect 22-30 hours of work
- High risk of subtle bugs
- Extensive testing required
- Gaming benefit uncertain until tested

### Option 2: Wait for Upstream (Recommended)
- Linux 7.0 expected April 2026 (~2 months)
- Cleaner backport from tested code
- Less risk of introducing bugs
- Can evaluate real-world gaming benefits from community feedback first

### Option 3: Hybrid Approach
- Keep current infrastructure in experimental branch
- Monitor upstream progress and gaming community feedback
- Resume backport if proven valuable OR
- Wait for 7.0 and do cleaner backport

## Key Architectural Differences (6.18 vs 6.19)

| Component | 6.19 Upstream | 6.18 BobZKernel |
|-----------|---------------|-----------------|
| Task rseq pointer | `current->rseq.usrptr` | `current->rseq` |
| Slice state | `current->rseq.slice` | `current->rseq_slice` |
| User access | `scoped_user_write_access()` | `put_user()` / `get_user()` |
| Task structure | Consolidated `rseq_data` | Flat fields in task_struct |
| Entry infrastructure | Enhanced GENERIC_ENTRY | Traditional entry paths |

## Git History

```
3637326 Add RSEQ sys_rseq_slice_yield() syscall (patch 5/11)
921277b Add RSEQ Time Slice Extension backport (patches 1-2 and 4/11)
62f1d78 Update RSEQ backport documentation with manual backport progress
```

## References

- Upstream series: git://git.kernel.org/pub/scm/linux/kernel/git/tglx/devel.git rseq/slice
- LKML discussion: https://lore.kernel.org/lkml/[thread-id]
- Target kernel: Linux 7.0 (6.20) - April 2026
- BobZKernel base: 6.18.8 with BORE scheduler, Full LTO, BBRv3
