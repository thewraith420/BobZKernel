# BobZKernel 6.18.3 Release Notes

## Overview

BobZKernel 6.18.3 is a high-performance Linux kernel with desktop-oriented optimizations, available in two variants for maximum compatibility and performance.

## Download

### For Intel 12th/13th Gen Users (Recommended)
**BobZKernel-6.18.3-march-native-installer.sh** (~120MB)
- Optimized specifically for Intel Alder Lake (12th Gen) and Raptor Lake (13th Gen)
- Maximum performance through CPU-specific optimizations
- Use if you have: Intel Core i5/i7/i9 12th or 13th Gen

### For All Other Users
**BobZKernel-6.18.3-generic-installer.sh** (~119MB)
- Compatible with all modern x86-64 CPUs (2015+)
- Works on Intel, AMD, and other x86-64 processors
- Maintains all performance optimizations except march=native

## Installation

```bash
# Download the appropriate installer for your CPU
wget https://github.com/thewraith420/BobZKernel/releases/download/v6.18.3/BobZKernel-6.18.3-<variant>-installer.sh

# Make executable
chmod +x BobZKernel-6.18.3-<variant>-installer.sh

# Run installer (requires root)
sudo ./BobZKernel-6.18.3-<variant>-installer.sh
```

The installer features:
- Interactive GUI (dialog/whiptail/zenity) or text fallback
- Automatic bootloader update (GRUB)
- Preserves your existing kernel for safe rollback
- Automatic initramfs generation

## What's New in 6.18.3

### Performance Features
- **BORE Scheduler** - Burst-Oriented Response Enhancer for improved desktop responsiveness
- **BBRv3** - Google's latest TCP congestion control algorithm
- **Full LTO** - Link-Time Optimization using LLVM/Clang 20.1.2
- **1000Hz Timer** - Reduced latency for interactive workloads
- **CachyOS Patches** - Performance and crypto optimizations

### Build System Improvements
- **DKMS Auto-Rebuild** - Automatically rebuilds all DKMS modules (NVIDIA, Legion, etc.) with Clang
- **Symbol Version Fix** - Prevents module_layout symbol mismatches
- **Dual Architecture** - Clean separation between march=native and generic builds

### Compiler
- Built with **Clang 20.1.2** and **LLVM toolchain**
- Full LTO enabled for whole-program optimization
- Position-independent code for security

## Technical Details

### Kernel Configuration
- Based on Linux 6.18.3 stable
- CONFIG_SCHED_BORE=y
- CONFIG_LTO_CLANG_FULL=y
- CONFIG_HZ_1000=y
- CONFIG_TCP_CONG_BBR=y (v3)

### march=native Build
- CONFIG_X86_NATIVE_CPU=y
- Optimized for Intel Raptor Lake microarchitecture
- CPU-specific instruction optimizations

### Generic Build
- CONFIG_GENERIC_CPU=y
- x86-64-v3 baseline (AVX, AVX2, BMI1, BMI2, F16C, FMA, LZCNT, MOVBE, XSAVE)
- Compatible with CPUs from ~2015 onwards

## Tested Hardware

- **CPU:** Intel Core i5-13420H (Raptor Lake)
- **GPU:** NVIDIA GPU with driver 580.95.05
- **Laptop:** Lenovo Legion LOQ 15IRH8
- **DKMS Modules:** NVIDIA, LenovoLegionLinux, hid-xpadneo

## Verification

After installation and reboot:

```bash
# Check kernel version
uname -r
# Should show: 6.18.3-BobZKernel or 6.18.3-BobZKernel-generic

# Verify compiler
cat /proc/version
# Should show: clang version 20.1.2

# Check BORE scheduler
cat /sys/kernel/sched_features | grep -i bore

# Verify 1000Hz timer
grep CONFIG_HZ= /boot/config-$(uname -r)
# Should show: CONFIG_HZ_1000=y

# Check LTO
grep CONFIG_LTO_CLANG_FULL /boot/config-$(uname -r)
# Should show: CONFIG_LTO_CLANG_FULL=y
```

## Troubleshooting

### Boot Issues
- At GRUB menu, select your previous kernel if BobZKernel doesn't boot
- Your old kernel is always preserved

### DKMS Module Issues
DKMS modules are automatically rebuilt during installation. If you encounter issues:

```bash
sudo dkms status  # Check module status
# Manually rebuild if needed
sudo dkms remove <module>/<version> -k $(uname -r)
sudo CC=clang dkms install <module>/<version> -k $(uname -r)
```

### Wrong CPU Architecture
If you installed the wrong variant:
- Boot your old kernel
- Download and install the correct variant
- Reboot to BobZKernel

## Building from Source

See [BRANCH-WORKFLOW.md](https://github.com/thewraith420/BobZKernel/blob/master/BRANCH-WORKFLOW.md) for details.

```bash
# Clone repository
git clone https://github.com/thewraith420/BobZKernel.git
cd BobZKernel

# For march=native build
git checkout master
cp configs/config-6.18.3-march-native builds/linux-6.18/.config
./scripts/build-kernel.sh

# For generic build
git checkout generic-build
cp configs/config-6.18.3-generic builds/linux-6.18/.config
./scripts/build-kernel.sh
```

## Support

- **Issues:** https://github.com/thewraith420/BobZKernel/issues
- **Discussions:** https://github.com/thewraith420/BobZKernel/discussions
- **Documentation:** https://github.com/thewraith420/BobZKernel

## License

Linux kernel is licensed under GPLv2. CachyOS patches maintain their respective licenses.

## Credits

- **Linux Kernel** - Linus Torvalds and contributors
- **CachyOS Team** - Performance patches (BORE, BBRv3, etc.)
- **LLVM Project** - Clang/LLVM compiler infrastructure

---

**Changelog:**
- First official release of BobZKernel 6.18.3
- Dual-architecture support (march=native + generic)
- DKMS auto-rebuild system
- Complete installer with GUI support
