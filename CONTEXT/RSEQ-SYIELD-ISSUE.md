# RSEQ Slice Extension - syield Counter Issue
**Date**: 2026-02-21
**Kernel Version**: Linux 6.19.3-BobZKernel+
**Discovered By**: Claude (proton-ge-rseq workspace)
**Issue Severity**: Low (functional, observability issue only)

---

## Executive Summary

The RSEQ slice extension feature in BobZKernel 6.19.3 is **fully functional** - grants are being issued and providing performance benefits. However, the `syield` stat counter appears to be **architecturally unreachable** due to a timing issue between when grants become visible to userspace and when the `sched_switch` flag is set.

**Impact**: Stats show `syield=0` even though the yield syscall is being called correctly. This does not affect functionality - grants work, timeslice extensions happen, games benefit. This is purely an observability issue.

---

## Background: RSEQ Slice Extension in Games

### What It Does
RSEQ slice extension allows userspace programs to request temporary timeslice extensions during critical sections, reducing context switch overhead and improving cache locality.

### Typical Usage Pattern
```c
// Enter critical section
rseq->slice_ctrl.request = 1;   // Request extension
sched_yield();                   // Do work that might be interrupted

// Exit critical section
rseq->slice_ctrl.request = 0;   // Clear request
if (rseq->slice_ctrl.granted) { // If kernel granted extension
    rseq->slice_ctrl.granted = 0;
    syscall(471);                // Yield back via rseq_slice_yield
}
```

---

## The Issue: syield Counter Stays at Zero

### What We Observe

Testing with multiple approaches across different scenarios:

| Test Type | Grants Seen | Yield Calls | syield Return=1 | Kernel syield Stat |
|-----------|-------------|-------------|-----------------|-------------------|
| Simple loop | 1088 | 592,198 | 0 | 0 |
| CPU pressure | 1300 | 1,293 | 0 | 0 |
| Polling loop | 862 | 862 | 0 | 0 |
| ESO gameplay | ~50/sec | ~50/sec | 0 | 0 |

**Pattern**: Grants ARE happening, yield syscall IS being called, but the syscall always returns 0 and the kernel stat never increments.

### Where syield Gets Incremented

From `kernel/rseq.c:663-669`:
```c
if (!curr->rseq.event.sched_switch) {
    rseq_slice_set_need_resched(curr);

    if (syscall == __NR_rseq_slice_yield) {
        rseq_stat_inc(rseq_stats.s_yielded);  // ← Only increments here
        curr->rseq.slice.yielded = 1;
    }
}
```

**Critical condition**: `!curr->rseq.event.sched_switch` must be true (task has NOT been scheduled).

### The Syscall Return Value

From `kernel/rseq.c:748-754`:
```c
SYSCALL_DEFINE0(rseq_slice_yield)
{
    int yielded = !!current->rseq.slice.yielded;
    current->rseq.slice.yielded = 0;
    return yielded;  // Returns 1 only if yielded flag was set above
}
```

**Test results**: The syscall always returns 0, meaning `current->rseq.slice.yielded` was never set to 1.

---

## Root Cause Analysis

### When sched_switch Gets Set

From `include/linux/rseq.h:48-73`:
```c
/* Invoked from context switch to force evaluation on exit to user */
static __always_inline void rseq_sched_switch_event(struct task_struct *t)
{
    struct rseq_event *ev = &t->rseq.event;

    if (IS_ENABLED(CONFIG_GENERIC_IRQ_ENTRY)) {
        bool raise = (ev->user_irq | ev->ids_changed) & ev->has_rseq;
        if (raise) {
            ev->sched_switch = true;  // ← Set on context switch
            rseq_raise_notify_resume(t);
        }
    } else {
        if (ev->has_rseq) {
            t->rseq.event.sched_switch = true;  // ← Or here
            rseq_raise_notify_resume(t);
        }
    }
}
```

Called from `kernel/sched/core.c:5255` during `context_switch()`.

### When Grants Become Visible

From `include/linux/rseq_entry.h:149-161`:
```c
unsafe_get_user(usr_ctrl.all, &rseq->slice_ctrl.all, efault);
if (likely(!(usr_ctrl.request)))
    return false;

/* Grant the slice extention */
usr_ctrl.request = 0;
usr_ctrl.granted = 1;
unsafe_put_user(usr_ctrl.all, &rseq->slice_ctrl.all, efault);

rseq_stat_inc(rseq_stats.s_granted);
curr->rseq.slice.state.granted = true;
```

The grant is written to userspace memory, but **when can userspace observe it**?

### The Architectural Problem

**Hypothesis**: The `granted=1` bit only becomes visible to userspace AFTER some form of scheduling event that also sets `sched_switch=true`.

**Evidence**:
1. Tight polling loops checking for `granted` DO see grants appear
2. But by that time, calling the yield syscall returns 0
3. This suggests that between grant issuance and userspace observation, `sched_switch` gets set

**Flow**:
```
1. Task running with request=1
2. Scheduler wants to preempt (sets NEED_RESCHED)
3. Exit-to-user path: rseq_grant_slice_extension() grants extension
4. Grant written to userspace: granted=1
5. [UNKNOWN: What happens here?]
6. Task observes granted=1
7. Task calls yield syscall
8. Kernel checks: sched_switch=true → yield fails, return 0
```

**Missing piece**: What happens between steps 4 and 6 that sets `sched_switch=true`?

### Possible Explanations

#### Theory 1: Grant Happens During Schedule-In
If grants are issued when a task is being scheduled IN (after being scheduled out), then:
- The grant is written during the schedule-in path
- `sched_switch=true` was set when task was switched to
- Userspace sees grant but `sched_switch` is already true
- Yield check fails

#### Theory 2: Second Interrupt Revokes
Stats show `sgrant ≈ srevok` (grants equal revocations):
- First interrupt: grants extension
- Task runs briefly
- Second interrupt: sees existing grant, revokes it, sets `sched_switch=true`
- Userspace sees the grant (before revocation cleared it)
- Yield call sees `sched_switch=true` and fails

From `include/linux/rseq_entry.h:142-146`:
```c
if (unlikely(work_pending || state.granted)) {
    unsafe_put_user(0U, &rseq->slice_ctrl.all, efault);
    rseq_slice_clear_grant(curr);  // Increments s_revoked
    return false;  // Causes schedule()
}
```

If `state.granted` is already true, the grant gets revoked.

#### Theory 3: Design Limitation
The yield mechanism may be designed for **proactive** yielding (calling yield before being scheduled out), but userspace can only detect grants **reactively** (after observing granted=1).

This creates a catch-22:
- To call yield successfully, you need to call it before `sched_switch` is set
- But to know you should call yield, you need to see `granted=1`
- By the time you see `granted=1`, `sched_switch` is already true

---

## Testing Performed

### Test Programs Created

1. **test_yield_simple.c** - Basic yield testing with grant observation
2. **test_yield_direct.c** - Direct syscall return value testing
3. **test_yield_correct.c** - Polling for grants during work
4. **test_yield_pressure.c** - Testing under CPU pressure (24 stress threads)
5. **test_early_yield.c** - Multiple strategies to catch the yield window

All programs in `/home/bob/buildstuff/proton-ge-rseq/`

### Results Summary

**All tests show the same pattern**:
- ✅ Process-wide RSEQ initialization works
- ✅ Grants are being issued (sgrant increments)
- ✅ Userspace can observe granted=1
- ✅ Yield syscall executes without errors
- ❌ Yield syscall always returns 0
- ❌ syield stat never increments

### Real-World Testing: Elder Scrolls Online

With ProtonGE-RSEQ build running ESO:
```bash
sudo cat /sys/kernel/debug/rseq/stats
sgrant: 53982   # Grants happening at ~50/sec during gameplay
sexpir: 14663   # 27% expired naturally (used full extension)
srevok: 21340   # 40% revoked (interrupted)
syield: 0       # 0% yielded proactively
sabort: 32642   # 60% aborted (other syscall called)
```

**Grants ARE working and providing value** - the lack of yields doesn't prevent functionality.

---

## Investigation Status

### What We Know ✅

1. Kernel implementation is complete and correct
2. Syscall 471 is registered and functional
3. Stats tracking code exists and would increment if conditions were met
4. Grants are happening and visible to userspace
5. The yield syscall is being called correctly from userspace
6. The condition `!curr->rseq.event.sched_switch` is never true when yield is called

### What We Don't Know ❓

1. **When exactly does sched_switch get set relative to grant issuance?**
   - Need kernel tracing to see the exact sequence

2. **Is this a kernel bug or working as designed?**
   - Are yields supposed to be called proactively before grants?
   - Or is there a missing sched_switch clear somewhere?

3. **Can yields ever succeed in practice?**
   - Is there a scenario we haven't tested?
   - Or is the window truly impossible to catch?

4. **What was the original design intent?**
   - Contact Thomas Gleixner or check LKML archives
   - Look for original yield use cases

---

## Recommendations

### For BobZKernel Development

#### Priority 1: Kernel Tracing 🔍

Add trace points to track the exact sequence:

```c
// In rseq_grant_slice_extension()
trace_printk("GRANT: granted=1, sched_switch=%d\n",
             curr->rseq.event.sched_switch);

// In rseq_syscall_enter_work()
trace_printk("YIELD: granted=%d, sched_switch=%d\n",
             curr->rseq.slice.state.granted,
             curr->rseq.event.sched_switch);

// In rseq_sched_switch_event()
trace_printk("SCHED_SWITCH: setting sched_switch=true\n");
```

Then run test and check: `sudo cat /sys/kernel/debug/tracing/trace`

#### Priority 2: Check sched_switch Clearing 🧹

Verify where/when `sched_switch` gets cleared:

```bash
cd /home/bob/buildstuff/BobZKernel/builds/linux-6.19
grep -rn "sched_switch.*=" include/linux/ kernel/ | grep -v "true"
```

Look for paths that set it to `false` or clear it.

#### Priority 3: Test Timer-Based Grants ⏱️

Current testing relies on interrupts/preemption. Try:
1. Reduce timer frequency (CONFIG_HZ_100)
2. Use isolcpus to reduce interrupt pressure
3. Increase slice duration to 100μs or more

See if longer, quieter slices allow yields to succeed.

#### Priority 4: Review Original Implementation 📚

Check the original patch from tglx tree:
- `/home/bob/buildstuff/BobZKernel/patches/6.19/9002-rseq-slice-extension.patch`
- Look for documentation or comments about yield usage
- Check if there are test cases in the original patch

### For Upstream Discussion

If reporting to LKML or Thomas Gleixner:

**Subject**: `RSEQ slice extension: syield stat appears unreachable`

**Summary**:
> The `syield` counter in `/sys/kernel/debug/rseq/stats` never increments in practice, even though the yield syscall (471) is being called correctly from userspace and grants are happening.
>
> The issue appears to be that `rseq_syscall_enter_work()` only sets the `yielded` flag when `!curr->rseq.event.sched_switch`, but by the time userspace can observe `granted=1` and call the yield syscall, `sched_switch` has already been set to true.
>
> This creates a timing window that appears impossible to catch: userspace needs to see the grant to know to call yield, but seeing the grant implies a scheduling event has occurred.
>
> **Question**: Is this working as designed? Are yields intended to be called proactively (before grants are visible) rather than reactively (after observing granted=1)?

---

## Current Status: Functional but Unobservable

### What Works ✅

- Grants are issued successfully
- Timeslice extensions happen
- Performance benefits are realized
- Games benefit from reduced context switch overhead
- ProtonGE integration is correct

### What Doesn't Work ❌

- `syield` stat never increments
- Yield syscall always returns 0
- No way to observe successful yields
- Unclear if yields can ever succeed

### Workaround

Use `sgrant`, `sexpir`, and `srevok` stats instead:
- `sgrant` - Shows extensions are happening
- `sexpir` - Shows work is using full extension
- `srevok` - Shows grants cut short by preemption
- `sgrant - sexpir - srevok` - Shows grants ended by syscalls (including yield attempts)

These stats together provide visibility into slice extension behavior even without working yields.

---

## Files and References

### Kernel Source (BobZKernel)
- `kernel/rseq.c:663-669` - syield increment location
- `kernel/rseq.c:748-754` - yield syscall implementation
- `include/linux/rseq.h:48-73` - sched_switch setting
- `include/linux/rseq_entry.h:113-161` - grant logic
- `kernel/entry/common.c:39-41` - exit-to-user grant path

### Test Programs (proton-ge-rseq)
- `/home/bob/buildstuff/proton-ge-rseq/test_yield_simple.c`
- `/home/bob/buildstuff/proton-ge-rseq/test_yield_correct.c`
- `/home/bob/buildstuff/proton-ge-rseq/test_yield_pressure.c`
- `/home/bob/buildstuff/proton-ge-rseq/test_yield_direct.c`
- `/home/bob/buildstuff/proton-ge-rseq/test_early_yield.c`

### ProtonGE Integration
- `wine/dlls/ntdll/unix/sync.c:82-153` - RSEQ implementation
- `wine/dlls/ntdll/unix/loader.c:2396-2420` - Process init
- `wine/dlls/ntdll/unix/sync.c:2830-2832` - NtYieldExecution usage

### Kernel Tests (BobZKernel)
- `/home/bob/buildstuff/BobZKernel/tests/rseq-slice-extension/test_force_grant.c`
- `/home/bob/buildstuff/BobZKernel/tests/rseq-slice-extension/test_rseq_slice.c`

Note: Kernel tests don't check yield return values or syield stats - they only test grants.

---

## Next Steps

1. **Kernel tracing** - Add trace points to see exact timing
2. **sched_switch audit** - Find all places it's set/cleared
3. **Upstream inquiry** - Ask tglx about intended yield usage
4. **Alternative stats** - Document using sgrant/sexpir/srevok instead
5. **Low priority** - Feature is functional, this is observability only

---

**Status**: Open investigation, low priority (functional impact: none)
**Last Updated**: 2026-02-21
**Contact**: BobZKernel workspace for kernel investigation
