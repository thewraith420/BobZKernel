# BobZKernel 6.18.8+ Project Context

## Project Goals
1. **System Optimization**: Optimize Lenovo LOQ 15IRH8 for battery life (battery mode) and smoothness (AC mode)
2. **Custom Kernel Development**: Build BobZKernel with BORE scheduler, CachyOS patches, and RSEQ slice extension
3. **RSEQ Slice Extension**: Primary development focus - enabling `CONFIG_RSEQ_SLICE_EXTENSION=y` for timeslice extension feature

## Hardware Target
- **Device**: Lenovo LOQ 15IRH8
- **CPU**: Intel i5-13420H (13th Gen, 8 cores/12 threads)
- **GPU**: NVIDIA GeForce RTX 3050 6GB
- **RAM**: 16GB
- **OS**: Debian GNU/Linux 13 (trixie)

## Current Kernel Version
- **Base**: Linux 6.18.8
- **Branch**: rseq-timeslice
- **Build Tag**: 6.18.8-BobZKernel+

## Key Configuration
```
CONFIG_RSEQ=y
CONFIG_RSEQ_SLICE_EXTENSION=y              # PRIMARY FEATURE
CONFIG_SCHED_BORE=y                        # BORE scheduler
CONFIG_LTO_CLANG_FULL=y                    # Full LTO optimization
CONFIG_X86_NATIVE_CPU=y                    # march=native CPU optimizations
CONFIG_CPU_FREQ=y                          # Dynamic frequency scaling
CONFIG_PM=y                                # Power management
CONFIG_ACPI_MADT_WAKEUP=y                  # ACPI wake optimization
```

## Applied Patches (In Order)
1. **0001-revocable-resource-management.patch** - Revocable resource management support
2. **0002-rseq-timeslice-extension.patch** - RSEQ slice extension feature (937 lines, 21 files)
3. **0003-rseq-timeslice-debian-fixes.patch** - Debian glibc 2.41 compatibility fixes
4. **0004-fix-scheduler-vruntime-field-names.patch** - Scheduler field name fixes (min_vruntime → zero_vruntime)

## Critical Fixes Applied
### 1. Scheduler vruntime Field Names (Patch 0004)
**Problem**: Kernel code references `min_vruntime` and `min_vruntime_fi` but struct defines `zero_vruntime` and `zero_vruntime_fi`

**Solution**: Fixed 3 locations in kernel/sched/fair.c:
- Line 13138: `cfs_rq->zero_vruntime_fi = cfs_rq->zero_vruntime;`
- Line 13195: `(s64)(cfs_rqb->zero_vruntime_fi - cfs_rqa->zero_vruntime_fi);`
- Line 13434: `cfs_rq->zero_vruntime = (u64)(-(1LL << 20));`

### 2. BORE Sysctl Terminator (In Source)
**Problem**: Missing null terminator in sched_bore_sysctls[] array → "sysctl table check failed" error

**Solution**: Added `{}` terminator at line 378 of kernel/sched/bore.c

### 3. RSEQ Stub Syscall (In Source)
**Problem**: sys_rseq_slice_yield syscall in table unconditionally, but not compiled when CONFIG_RSEQ_SLICE_EXTENSION=n

**Solution**: Added stub implementation in kernel/rseq.c (lines 844-852):
```c
SYSCALL_DEFINE0(rseq_slice_yield)
{
    return 0;
}
```

## Build Process
```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh --resume --yes
```

### Build Script Steps
1. Update kernel source from upstream
2. Apply 4 patches in order
3. Copy kernel config (auto-detects branch for native/generic/pixel-slate)
4. Build with LLVM-19 clang, ccache enabled
5. Create portable installer package

## Build History
- **Previous Issues**: 
  - Scheduler vruntime field mismatches (solved by patch 0004)
  - BORE sysctl array without terminator (in source)
  - Undefined rseq_slice_yield symbol (stub added)
  
- **Gemini Attempt**: AI assistant attempted broad patches that conflicted with custom fixes - REVERTED
- **Current Status**: All fixes isolated, tested, and committed to git

## ccache Management
- **Location**: `~/.cache/ccache/`
- **Clear with**: `rm -rf ~/.cache/ccache/*`
- **Usage**: Automatically used in build (ccache clang-19)
- **Note**: Clear before fresh builds to avoid stale object files

## System Optimizations Applied
```bash
# Power Management (TLP)
/etc/tlp.conf - USB autosuspend, battery thresholds (20-85%), NMI watchdog disabled

# Driver Blacklists
/etc/modprobe.d/blacklist-spd5118.conf - Ghost fingerprint sensor
/etc/modprobe.d/blacklist-pcspkr.conf - PC speaker

# ALSA Fixes
/etc/udev/rules.d/90-alsa-restore.rules - Fixed duplicate label

# Chrome Hardware Acceleration
~/.config/google-chrome/chrome-flags.conf - Workaround for PDF printing
```

## Next Steps
1. Complete build (currently in progress)
2. Verify no compilation errors
3. Install kernel: `sudo ./install.sh` from installer directory
4. Reboot to apply
5. Test RSEQ slice extension sysctl availability: `/proc/sys/kernel/rseq_slice_extension_nsec`
