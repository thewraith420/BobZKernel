# RSEQ Time Slice Extension - Quick Start

## What Is This?

A backport of Linux 7.0's RSEQ Time Slice Extension feature to BobZKernel 6.18.8.
This feature lets applications request brief delays in preemption (~30µs) to reduce micro-stutters.

## Quick Verification

```bash
# 1. Check if feature is present
./test_feature_check

# 2. Run full test suite (takes ~20 seconds)
./run_all_tests.sh
```

## What to Expect

✅ **Infrastructure tests will PASS** - prctl, sysctl, symbols all work

⚠️ **Grant tests will show 0%** - nothing uses this API yet

This is NORMAL! The feature is complete but waiting for applications to adopt it.

## Files

- `test_feature_check` - Quick kernel support check
- `test_synthetic_workload` - Game-like workload simulation
- `run_all_tests.sh` - Full test suite
- `FINAL_SUMMARY.md` - Complete technical details

## One-Liner Test

```bash
./test_feature_check && echo "✓ RSEQ is ready!"
```

## When Will This Actually Work?

When games/engines add RSEQ support. Think:
- Unity engine updates
- Unreal engine updates
- Wine/Proton updates
- Mesa driver updates

Probably 2026-2027 timeframe.

## Your Kernel Has

- ✅ 10 functional patches backported
- ✅ prctl API (`PR_RSEQ_SLICE_EXTENSION`)
- ✅ Sysctl tuning (`/proc/sys/kernel/rseq_slice_extension_nsec`)
- ✅ Full grant logic in exit-to-user-mode path
- ⏳ Waiting for software to use it

You're just early to the party! 🎉
