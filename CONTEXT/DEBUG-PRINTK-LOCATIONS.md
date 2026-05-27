# Debug printk Locations for RSEQ Investigation

This document records all debug printk statements added during RSEQ debugging, in case they need to be re-added later.

## File: kernel/rseq.c

### Location 1: rseq_slowpath_update_usr() - Event tracking
**Lines: ~291-300** (inside scoped_guard(irq) block)

```c
scoped_guard(irq) {
    /* Check what events are set */
    bool sched = t->rseq.event.sched_switch;
    bool ids_chg = t->rseq.event.ids_changed;
    bool usr_irq = t->rseq.event.user_irq;

    if (sched || ids_chg || usr_irq) {
        printk(KERN_INFO "RSEQ_EVENTS: pid=%d sched=%d ids=%d irq=%d\n",
               t->pid, sched, ids_chg, usr_irq);
    }

    event = sched;
    if (event) {
        printk(KERN_INFO "RSEQ_CLEAR: pid=%d clearing sched_switch\n", t->pid);
    }
    t->rseq.event.all &= evt_mask.all;
```

### Location 2: rseq_syscall_enter_work() - Yield tracking
**Entire function with debug messages**

```c
void rseq_syscall_enter_work(long syscall)
{
    struct task_struct *curr = current;
    struct rseq_slice_ctrl ctrl = { .granted = curr->rseq.slice.state.granted };

    if (syscall == __NR_rseq_slice_yield)
        printk(KERN_INFO "RSEQ_YIELD_ENTER: pid=%d granted=%d\n", curr->pid, ctrl.granted);

    clear_task_syscall_work(curr, SYSCALL_RSEQ_SLICE);

    if (!ctrl.granted) {
        if (syscall == __NR_rseq_slice_yield)
            printk(KERN_INFO "RSEQ_YIELD_NO_GRANT: pid=%d grant already revoked\n", curr->pid);
        return;
    }

    if (!curr->rseq.event.sched_switch) {
        if (syscall == __NR_rseq_slice_yield) {
            printk(KERN_INFO "RSEQ_YIELD_WILL_SET: pid=%d granted=%d sched_switch=%d\n",
                     curr->pid, curr->rseq.slice.state.granted,
                     curr->rseq.event.sched_switch);
            rseq_stat_inc(rseq_stats.s_yielded);
            curr->rseq.slice.yielded = 1;
        }
    } else {
        if (syscall == __NR_rseq_slice_yield) {
            printk(KERN_INFO "RSEQ_YIELD_BLOCKED: pid=%d granted=%d sched_switch=%d\n",
                     curr->pid, curr->rseq.slice.state.granted,
                     curr->rseq.event.sched_switch);
        }
    }
}
```

## File: include/linux/rseq.h

### Location: rseq_set_event_sched_switch() - Tracking when sched_switch is set
**Around line where sched_switch is set to true**

```c
if (raise) {
    ev->sched_switch = true;
    printk(KERN_INFO "RSEQ_SCHED_SWITCH: pid=%d setting sched_switch=true (raise path)\n", t->pid);
    rseq_raise_notify_resume(t);
}
```

## File: include/linux/rseq_entry.h

### Location: Multiple places where grant/revoke/clear happens

**Note:** We tried adding printk here but it's in unsafe_put_user() context where printk cannot execute.
These debug points did NOT work and should not be re-added:

```c
// DON'T USE - These are in unsafe context and won't work:
// - Around line ~730 in rseq_irqentry_exit_to_user_mode()
// - Around line ~747 in rseq_irqentry_exit_to_user_mode()
// - Around line ~769 in rseq_irqentry_exit_to_user_mode()
```

## Purpose of Each Debug Point

1. **RSEQ_EVENTS / RSEQ_CLEAR** - Track when slowpath processes events and clears sched_switch flag
2. **RSEQ_YIELD_ENTER** - Track when yield syscall is called
3. **RSEQ_YIELD_NO_GRANT** - Track yield attempts when grant already revoked
4. **RSEQ_YIELD_WILL_SET** - Track successful yield registration
5. **RSEQ_YIELD_BLOCKED** - Track yield attempts blocked by existing sched_switch
6. **RSEQ_SCHED_SWITCH** - Track every time sched_switch flag is raised

## How to View Output

```bash
# View all RSEQ debug messages
sudo dmesg | grep "RSEQ_"

# View just yield-related messages
sudo dmesg | grep "RSEQ_YIELD"

# Count unique PIDs with RSEQ activity
sudo dmesg | grep "RSEQ_SCHED_SWITCH" | grep -oP 'pid=\K[0-9]+' | sort -u | wc -l

# Live monitoring
sudo dmesg -w | grep "RSEQ_"
```

## Key Findings from Debug Session

- **179 unique threads** actively using RSEQ (confirmed per-thread initialization working)
- **sched_switch was being set thousands of times** but prematurely cleared by `ev->events = 0`
- **Yield syscall was being called** but `rseq_syscall_enter_work()` was never invoked until we added the hook
- **Critical bug fixed:** Missing syscall work hook in `kernel/entry/syscall-common.c`

## Related Files

- `/home/bob/buildstuff/BobZKernel/CONTEXT/RSEQ-TRACE-RESULTS.md` - Full investigation results
- `/home/bob/buildstuff/BobZKernel/patches/cachyos-6.19/9002-rseq-slice-extension.patch` - Permanent fix
