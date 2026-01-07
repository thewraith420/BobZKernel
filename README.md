# BobZKernel - Optimized Linux 6.18.3

Custom optimized Linux kernel 6.18.3 with performance patches and multi-architecture support.

## Features

### Performance Optimizations
- **BORE Scheduler** - Burst-Oriented Response Enhancer for desktop responsiveness
- **BBRv3** - TCP congestion control for improved network performance
- **Full LTO** - Link-Time Optimization using LLVM/Clang 20.1.2
- **1000Hz Timer** - Better latency for interactive workloads
- **CachyOS Patches** - Additional performance and crypto optimizations

### Architecture Support
- **march=native** - CPU-specific optimizations for Intel Raptor Lake (13th Gen)
- **Generic x86-64-v3** - Universal build compatible with all modern CPUs
- **Two separate installers** - Choose the right build for your CPU

## Installation

### For End Users (Prebuilt Installer)

**Choose the installer for your CPU:**

#### Intel 12th/13th Gen (Recommended for Alder Lake/Raptor Lake)
```bash
# Download march=native installer
wget https://github.com/thewraith420/BobZKernel/releases/latest/download/BobZKernel-6.18.3-march-native-installer.sh

# Make executable and run
chmod +x BobZKernel-6.18.3-march-native-installer.sh
sudo ./BobZKernel-6.18.3-march-native-installer.sh
```

#### All Other CPUs (AMD, Intel 11th Gen and older)
```bash
# Download generic installer
wget https://github.com/thewraith420/BobZKernel/releases/latest/download/BobZKernel-6.18.3-generic-installer.sh

# Make executable and run
chmod +x BobZKernel-6.18.3-generic-installer.sh
sudo ./BobZKernel-6.18.3-generic-installer.sh
```

Both installers will:
- Install kernel, modules, and update bootloader
- Automatically rebuild DKMS modules with Clang
- Preserve your existing kernel for safe fallback

### For Developers (Build from Source)

#### Automated Build Workflow

```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh --yes
```

This complete workflow:
1. Updates kernel source from upstream
2. Applies CachyOS performance patches
3. Verifies patches applied correctly
4. Builds kernel with all optimizations
5. Installs kernel and rebuilds DKMS modules with Clang

#### Manual Build Steps

```bash
# Update kernel source
./scripts/update-kernel-source.sh 6.18

# Build kernel
./scripts/build-kernel.sh

# Install kernel
sudo ./scripts/install-kernel.sh
```

#### Create Distribution Installer

```bash
# Build both architectures, then:
./scripts/create-multi-arch-installer.sh
```

## System Requirements

- **Kernel:** Linux 6.18.3
- **Compiler:** Clang 20.1.2 with LLVM
- **Target CPUs:**
  - Intel 12th/13th Gen (Alder Lake/Raptor Lake) - march=native build
  - Any modern x86-64-v3 CPU - generic build
- **DKMS Modules:** Automatically rebuilt with Clang
  - NVIDIA 580.95.05
  - LenovoLegionLinux 1.0.0
  - hid-xpadneo v0.9

## Directory Structure

```
BobZKernel/
├── builds/
│   └── linux-6.18/                    # Kernel source with patches
├── scripts/
│   ├── update-and-build.sh            # Complete automated workflow
│   ├── build-kernel.sh                # Build kernel only
│   ├── install-kernel.sh              # Install kernel + DKMS (with auto-rebuild)
│   ├── create-multi-arch-installer.sh # Create distribution installer
│   ├── update-kernel-source.sh        # Fetch upstream updates
│   ├── apply-patches.sh               # Apply CachyOS patches
│   ├── verify-patches.sh              # Verify patch integrity
│   └── auto-fix-patches.sh            # Auto-fix common patch issues
├── patches/
│   ├── cachyos-6.18/                  # CachyOS performance patches
│   └── patch-config.sh                # Patch configuration
├── configs/                           # Saved kernel configs
└── docs/
    ├── UPDATE-WORKFLOW.md             # Detailed workflow documentation
    └── QUICK-START.md                 # Quick reference guide
```

## Build Variants

### march=native (Intel Raptor Lake 13th Gen)
- Optimized for Intel Core i5-13420H and similar CPUs
- Maximum performance on target hardware
- **Version:** 6.18.3-BobZKernel

### Generic x86-64-v3
- Compatible with all modern x86-64 CPUs (2015+)
- Portable across different Intel/AMD systems
- **Version:** 6.18.3-BobZKernel-generic

## Verification

After installation, verify your kernel:

```bash
# Check kernel version
uname -r

# Check compiler used
cat /proc/version

# Verify BORE scheduler is active
cat /sys/kernel/sched_features | grep -i bore

# Check timer frequency (should show 1000)
grep CONFIG_HZ= /boot/config-$(uname -r)

# Verify LTO was used
grep CONFIG_LTO_CLANG_FULL /boot/config-$(uname -r)

# Check DKMS modules
dkms status
```

## Troubleshooting

### DKMS Module Issues
DKMS modules are automatically rebuilt with Clang during installation. If you encounter symbol version mismatches:

```bash
# The install script handles this automatically, but manual rebuild:
sudo dkms remove <module>/<version> -k $(uname -r)
sudo CC=clang dkms install <module>/<version> -k $(uname -r) \
  --kernelsourcedir=/home/bob/buildstuff/BobZKernel/builds/linux-6.18
```

### Build Logs
Build logs are saved to `build-6.18.log` after each build for troubleshooting.

## Contributing

Contributions welcome! Please ensure:
- Kernel builds successfully with LLVM=1
- All patches apply cleanly
- DKMS modules rebuild correctly
- Documentation is updated

## Credits

- **Linux Kernel** - Linus Torvalds and contributors
- **CachyOS Team** - Performance patches ([BORE scheduler](https://github.com/CachyOS/linux-cachyos), BBRv3, optimizations)
- **LLVM Project** - Clang/LLVM compiler infrastructure
- **LenovoLegionLinux** - [johnfanv2](https://github.com/johnfanv2/LenovoLegionLinux) - Lenovo Legion laptop driver
- **hid-xpadneo** - [atar-axis](https://github.com/atar-axis/xpadneo) - Advanced Xbox controller driver

## License

Linux kernel is licensed under GPLv2. CachyOS patches maintain their respective licenses.
