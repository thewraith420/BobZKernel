# RSEQ Abort Tracking Implementation Plan

**Request:** Track which syscalls are causing RSEQ grant aborts
**Status:** Feasible - can be implemented in kernel

## Current Situation

**Stats available:**
```
sabort: 6,116  # Total aborts, but no breakdown by syscall
```

**What we need:**
```
sabort: 6,116
sabort_futex: 3,500  (57%)
sabort_read: 1,200   (20%)
sabort_write: 800    (13%)
sabort_poll: 400     (7%)
sabort_other: 216    (3%)
```

## Implementation Approach

### Option 1: Top-N Syscall Tracking (Recommended)

Track the top 10-20 most common syscalls that cause aborts:

**Advantages:**
- Fixed memory usage (small)
- Fast lookup (array indexed by common syscalls)
- Covers 95%+ of real-world cases

**Common syscalls to track:**
- Futex (202) - thread synchronization
- Read (0) - file/socket reads
- Write (1) - file/socket writes
- Poll (7) - I/O polling
- Select (23) - I/O multiplexing
- Epoll_wait (232) - event polling
- Recvfrom (45) - network receive
- Sendto (44) - network send
- Ioctl (16) - device control (GPU!)
- Nanosleep (35) - sleeping

### Option 2: Hash Table (More Complete)

Track all syscalls using a hash table:

**Advantages:**
- Complete coverage
- Dynamic

**Disadvantages:**
- More memory
- More complex
- Slower lookup

### Option 3: BPF/eBPF (External)

Use BPF to track without kernel modification:

**Advantages:**
- No kernel recompilation needed
- Flexible

**Disadvantages:**
- Requires BPF knowledge
- More overhead
- Less integrated

## Recommended Implementation (Option 1)

### 1. Add per-syscall counters to stats structure

**File:** `kernel/rseq.c`

```c
// Add to struct rseq_stats (around line 100)
struct rseq_stats {
    unsigned long exit;
    unsigned long signal;
    unsigned long slowpath;
    unsigned long fastpath;
    unsigned long ids;
    unsigned long cs;
    unsigned long clear;
    unsigned long fixup;
    unsigned long s_granted;
    unsigned long s_expired;
    unsigned long s_revoked;
    unsigned long s_yielded;
    unsigned long s_aborted;

    // NEW: Per-syscall abort tracking
    unsigned long s_abort_futex;
    unsigned long s_abort_read;
    unsigned long s_abort_write;
    unsigned long s_abort_poll;
    unsigned long s_abort_epoll;
    unsigned long s_abort_ioctl;
    unsigned long s_abort_recv;
    unsigned long s_abort_send;
    unsigned long s_abort_select;
    unsigned long s_abort_sleep;
    unsigned long s_abort_other;
};
```

### 2. Track syscall number on abort

**File:** `kernel/rseq.c`, in `rseq_syscall_enter_work()`

```c
void rseq_syscall_enter_work(long syscall)
{
    // ... existing code ...

    if (!curr->rseq.event.sched_switch) {
        if (syscall == __NR_rseq_slice_yield) {
            rseq_stat_inc(rseq_stats.s_yielded);
            curr->rseq.slice.yielded = 1;
        } else {
            // Abort - track which syscall caused it
            rseq_stat_inc(rseq_stats.s_aborted);

            // NEW: Track abort by syscall type
            switch (syscall) {
            case __NR_futex:
                rseq_stat_inc(rseq_stats.s_abort_futex);
                break;
            case __NR_read:
                rseq_stat_inc(rseq_stats.s_abort_read);
                break;
            case __NR_write:
                rseq_stat_inc(rseq_stats.s_abort_write);
                break;
            case __NR_poll:
                rseq_stat_inc(rseq_stats.s_abort_poll);
                break;
            case __NR_epoll_wait:
            case __NR_epoll_pwait:
                rseq_stat_inc(rseq_stats.s_abort_epoll);
                break;
            case __NR_ioctl:
                rseq_stat_inc(rseq_stats.s_abort_ioctl);
                break;
            case __NR_recvfrom:
            case __NR_recvmsg:
                rseq_stat_inc(rseq_stats.s_abort_recv);
                break;
            case __NR_sendto:
            case __NR_sendmsg:
                rseq_stat_inc(rseq_stats.s_abort_send);
                break;
            case __NR_select:
            case __NR_pselect6:
                rseq_stat_inc(rseq_stats.s_abort_select);
                break;
            case __NR_nanosleep:
            case __NR_clock_nanosleep:
                rseq_stat_inc(rseq_stats.s_abort_sleep);
                break;
            default:
                rseq_stat_inc(rseq_stats.s_abort_other);
                break;
            }
        }
    }
}
```

### 3. Add to debugfs output

**File:** `kernel/rseq.c`, in `rseq_stats_show()`

```c
static int rseq_stats_show(struct seq_file *m, void *v)
{
    // ... existing code ...

    seq_printf(m, "sabort: %16lu\n", stats.s_aborted);

    // NEW: Show breakdown
    if (stats.s_aborted > 0) {
        seq_printf(m, "\nAbort breakdown:\n");
        seq_printf(m, "sabort_futex:   %16lu  (%lu%%)\n",
                   stats.s_abort_futex,
                   stats.s_abort_futex * 100 / stats.s_aborted);
        seq_printf(m, "sabort_read:    %16lu  (%lu%%)\n",
                   stats.s_abort_read,
                   stats.s_abort_read * 100 / stats.s_aborted);
        seq_printf(m, "sabort_write:   %16lu  (%lu%%)\n",
                   stats.s_abort_write,
                   stats.s_abort_write * 100 / stats.s_aborted);
        seq_printf(m, "sabort_poll:    %16lu  (%lu%%)\n",
                   stats.s_abort_poll,
                   stats.s_abort_poll * 100 / stats.s_aborted);
        seq_printf(m, "sabort_epoll:   %16lu  (%lu%%)\n",
                   stats.s_abort_epoll,
                   stats.s_abort_epoll * 100 / stats.s_aborted);
        seq_printf(m, "sabort_ioctl:   %16lu  (%lu%%)\n",
                   stats.s_abort_ioctl,
                   stats.s_abort_ioctl * 100 / stats.s_aborted);
        seq_printf(m, "sabort_recv:    %16lu  (%lu%%)\n",
                   stats.s_abort_recv,
                   stats.s_abort_recv * 100 / stats.s_aborted);
        seq_printf(m, "sabort_send:    %16lu  (%lu%%)\n",
                   stats.s_abort_send,
                   stats.s_abort_send * 100 / stats.s_aborted);
        seq_printf(m, "sabort_select:  %16lu  (%lu%%)\n",
                   stats.s_abort_select,
                   stats.s_abort_select * 100 / stats.s_aborted);
        seq_printf(m, "sabort_sleep:   %16lu  (%lu%%)\n",
                   stats.s_abort_sleep,
                   stats.s_abort_sleep * 100 / stats.s_aborted);
        seq_printf(m, "sabort_other:   %16lu  (%lu%%)\n",
                   stats.s_abort_other,
                   stats.s_abort_other * 100 / stats.s_aborted);
    }

    return 0;
}
```

## Expected Output

```bash
$ sudo cat /sys/kernel/debug/rseq/stats
exit:         488488709
signal:         12599809
slowp:              3744
fastp:           5626030
ids:             5400181
cs:                    0
clear:                 0
fixup:                 0
sgrant:            13089
sexpir:             4790
srevok:             6740
syield:              233
sabort:             6116

Abort breakdown:
sabort_futex:          3500  (57%)
sabort_ioctl:          1200  (20%)
sabort_read:            800  (13%)
sabort_write:           400  (7%)
sabort_poll:            150  (2%)
sabort_epoll:            40  (1%)
sabort_recv:             15  (0%)
sabort_send:              5  (0%)
sabort_select:            3  (0%)
sabort_sleep:             2  (0%)
sabort_other:             1  (0%)
```

## Value for ProtonGE Optimization

If we see:
- **57% futex aborts** → Focus on Wine futex/lock operations
- **20% ioctl aborts** → GPU driver interaction needs work
- **13% read/write** → File I/O during critical sections

This data tells us **exactly where to add yields in ProtonGE!**

## Implementation Effort

**Complexity:** Low-Medium
**Files to modify:** 1 (kernel/rseq.c)
**Lines of code:** ~100 lines
**Testing:** Simple - just check stats output

## Alternative: Quick Debug Version

For immediate testing, we could add a simple printk:

```c
} else {
    rseq_stat_inc(rseq_stats.s_aborted);

    // TEMPORARY DEBUG
    if (syscall == __NR_futex)
        printk_ratelimited(KERN_INFO "RSEQ abort: futex\n");
    else if (syscall == __NR_ioctl)
        printk_ratelimited(KERN_INFO "RSEQ abort: ioctl\n");
    // etc...
}
```

Then `dmesg | grep "RSEQ abort" | sort | uniq -c` to see counts.

## Next Steps

1. **Decide on implementation approach**
2. **Modify kernel/rseq.c**
3. **Rebuild kernel**
4. **Test with ESO**
5. **Analyze abort breakdown**
6. **Use data to optimize ProtonGE yield placement**

## References

- Current RSEQ implementation: `kernel/rseq.c`
- Syscall numbers: `arch/x86/entry/syscalls/syscall_64.tbl`
- Stats location: `/sys/kernel/debug/rseq/stats`
