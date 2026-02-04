# BobZKernel - Optimized Linux 6.18.7+

Custom optimized Linux kernel 6.18.7+ with performance patches, NVMe optimization, and multi-architecture support.

## Features

### Performance Optimizations
- **BORE Scheduler** - Burst-Oriented Response Enhancer for desktop responsiveness
- **BBRv3** - TCP congestion control for improved network performance
- **Full LTO** - Link-Time Optimization using LLVM/Clang 20.1.2
- **1000Hz Timer** - Better latency for interactive workloads
- **CachyOS Patches** - Additional performance and crypto optimizations
- **NVMe Cluster-Aware IRQ Optimization** - 10-15% NVMe performance gain on modern CPUs (Intel 12th gen+, AMD Ryzen multi-CCD)

### Architecture Support
- **march=native** - CPU-specific optimizations for Intel Raptor Lake (13th Gen)
- **Generic x86-64-v3** - Universal build compatible with all modern CPUs with cluster-aware NVMe optimization
- **Pixel Slate optimized** - Lean config for Intel Skylake/Kaby Lake (WiFi 7265 only)
- **Multiple installers** - Choose the right build for your hardware

## Installation

### For End Users (Prebuilt Installer)

**Choose the installer for your CPU:**

#### Intel 12th/13th Gen (march=native)
```bash
# Download march=native package
wget https://github.com/thewraith420/BobZKernel/releases/download/v6.18.6-master/BobZKernel-6.18.6-march-native.tar.gz

# Extract and install
tar -xzf BobZKernel-6.18.6-march-native.tar.gz
sudo cp vmlinuz-6.18.6-BobZKernel /boot/
sudo cp config-6.18.6-BobZKernel /boot/
sudo update-grub
```

#### All Other CPUs (AMD, Intel 11th Gen and older, Generic x86-64)
```bash
# Download generic package with AMD GPU support
wget https://github.com/thewraith420/BobZKernel/releases/download/v6.18.6-generic/BobZKernel-6.18.6-generic-x86-64.tar.gz

# Extract and install
tar -xzf BobZKernel-6.18.6-generic-x86-64.tar.gz
sudo cp vmlinuz-6.18.6-BobZKernel-generic /boot/
sudo cp config-6.18.6-BobZKernel-generic /boot/
sudo update-grub
```

Installation includes:
- Kernel image and configuration file
- Manual bootloader update with `sudo update-grub`
- Preserves your existing kernel for safe fallback

### For Developers (Build from Source)

#### Automated Build Workflow

```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh --yes
```

This complete workflow:
1. Updates kernel source from upstream
2. Applies CachyOS performance patches
3. Applies NVMe cluster-aware IRQ optimization (automatic backport for 6.18.x)
4. Verifies patches applied correctly
5. Builds kernel with all optimizations
6. Automatically rebuilds DKMS modules (NVIDIA, VMware, Legion, xpadneo) with Clang
7. Offers portable installer creation or direct installation

#### Manual Build Steps

```bash
# Update kernel source
./scripts/update-kernel-source.sh 6.18

# Build kernel
./scripts/build-kernel.sh

# Install kernel
sudo ./scripts/install-kernel.sh
```

#### Create Portable Installer

```bash
# After building the kernel:
./scripts/create-portable-installer.sh
```

This creates a portable tarball installer that:
- Auto-detects the target system's distribution
- Includes all kernel files and modules
- Provides install/uninstall scripts
- Works across Ubuntu, Debian, Fedora, Arch, and more

## System Requirements

- **Kernel:** Linux 6.18.6
- **Compiler:** Clang 20.1.2 with LLVM
- **Target CPUs:**
  - Intel 12th/13th Gen (Alder Lake/Raptor Lake) - march=native build
  - Any modern x86-64-v3 CPU - generic build (2015+)
- **GPU Support:**
  - NVIDIA (via external driver)
  - AMD Radeon (radeon module)
  - AMD AMDGPU (amdgpu module)
  - Intel integrated graphics

## Directory Structure

```
BobZKernel/
├── builds/
│   └── linux-6.18/                    # Kernel source with patches
├── scripts/
│   ├── update-and-build.sh            # Complete automated workflow
│   ├── build-kernel.sh                # Build kernel only
│   ├── install-kernel.sh              # Install kernel locally
│   ├── create-portable-installer.sh   # Create portable installer package
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
- Full cluster-aware NVMe optimization
- **Version:** 6.18.7+-BobZKernel
- **Branch:** master

### Generic x86-64-v3 (All Modern CPUs)
- Compatible with all modern x86-64 CPUs (2015+)
- Portable across different Intel/AMD systems
- AMD GPU driver support (radeon + amdgpu)
- Includes cluster-aware NVMe optimization (fallback gracefully on older CPUs)
- **Version:** 6.18.7+-BobZKernel-generic
- **Branch:** generic-build

### Pixel Slate (Intel Skylake/Kaby Lake)
- Optimized for Google Pixel Slate with Intel Wireless 7265
- Trimmed config: only Intel WiFi/Bluetooth/graphics drivers
- No VMware, PlayStation, or Ethernet drivers
- Smallest kernel size and fastest build times
- **Version:** 6.18.7+-BobZKernel
- **Branch:** pixel-slate

### Workpc (Custom Config)
- Organization-specific optimizations
- **Branch:** workpc

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
DKMS modules are automatically detected and rebuilt with Clang during installation. The installer:
- Scans `/usr/src/*/dkms.conf` for valid modules
- Rebuilds only modules with actual source directories
- Provides verbose output showing build status for each module
- Gracefully handles individual module failures

If you still need manual rebuild after booting:
```bash
# Manual rebuild with Clang
sudo dkms remove <module>/<version> -k $(uname -r)
sudo CC=clang dkms install <module>/<version> -k $(uname -r)
```

### Build Logs
Build logs are saved with timestamps in the build directory for troubleshooting.

### VMware Module Building
If VMware modules fail to build during installation, you can rebuild them with:
```bash
# Rebuild VMware modules for current kernel
cd /tmp
mkdir -p vmware-build
cd vmware-build
tar -xf /usr/lib/vmware/modules/source/vmmon.tar
tar -xf /usr/lib/vmware/modules/source/vmnet.tar
cd vmmon-only && make && sudo make install KVER=$(uname -r)
cd ../vmnet-only && make && sudo make install KVER=$(uname -r)
```

Alternatively, if you have the BobZKernel source available locally:
```bash
# Rebuild with explicit kernel source
sudo /path/to/BobZKernel/scripts/build-vmware-modules.sh $(uname -r)
```

## Contributing

Contributions welcome! Please ensure:
- Kernel builds successfully with LLVM=1
- All patches apply cleanly
- DKMS modules rebuild correctly
- Documentation is updated

## Credits

- **Linux Kernel** - Linus Torvalds and contributors
- **CachyOS Team** - Performance patches ([BORE scheduler](https://github.com/CachyOS/linux-cachyos), BBRv3, optimizations)
- **NVMe Cluster-Aware Optimization** - Wangyang Guo (Intel) - cluster-aware IRQ affinity for modern multi-cluster CPUs
- **LLVM Project** - Clang/LLVM compiler infrastructure
- **LenovoLegionLinux** - [johnfanv2](https://github.com/johnfanv2/LenovoLegionLinux) - Lenovo Legion laptop driver
- **hid-xpadneo** - [atar-axis](https://github.com/atar-axis/xpadneo) - Advanced Xbox controller driver

## License

Linux kernel is licensed under GPLv2. CachyOS patches maintain their respective licenses.
