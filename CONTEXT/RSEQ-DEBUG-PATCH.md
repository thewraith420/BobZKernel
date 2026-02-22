# RSEQ Slice Extension Debug Trace Patch

To investigate the `syield` counter issue, add these trace points to the kernel:

## Location 1: Grant Issuance

**File**: `include/linux/rseq_entry.h`
**Function**: `rseq_grant_slice_extension()`
**After line where granted=1 is set**:

```c
unsafe_put_user(usr_ctrl.all, &rseq->slice_ctrl.all, efault);

rseq_stat_inc(rseq_stats.s_granted);
curr->rseq.slice.state.granted = true;

// ADD THIS:
trace_printk("RSEQ_GRANT: pid=%d granted=1 sched_switch=%d\n",
             curr->pid, curr->rseq.event.sched_switch);
```

## Location 2: Yield Syscall Entry

**File**: `kernel/rseq.c`
**Function**: `rseq_syscall_enter_work()`
**Around the yield check (line ~663)**:

```c
if (!curr->rseq.event.sched_switch) {
    rseq_slice_set_need_resched(curr);

    if (syscall == __NR_rseq_slice_yield) {
        // ADD THIS BEFORE:
        trace_printk("RSEQ_YIELD_WILL_SET: pid=%d granted=%d sched_switch=%d\n",
                     curr->pid, curr->rseq.slice.state.granted,
                     curr->rseq.event.sched_switch);

        rseq_stat_inc(rseq_stats.s_yielded);
        curr->rseq.slice.yielded = 1;
    }
} else {
    // ADD THIS:
    if (syscall == __NR_rseq_slice_yield) {
        trace_printk("RSEQ_YIELD_BLOCKED: pid=%d granted=%d sched_switch=%d\n",
                     curr->pid, curr->rseq.slice.state.granted,
                     curr->rseq.event.sched_switch);
    }
}
```

## Location 3: Revocation

**File**: `include/linux/rseq_entry.h`
**Function**: `rseq_grant_slice_extension()`
**In the revocation path**:

```c
if (unlikely(work_pending || state.granted)) {
    // ADD THIS:
    trace_printk("RSEQ_REVOKE: pid=%d work_pending=%d already_granted=%d\n",
                 curr->pid, work_pending, state.granted);

    unsafe_put_user(0U, &rseq->slice_ctrl.all, efault);
    rseq_slice_clear_grant(curr);
    return false;
}
```

## Location 4: sched_switch Setting

**File**: `include/linux/rseq.h`
**Function**: `rseq_sched_switch_event()`
**Where sched_switch is set**:

```c
ev->sched_switch = true;

// ADD THIS:
trace_printk("RSEQ_SCHED_SWITCH: pid=%d setting sched_switch=true\n",
             t->pid);
```

## How to Use

1. Apply the trace_printk additions to the kernel source
2. Rebuild kernel (just the RSEQ parts will recompile)
3. Install and reboot
4. Enable tracing:
   ```bash
   sudo sh -c 'echo 1 > /sys/kernel/debug/tracing/tracing_on'
   sudo sh -c 'echo > /sys/kernel/debug/tracing/trace'  # Clear buffer
   ```
5. Run a test program (like test_yield_pressure)
6. View trace:
   ```bash
   sudo cat /sys/kernel/debug/tracing/trace
   ```

## Expected Output

You should see a sequence like:
```
RSEQ_GRANT: pid=12345 granted=1 sched_switch=0
RSEQ_SCHED_SWITCH: pid=12345 setting sched_switch=true
RSEQ_YIELD_BLOCKED: pid=12345 granted=1 sched_switch=1
```

This would confirm the timing issue: grant happens, then sched_switch is set, then yield is blocked.

OR if we're lucky:
```
RSEQ_GRANT: pid=12345 granted=1 sched_switch=0
RSEQ_YIELD_WILL_SET: pid=12345 granted=1 sched_switch=0
```

Which would mean yields CAN succeed in some scenarios.

## Alternative: Use ftrace

Instead of trace_printk, you can add proper trace events, but that's more work. trace_printk is quick and dirty for debugging.

## Clean Up After

Remember to remove trace_printk calls before any production use - they have performance overhead.
