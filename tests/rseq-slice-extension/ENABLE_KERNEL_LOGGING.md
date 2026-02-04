# How to Verify Grants with Kernel Logging

## The Only Definitive Test

Since userspace can't reliably detect grants, the ONLY way to confirm they're happening is to add kernel logging.

## Add This to the Kernel

Edit `/home/bob/buildstuff/BobZKernel/builds/linux-6.18/include/linux/rseq_entry.h`

Find the grant function around line 66-70:

```c
/* Grant the slice extension */
usr_ctrl.request = 0;
usr_ctrl.granted = 1;
if (put_user(usr_ctrl.all, &rseq->slice_ctrl.all))
    goto efault;
```

Add a printk AFTER the put_user:

```c
/* Grant the slice extension */
usr_ctrl.request = 0;
usr_ctrl.granted = 1;
if (put_user(usr_ctrl.all, &rseq->slice_ctrl.all))
    goto efault;

printk_ratelimited(KERN_INFO "RSEQ: Granted slice extension to PID %d\n", current->pid);
```

## Rebuild and Test

```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh  # Rebuild with logging

# After reboot
dmesg -w &  # Watch kernel log in background

# Run test
cd tests/rseq-slice-extension
./test_quick_grant

# Check dmesg
dmesg | grep "RSEQ: Granted"
```

## What You'll See

If grants are happening:
```
[12345.678] RSEQ: Granted slice extension to PID 12345
[12345.679] RSEQ: Granted slice extension to PID 12346
...
```

If no grants:
```
(nothing)
```

## Why This Works

The printk happens IN THE KERNEL when the grant occurs, before userspace even knows about it. This bypasses the observation problem.

## Alternative: Use ftrace

Without recompiling:

```bash
# Enable function tracing
echo 1 > /sys/kernel/debug/tracing/events/enable
echo 'rseq_grant_slice_extension' > /sys/kernel/debug/tracing/set_ftrace_filter
echo function > /sys/kernel/debug/tracing/current_tracer

# Run test
./test_quick_grant

# Check trace
cat /sys/kernel/debug/tracing/trace
```

Note: `rseq_grant_slice_extension` is inline so it won't show in ftrace. You'd need to trace the exit_to_user_mode_loop instead.

## The Nuclear Option

Add printk to BOTH the grant and the deny paths to see what's happening:

```c
if (likely(!usr_ctrl.request)) {
    printk_ratelimited(KERN_DEBUG "RSEQ: No request (PID %d)\n", current->pid);
    return false;
}

if (unlikely(work_pending || curr->rseq_slice.state.granted)) {
    printk_ratelimited(KERN_DEBUG "RSEQ: Denied - work_pending=%d granted=%d (PID %d)\n",
                       !!work_pending, curr->rseq_slice.state.granted, current->pid);
    // ... clear logic
}

// At grant
printk(KERN_INFO "RSEQ: GRANTED to PID %d!\n", current->pid);
```

This will show you EXACTLY what's happening.

## Expected Results

My prediction: You'll see grants happening, proving the feature works!

The reason we don't detect them in userspace is the observation paradox explained in WHY_NO_GRANTS.md.
