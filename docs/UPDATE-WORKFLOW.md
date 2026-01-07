# BobZKernel Update & Build Workflow

## Overview

This document describes the streamlined workflow for updating, patching, building, and installing BobZKernel.

## Quick Start

### Full Automated Workflow

```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh 6.18
```

This single command will:
1. Update kernel source from upstream
2. Clean build directory
3. Apply CachyOS patches
4. Verify patches
5. Build kernel with all optimizations
6. Install kernel and DKMS modules

### Step-by-Step Manual Workflow

If you prefer manual control:

```bash
# 1. Update kernel source
./scripts/update-kernel-source.sh 6.18

# 2. Apply patches
./scripts/apply-patches.sh 6.18

# 3. Verify patches applied correctly
./scripts/verify-patches.sh 6.18

# 4. Build kernel
./scripts/build-kernel.sh

# 5. Install kernel
sudo ./scripts/install-kernel.sh 6.18

# 6. Reboot and select new kernel from GRUB
```

## Script Reference

### `update-kernel-source.sh`
Updates kernel source from upstream stable branch.

```bash
./scripts/update-kernel-source.sh 6.18           # Update to latest 6.18.x
./scripts/update-kernel-source.sh 6.18 6.18.5   # Update to specific version
```

**What it does:**
- Fetches latest stable kernel from kernel.org
- Fast-forward merges or checks out specific tag
- Shows changelog since last update

### `apply-patches.sh`
Applies CachyOS performance patches.

```bash
./scripts/apply-patches.sh 6.18
```

**What it does:**
- Applies all patches from `patches/cachyos-6.18/`
- Uses `git apply` with fallback to 3-way merge
- Reports which patches failed to apply

**Patches applied:**
- BORE scheduler (Burst-Oriented Response Enhancer)
- BBR3 TCP congestion control
- Block layer optimizations
- CachyOS misc optimizations
- Crypto optimizations
- Intel P-State improvements

### `verify-patches.sh`
Verifies patches applied correctly and catches common issues.

```bash
./scripts/verify-patches.sh 6.18
```

**What it checks:**
1. BORE scheduler `nsecs_per_tick` definition exists
2. BORE scheduler `sysctl_sched_min_base_slice` defined
3. No duplicate `unprivileged_userns_clone` definitions
4. Correct preprocessor conditions (CONFIG_SCHED_BORE vs CONFIG_CACHY)
5. Key optimization config options enabled

**Exit codes:**
- `0` - All checks passed, ready to build
- `1` - Issues found, must fix before building

### `build-kernel.sh`
Builds the kernel with Clang/LLVM and all optimizations.

```bash
./scripts/build-kernel.sh [num_jobs]
./scripts/build-kernel.sh 11  # Build with 11 parallel jobs
```

**Optimizations enabled:**
- `march=native` - CPU-specific optimizations
- Full LTO (Link-Time Optimization)
- Clang 20.1.2 compiler
- BORE scheduler
- 1000Hz timer
- ZSTD compression

### `install-kernel.sh`
Installs kernel, modules, and rebuilds DKMS modules.

```bash
sudo ./scripts/install-kernel.sh 6.18
```

**What it does:**
1. Install kernel image to `/boot/`
2. Install modules to `/lib/modules/`
3. Compress modules with ZSTD
4. Patch DKMS sources for compatibility
5. Build DKMS modules (NVIDIA, Legion, xpadneo) with Clang
6. Generate initramfs
7. Build VMware modules (if installed)
8. Update GRUB

### `update-and-build.sh`
All-in-one script combining all steps.

```bash
./scripts/update-and-build.sh 6.18                    # Full workflow
./scripts/update-and-build.sh 6.18 --skip-update     # Skip kernel update
./scripts/update-and-build.sh 6.18 --skip-install    # Build only, don't install
./scripts/update-and-build.sh 6.18 --yes             # Non-interactive mode
```

## Common Issues & Solutions

### Issue 1: Patches Don't Apply

**Symptom:** `apply-patches.sh` reports failed patches

**Cause:** Upstream kernel changes conflict with CachyOS patches

**Solution:**
1. Check if newer patches exist: https://github.com/CachyOS/kernel-patches
2. Download updated patches for your kernel version
3. Place in `patches/cachyos-6.18/`
4. Or manually resolve conflicts with `git apply --reject`

### Issue 2: Verification Fails

**Symptom:** `verify-patches.sh` reports missing definitions

**Cause:** Patches partially applied

**Solutions:**

**Missing `nsecs_per_tick`:**
```c
// Add to kernel/sched/fair.c after #ifdef CONFIG_SCHED_BORE
static const unsigned int nsecs_per_tick = 1000000000ULL / HZ;
```

**Missing `sysctl_sched_min_base_slice`:**
```c
// Add to kernel/sched/fair.c sysctl variables section
unsigned int sysctl_sched_min_base_slice = CONFIG_MIN_BASE_SLICE_NS;
__read_mostly unsigned int sysctl_sched_base_slice = 1000000000ULL / HZ;
```

**Duplicate `unprivileged_userns_clone`:**
```bash
# Remove the definition from kernel/fork.c
# Keep only the one in kernel/user_namespace.c
```

### Issue 3: Build Fails

**Symptom:** Compile errors during `build-kernel.sh`

**Solution:**
1. Check `build.log` for specific error
2. Run `verify-patches.sh` to catch patch issues
3. Make sure config is up-to-date: `make LLVM=1 olddefconfig`

### Issue 4: NVIDIA Module Fails to Load

**Symptom:** `nvidia: disagrees about version of symbol module_layout`

**Cause:** NVIDIA module built with wrong kernel source path

**Solution:**
```bash
# Rebuild NVIDIA module
sudo dkms remove nvidia/580.95.05 -k $(uname -r)
sudo CC=clang dkms install nvidia/580.95.05 -k $(uname -r)
sudo modprobe nvidia
```

## Kernel Configuration

### Location
- Template: `configs/.config-6.18`
- Active: `builds/linux-6.18/.config`

### Key Options

**Performance:**
- `CONFIG_X86_NATIVE_CPU=y` - march=native optimizations
- `CONFIG_LTO_CLANG_FULL=y` - Full Link-Time Optimization
- `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y` - Optimize for speed not size
- `CONFIG_HZ_1000=y` - 1000Hz timer for low latency

**Scheduler:**
- `CONFIG_SCHED_BORE=y` - BORE scheduler
- `CONFIG_PREEMPT_DYNAMIC=y` - Dynamic preemption
- `CONFIG_NO_HZ_FULL=y` - Tickless kernel

**Compression:**
- `CONFIG_KERNEL_ZSTD=y` - ZSTD compression for fast boot

### Updating Config

```bash
cd builds/linux-6.18

# See new options
make LLVM=1 listnewconfig

# Auto-accept defaults for new options
make LLVM=1 olddefconfig

# Interactive configuration
make LLVM=1 menuconfig

# Save back to template
cp .config ../../configs/.config-6.18
```

## Best Practices

### Before Building

1. **Always verify patches:** `./scripts/verify-patches.sh`
2. **Check for config updates:** `make LLVM=1 listnewconfig`
3. **Backup working kernel** in case new build fails

### After Building

1. **Keep old kernel** as fallback in GRUB
2. **Test boot** before deleting old kernels
3. **Verify DKMS modules:** `dkms status`
4. **Check GPU:** `nvidia-smi` (if using NVIDIA)

### Regular Updates

**Weekly:**
```bash
./scripts/update-and-build.sh 6.18 --yes
```

**Before major version bump (6.18 → 6.19):**
1. Download new patches from CachyOS
2. Create new config: `cp .config-6.18 .config-6.19`
3. Test build without installing first

## Troubleshooting

### Clean Build State

If things go wrong, reset to clean state:

```bash
cd /home/bob/buildstuff/BobZKernel/builds/linux-6.18

# Nuclear option: reset all changes
git reset --hard HEAD
git clean -fdx

# Or just clean build artifacts
make mrproper
```

### Check Build Status

```bash
# View build log
less build.log

# Check for errors
grep -i "error:" build.log

# Check warnings
grep -i "warning:" build.log | wc -l
```

### Kernel Won't Boot

1. Reboot and select previous kernel from GRUB "Advanced options"
2. Check dmesg for errors: `dmesg | less`
3. Rebuild with known-good config
4. Disable BORE scheduler if suspected: `CONFIG_SCHED_BORE=n`

## Directory Structure

```
BobZKernel/
├── builds/
│   ├── linux-6.14/          # 6.14 kernel source
│   └── linux-6.18/          # 6.18 kernel source (active)
├── configs/
│   ├── .config-6.14         # 6.14 configuration template
│   └── .config-6.18         # 6.18 configuration template
├── patches/
│   ├── cachyos-6.14/        # 6.14 patches
│   └── cachyos-6.18/        # 6.18 patches
├── scripts/
│   ├── apply-patches.sh     # Apply CachyOS patches
│   ├── verify-patches.sh    # Verify patch application
│   ├── build-kernel.sh      # Build kernel
│   ├── install-kernel.sh    # Install kernel
│   ├── update-kernel-source.sh  # Update from upstream
│   └── update-and-build.sh  # All-in-one workflow
├── docs/
│   └── UPDATE-WORKFLOW.md   # This file
├── build.log                # Build output
└── README.md                # Project overview
```

## FAQ

**Q: How long does a full build take?**
A: 10-30 minutes depending on CPU (with -j11 on i5-13420H: ~15 min)

**Q: Can I build on different hardware?**
A: No - march=native optimizes for the build machine. Build on target hardware.

**Q: What if I want to disable an optimization?**
A: Edit `configs/.config-6.18` and rebuild. Or use `make menuconfig`.

**Q: How do I know if march=native is working?**
A: Check `/boot/config-$(uname -r)` for `CONFIG_X86_NATIVE_CPU=y`

**Q: Can I use GCC instead of Clang?**
A: Not recommended. Kernel and DKMS modules must use same compiler. Scripts assume Clang.

**Q: How to rollback to stock Ubuntu kernel?**
A: Select "Ubuntu" from GRUB menu (not "Advanced options")

## References

- Kernel.org stable: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
- CachyOS patches: https://github.com/CachyOS/kernel-patches
- BORE scheduler: https://github.com/firelzrd/bore-scheduler
- Kernel documentation: https://www.kernel.org/doc/html/latest/
