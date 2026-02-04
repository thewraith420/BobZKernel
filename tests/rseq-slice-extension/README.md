# RSEQ Time Slice Extension Tests

This directory contains tests for the RSEQ Time Slice Extension feature backported to BobZKernel 6.18.8.

## What is RSEQ Time Slice Extension?

RSEQ Time Slice Extension allows userspace programs to request brief delays in preemption (~30µs) to complete critical sections without being scheduled out. This reduces micro-stutters in gaming and other latency-sensitive applications.

## Building the Tests

```bash
make
```

## Running the Tests

```bash
make test
# or
./test_rseq_slice
```

## Test Coverage

The test suite validates:

1. **Sysctl Configuration**: Verifies `/proc/sys/kernel/rseq_slice_extension_nsec` is readable and in range
2. **Basic Grant**: Tests single slice extension request and grant
3. **Multiple Requests**: Tests 1000 consecutive requests to measure grant rate
4. **Stress Test**: Multi-threaded test with 4 threads making 10000 requests each

## Expected Results

- Grant rates depend on system load
- Under low load: 80-100% grant rate expected
- Under high load: Lower grant rates are normal (kernel denies when work is pending)
- All tests should pass if the feature is working correctly

## Troubleshooting

### Test fails with "rseq registration failed"
- Check that kernel has `CONFIG_RSEQ=y` compiled in
- Verify kernel version is 6.18.8-BobZKernel+ or later

### Test fails with "prctl failed"
- Check that kernel has `CONFIG_RSEQ_SLICE_EXTENSION=y` compiled in
- Verify `/proc/sys/kernel/rseq_slice_extension_nsec` exists

### Low or zero grant rates
- This may indicate system is under high load
- Try closing other applications
- Check `dmesg` for kernel messages
- Verify sysctl value: `cat /proc/sys/kernel/rseq_slice_extension_nsec`

## Tuning

Adjust the slice extension duration:

```bash
# Set to 20µs
sudo sysctl kernel.rseq_slice_extension_nsec=20000

# Set to 40µs
sudo sysctl kernel.rseq_slice_extension_nsec=40000
```

Valid range: 10000-50000 ns (10-50 µs)

## Implementation Details

The test uses:
- `syscall(__NR_rseq, ...)` to register with RSEQ subsystem
- `prctl(PR_RSEQ_SLICE_ENABLE, ...)` to enable slice extensions
- Direct access to `struct rseq` fields in thread-local storage
- Memory barriers to ensure proper ordering

## License

GPL-2.0+ (same as kernel)
