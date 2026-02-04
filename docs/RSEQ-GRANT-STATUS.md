# RSEQ Slice Extension Status

## Summary

The RSEQ time slice extension has been **partially backported** to Linux 6.18.8. The infrastructure is in place and functional, but the **scheduler integration for granting time slices is missing**.

## What's Working ✅

All of the following components have been successfully backported and are functional:

1. **Syscall Interface** (`#470: rseq_slice_yield`)
   - Syscall is registered and callable
   - Returns 0 (not 1 because grants aren't happening)
   
2. **Prctl Interface** (`PR_RSEQ_SLICE_EXTENSION`)
   - `PR_RSEQ_SLICE_EXTENSION_GET`: Returns 0 (disabled) or 1 (enabled)
   - `PR_RSEQ_SLICE_EXTENSION_SET`: Enables/disables extension for task
   - Updates `rseq->flags` correctly

3. **Sysctl Configuration** (`kernel.rseq_slice_extension_nsec`)
   - Visible at `/proc/sys/kernel/rseq_slice_extension_nsec`
   - Tunable range: 10-50 microseconds (10000-50000 ns)
   - Default: 30 microseconds (30000 ns)

4. **Timer Infrastructure**
   - Per-CPU hrtimers set up in `rseq_slice_init()`
   - Timer callback `rseq_slice_expired()` ready to revoke grants
   - Timer cancellation on syscall entry

5. **Task State**
   - `task_struct->rseq_slice` field added
   - Contains `.state.enabled`, `.state.granted`, `.yielded`

6. **User-Kernel Communication**
   - `rseq->slice_ctrl.request` writable from userspace
   - `rseq->slice_ctrl.granted` readable from userspace
   - glibc 2.41 provides `__rseq_abi` thread-local variable

7. **Syscall Entry Work**
   - `rseq_syscall_enter_work()` clears grants on syscall entry
   - `SYSCALL_WORK_SYSCALL_RSEQ_SLICE` work flag

## What's Missing ❌

The **scheduler integration** that actually grants time slice extensions is not included in the backport. Specifically:

### Missing Component: Grant Mechanism

In Linux 6.20, the scheduler checks for slice extension requests during task scheduling. The missing code should:

1. **Check request bit** during scheduler operations (likely in `pick_next_task()` or task selection)
2. **Validate conditions** for granting (task enabled, not already granted, etc.)
3. **Set grant in kernel state**: `current->rseq_slice.state.granted = 1`
4. **Update userspace**: `put_user(0x0101, &current->rseq->slice_ctrl.all)` (request=1, granted=1)
5. **Start timer**: Arm the per-CPU hrtimer to enforce the extension limit
6. **Set syscall work**: `set_task_syscall_work(current, SYSCALL_WORK_SYSCALL_RSEQ_SLICE)`

### Why This Matters

Without the scheduler integration:
- Userspace can set `slice_ctrl.request = 1` ✅
- But kernel never sets `slice_ctrl.granted = 1` ❌
- The timer is never started ❌  
- Tasks don't actually get extended time slices ❌

## Test Results

### Infrastructure Test (`test_slice_infrastructure.c`)

```
=== RSEQ Slice Extension Infrastructure Test ===

✓ glibc __rseq_abi available at: 0x7ea448a44740
✓ prctl GET (before enable): 0x0 (expected 0x0)
✓ prctl SET enable: success
✓ prctl GET (after enable): 0x1 (expected 0x1)
✓ rseq_slice_yield() returned: 0
✓ sysctl kernel.rseq_slice_extension_nsec = 30000 ns (30 µs)
✓ slice_ctrl.request writable from userspace

Testing manual slice_ctrl manipulation...
Initial slice_ctrl: request=0 granted=0
After setting request=1: request=1 granted=0  ← Grant never happens!
```

### Grant Detection Test (`test_grant_detection.c`)

```
Requesting grant...
Spinning to trigger grant...
  [100000] slice_ctrl: 0x00000001 (req=1 grant=0)
  ...
  [900000] slice_ctrl: 0x00000001 (req=1 grant=0)

❌ No grant detected after 1M iterations
```

The request bit stays at 1, but granted never becomes 1 because the scheduler isn't checking for requests.

## Verification

The missing scheduler integration can be confirmed by:

1. **Patch Analysis**: No `kernel/sched/*.c` files in `0002-rseq-timeslice-extension.patch`
2. **Symbol Search**: No `rseq_slice_check_grant` or similar symbols in `/proc/kallsyms`
3. **Runtime Behavior**: Requests never result in grants
4. **Code Review**: `kernel/rseq.c` has grant revocation but no grant logic

## Next Steps to Complete the Backport

To make grants actually work, we need to add scheduler integration:

### Option 1: Find and Apply Missing Scheduler Patch

Look for additional patches in Linux 6.20 development that modify `kernel/sched/core.c` or `kernel/sched/fair.c` to add RSEQ slice extension support.

### Option 2: Manually Implement Scheduler Integration

Add code to the scheduler (likely in `kernel/sched/core.c`) to:

```c
static void rseq_check_and_grant_slice(struct task_struct *p)
{
	u8 request;
	
	if (!p->rseq || !p->rseq_slice.state.enabled)
		return;
		
	if (get_user(request, &p->rseq->slice_ctrl.request))
		return;
		
	if (request && !p->rseq_slice.state.granted) {
		/* Grant the slice extension */
		p->rseq_slice.state.granted = 1;
		
		/* Update userspace */
		put_user(0x0101, &p->rseq->slice_ctrl.all);
		
		/* Start enforcement timer */
		struct slice_timer *st = this_cpu_ptr(&slice_timer);
		st->cookie = p;
		hrtimer_start(&st->timer, ns_to_ktime(rseq_slice_ext_nsecs),
		              HRTIMER_MODE_REL_PINNED_HARD);
		
		/* Set syscall work flag */
		set_task_syscall_work(p, SYSCALL_WORK_SYSCALL_RSEQ_SLICE);
	}
}
```

Call this from an appropriate scheduler hook, likely:
- `pick_next_task()` in `kernel/sched/core.c`
- Or in the task selection path for CFS/BORE scheduler

### Option 3: Wait for Full 6.20 Backport

Wait for the full 6.20 kernel to be released and available for your distribution, which should include complete scheduler integration.

## Conclusion

**Status**: Backport is 80% complete

- ✅ All userspace-facing APIs work
- ✅ All kernel infrastructure in place
- ✅ Timer and revocation mechanisms ready
- ❌ Scheduler doesn't check requests or issue grants

**Impact**: The extension can be enabled and configured, but doesn't actually affect scheduling behavior.

**Recommended Action**: Complete the scheduler integration to make grants functional.
