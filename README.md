# BobZKernel - Optimized Linux 6.18.9

Custom optimized Linux kernel 6.18.9 with RSEQ slice extension, BORE scheduler, and performance optimizations for Lenovo LOQ 15IRH8.

## Features

### RSEQ Slice Extension (Primary Feature)
- **Syscall 470** (`rseq_slice_yield`) - New syscall for timeslice management
- **prctl Interface** - Per-process control of slice extension
- **Runtime Tunable** - `/proc/sys/kernel/rseq_slice_extension_nsec` (default: 30000 ns)
- **CONFIG_RSEQ_SLICE_EXTENSION=y** - Enabled by default

### Performance Optimizations
- **BORE Scheduler** - Burst-Oriented Response Enhancer for desktop responsiveness
- **CachyOS Patches** - Additional performance optimizations (CONFIG_CACHY=y)
- **Full LTO** - Link-Time Optimization using LLVM/Clang-19
- **1000Hz Timer** - Better latency for interactive workloads (CONFIG_HZ=1000)
- **Dynamic Preemption** - CONFIG_PREEMPT_DYNAMIC=y

### CPU Optimizations
- **march=native** - CPU-specific optimizations for Intel i5-13420H (13th Gen Raptor Lake)
- **CONFIG_X86_NATIVE_CPU=y** - Native CPU instruction set

### Memory & Storage
- **ZRAM** - Compressed RAM swap (CONFIG_ZRAM=y, zstd compression)
- **ZSWAP** - Compressed swap cache (CONFIG_ZSWAP=y, zstd compression, enabled by default)
- **BBRv3 TCP Congestion Control** - CONFIG_TCP_CONG_BBR=y, set as default

### Power Management
- **CONFIG_CPU_FREQ=y** - Dynamic frequency scaling
- **CONFIG_PM=y** - Power management support
- **CONFIG_ACPI_MADT_WAKEUP=y** - ACPI wake optimization

### DKMS Modules (Auto-Rebuilt)
- **xpadneo** - Advanced Xbox controller driver with rumble, battery reporting, and low-latency support
- **NVIDIA drivers** - Automatically rebuilt with each kernel update

## Target Hardware

- **Device**: Lenovo LOQ 15IRH8
- **CPU**: Intel i5-13420H (13th Gen, 8 cores/12 threads)
- **GPU**: NVIDIA GeForce RTX 3050 6GB
- **RAM**: 8GB
- **OS**: Debian GNU/Linux 13 (trixie)

## Installation

### Build from Source

```bash
./scripts/update-and-build.sh --yes
```

For incremental builds (skip upstream update):
```bash
./scripts/update-and-build.sh --resume --yes
```

### Install After Build

```bash
# Use the portable installer
cd installer-6.18.9-BobZKernel*/
sudo ./install.sh
```

## Verification

After installation and reboot:

```bash
# Check kernel version
uname -r
# Expected: 6.18.9-BobZKernel+

# Verify RSEQ slice extension sysctl
cat /proc/sys/kernel/rseq_slice_extension_nsec
# Expected: 30000

# Verify BORE scheduler
grep -i bore /proc/sched_debug 2>/dev/null || dmesg | grep -i bore

# Check LTO was used
grep CONFIG_LTO_CLANG_FULL /boot/config-$(uname -r)
```

### Run RSEQ Tests

```bash
cd tests/rseq-slice-extension
./run_all_tests.sh
```

## Applied Patches

Three custom patches are applied in order:

1. **9001-revocable-resource-management.patch** - Revocable resource management infrastructure
2. **9002-rseq-timeslice-extension.patch** - RSEQ slice extension feature (21 files, 937 lines)
3. **9003-rseq-timeslice-debian-fixes.patch** - Debian glibc 2.41 compatibility

## Build System

### Automated Build Fixes

The build system includes `fix-build-conflicts.sh` with 12 automated fixes:

1. Remove init/Kconfig merge conflict markers
2. Remove thread_info.h merge conflict markers
3. Remove kernel/rseq.c merge conflict markers
4. Remove duplicate migration_cost definition from fair.c
5. Fix vruntime field names (min_vruntime → zero_vruntime)
6. Remove bore.c merge conflict markers
7. Remove duplicate static from revocable.c
8. Update hrtimer API (hrtimer_init → hrtimer_setup)
9. Update sysctl API (register_sysctl → register_sysctl_init)
10. Repair broken comment block in fair.c
11. Add missing #endif for CONFIG_RSEQ_SLICE_EXTENSION
12. Remove empty `{}` terminator from sysctl array

### Build Requirements

- **Compiler**: Clang/LLVM-19
- **Build Tool**: ccache (optional, for faster rebuilds)
- **OS**: Debian 13 (trixie) or compatible

## Directory Structure

```
BobZKernel/
├── builds/
│   └── linux-6.18/                    # Kernel source with patches
├── scripts/
│   ├── update-and-build.sh            # Complete automated workflow
│   ├── build-kernel.sh                # Build kernel only
│   ├── fix-build-conflicts.sh         # Automated build fixes
│   └── ...
├── patches/
│   └── cachyos-6.18/                  # CachyOS + RSEQ patches (9001-9003)
├── configs/                           # Saved kernel configs
├── tests/
│   └── rseq-slice-extension/          # RSEQ feature tests
└── CONTEXT/                           # Project documentation
    ├── PROJECT-OVERVIEW.md
    ├── BUILD-STATUS.md
    ├── BUILD-TROUBLESHOOTING.md
    ├── QUICK-START.md
    ├── GIT-COMMITS.md
    └── SYSCTL-FIX-SESSION.md
```

## Troubleshooting

See `CONTEXT/BUILD-TROUBLESHOOTING.md` for detailed error solutions.

### Common Issues

**Build fails with scheduler errors:**
```bash
# Fix is automated, but if needed manually:
sed -i 's/cfs_rq->min_vruntime/cfs_rq->zero_vruntime/g' builds/linux-6.18/kernel/sched/fair.c
```

**Stale ccache objects:**
```bash
rm -rf ~/.cache/ccache/*
./scripts/update-and-build.sh --resume --yes
```

**RSEQ sysctl not appearing:**
- Ensure CONFIG_RSEQ_SLICE_EXTENSION=y in .config
- Check dmesg for sysctl registration errors
- See CONTEXT/SYSCTL-FIX-SESSION.md for details

## Credits

- **Linux Kernel** - Linus Torvalds and contributors
- **Thomas Gleixner** - RSEQ time slice extension mechanism
- **Tzung-Bi Shih (Google)** - Revocable resource management (Copyright 2025 Google LLC)
- **CachyOS Team** - BORE scheduler and performance patches
- **LLVM Project** - Clang/LLVM compiler infrastructure
- **atar-axis** - [xpadneo](https://github.com/atar-axis/xpadneo) - Advanced Xbox controller driver

## License

Linux kernel is licensed under GPLv2. CachyOS patches maintain their respective licenses.
