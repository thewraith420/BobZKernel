# BobZKernel 6.19 Project

## Current Status

**Kernel Version:** Linux 6.19.3-BobZKernel+
**Branch:** linux-6.19
**Last Updated:** February 22, 2026

## Project Goals

1. **System Optimization:** Optimize Lenovo LOQ 15IRH8 laptop for:
   - Battery life in battery mode
   - Performance and smoothness on AC power
   - Gaming performance (ESO, Steam games via Proton)

2. **Custom Kernel Features:**
   - **BORE Scheduler** - Burst-Oriented Response Enhancer for desktop responsiveness
   - **CachyOS Patches** - Performance optimizations and fixes
   - **RSEQ Slice Extension** - Reduce context switching overhead for gaming ✅ **WORKING**
   - **Cluster-aware scheduling** - NUMA and cache-aware task placement

3. **Hardware Support:**
   - NVIDIA RTX 4060 Mobile (proprietary driver, DKMS)
   - Xbox controller support (hid-xpadneo driver)
   - Lenovo Legion platform drivers (fan control, performance modes)

## Hardware Target

**System:** Lenovo LOQ 15IRH8
**CPU:** Intel 13th Gen (Raptor Lake)
**GPU:** NVIDIA GeForce RTX 4060 Mobile (8GB)
**RAM:** 16GB DDR5
**Display:** 144Hz panel

## Key Kernel Features

### RSEQ Slice Extension (✅ Production Ready)

**Status:** Fully functional and tested
**Performance:** 91% yield rate, 36% revocation rate in gaming workloads
**Integration:** ProtonGE-RSEQ fork for Wine/gaming support

**What it does:**
- Allows userspace threads to request brief protection from preemption (~30µs)
- Reduces context switch overhead during critical sections
- Improves gaming performance by reducing microstuttering

**Syscalls:**
- `prctl(PR_RSEQ_SLICE_EXTENSION_SET, ...)` - Enable per-thread
- `syscall(__NR_rseq_slice_yield, 471)` - Request grant/yield
- Sysctl: `/proc/sys/kernel/rseq_slice_extension_nsec` (default: 30000ns)
- Stats: `/sys/kernel/debug/rseq/stats`

**Key Fix:** Added missing syscall work hook in `kernel/entry/syscall-common.c`
**Patch:** `patches/cachyos-6.19/9002-rseq-slice-extension.patch`

### BORE Scheduler

Burst-Oriented Response Enhancer - improves desktop interactivity and responsiveness under load.

### CachyOS Patches

Collection of performance patches and optimizations from CachyOS project.

## Build Configuration

**Compiler:** LLVM/Clang 19 (NOT GCC)
**Build System:** Custom scripts in `scripts/`
**Config Location:** `configs/.config-6.19.*`

**Key Config Options:**
- `CONFIG_PREEMPT_DYNAMIC=y` - Runtime preemption model selection
- `CONFIG_RSEQ=y` - Restartable sequences support
- `CONFIG_SCHED_BORE=y` - BORE scheduler
- LLVM build flags for optimization

## Directory Structure

```
BobZKernel/
├── builds/
│   ├── linux-6.18/          # Old 6.18 kernel (archived)
│   └── linux-6.19/          # Current 6.19 kernel source
├── configs/
│   └── .config-6.19.*       # Kernel configurations
├── patches/
│   ├── cachyos-6.19/        # CachyOS patches including RSEQ
│   └── rseq-timeslice-v6-upstream/  # Upstream RSEQ patches
├── scripts/
│   ├── update-and-build.sh  # Main build workflow
│   ├── build-kernel.sh      # Kernel compilation
│   ├── install-kernel.sh    # Installation
│   └── apply-patches.sh     # Patch application
└── CONTEXT/
    └── *.md                 # Documentation (this file)
```

## Build Workflow

**Standard build:**
```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh
```

**Resume after manual changes (preserves modifications):**
```bash
./scripts/update-and-build.sh --resume
```

**Skip installation (build only):**
```bash
./scripts/update-and-build.sh --skip-install
```

## DKMS Modules

**NVIDIA (Open Kernel Module):**
- Version: 590.48.01
- Auto-rebuilds on kernel install
- Manual rebuild: `sudo dkms install nvidia/590.48.01 -k $(uname -r)`

**hid-xpadneo (Xbox Controller):**
- Version: v0.10-pre-259-gfc1b13a
- Provides Xbox controller support
- Rebuild: `sudo dkms install hid-xpadneo/v0.10-pre-259-gfc1b13a -k $(uname -r)`

**LenovoLegionLinux:**
- Version: 0.0.20
- Platform driver for Lenovo-specific features
- Rebuild: `sudo dkms install LenovoLegionLinux/0.0.20 -k $(uname -r)`
- Note: May fail with LLVM builds (needs GCC compatibility)

## Integration Projects

### ProtonGE-RSEQ

**Location:** `/home/bob/buildstuff/proton-ge-rseq/`
**Status:** Working - 91% yield rate achieved
**Purpose:** Wine/Proton fork with RSEQ slice extension support for gaming

**Key implementations:**
- Per-thread RSEQ initialization
- Proactive grant requests before lock acquisitions
- Cooperative yielding after critical sections
- Fixed syscall number (471, not 470)

### PipeWire-RSEQ (Planned)

**Location:** `/home/bob/buildstuff/pipewire-rseq/`
**Status:** Planning phase
**Purpose:** System-wide audio improvements via RSEQ
**Expected Impact:** Reduced xruns, lower latency, smoother audio during CPU load

## Git Workflow

**Branches:**
- `linux-6.19` - Current production branch (6.19.3)
- `linux-6.18` - Previous stable (archived)
- `generic-build` - Minimal generic build configuration

**Remotes:**
- `origin` - Local repository
- `upstream` - Linux stable kernel

**Commit Pattern:**
```bash
# After successful builds with new features
git add -A
git commit -m "Update to Linux 6.19.3 with RSEQ slice extension working"
git push origin linux-6.19
```

## Known Issues & Solutions

### Issue: Kernel built with GCC instead of LLVM

**Symptom:** `/proc/version` shows GCC compiler
**Cause:** Manual build commands without `LLVM=` flags
**Solution:** Always use `update-and-build.sh` script or include `LLVM=19` in make commands

### Issue: DKMS modules fail to build

**Symptom:** Module build errors with LLVM
**Cause:** Some DKMS modules (LenovoLegionLinux) use LLVM=1 flag but kernel was built with GCC
**Solution:** Rebuild kernel with proper LLVM flags, then rebuild DKMS modules

### Issue: Debug printk messages not appearing

**Symptom:** Added printk() but no output in dmesg
**Cause:** trace_printk() used but CONFIG_FTRACE not fully configured
**Solution:** Use regular `printk(KERN_INFO "message")` instead of trace_printk()

## Performance Tuning

### RSEQ Slice Duration

**Default:** 30,000ns (30µs) - **Optimal for gaming**
**Range:** 10,000ns - 100,000ns
**Adjust:** `echo 30000 | sudo tee /proc/sys/kernel/rseq_slice_extension_nsec`

**Testing showed:**
- 20µs: Too short (54% revocation rate)
- 30µs: **Optimal** (36% revocation rate) ✅
- 50µs: Too long (50% revocation rate, reduced yields)

### Scheduler Tuning

Check available tunables:
```bash
ls /proc/sys/kernel/sched_*
```

## Success Metrics

**RSEQ Performance (Gaming):**
- ✅ 25,832 grants during ESO gameplay
- ✅ 91% yield rate (1,342 yields)
- ✅ 36% revocation rate (9,389 revokes)
- ✅ 179 unique threads actively using RSEQ
- ✅ System-wide engagement via ProtonGE

**Build Quality:**
- ✅ Clean LLVM 19 compilation
- ✅ All patches apply successfully
- ✅ No compilation errors or warnings
- ✅ DKMS modules rebuild successfully

## References

**Documentation:**
- `CONTEXT/DEBUG-PRINTK-LOCATIONS.md` - Debug instrumentation reference
- `CONTEXT/RSEQ-TRACE-RESULTS.md` - RSEQ investigation final results
- `CONTEXT/BUILD-TROUBLESHOOTING.md` - Common build issues

**External:**
- Linux kernel: https://kernel.org
- CachyOS patches: https://github.com/CachyOS/linux-cachyos
- RSEQ upstream: Linux kernel `Documentation/rseq.txt`

## Quick Commands

```bash
# Check kernel version
uname -r

# View RSEQ stats
sudo cat /sys/kernel/debug/rseq/stats

# Check RSEQ slice duration
cat /proc/sys/kernel/rseq_slice_extension_nsec

# Rebuild NVIDIA driver
sudo dkms install nvidia/590.48.01 -k $(uname -r)

# Check loaded modules
lsmod | grep -E "nvidia|xpad|legion"

# Monitor build
tail -f scripts/build.log
```

## Next Steps

- [ ] Monitor RSEQ performance long-term
- [ ] Test with different game workloads
- [ ] Implement PipeWire-RSEQ integration
- [ ] Consider contributing RSEQ improvements upstream
- [ ] Track kernel 6.20+ updates for new features
