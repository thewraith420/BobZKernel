# BobZKernel — Optimized Linux 7.0

Custom optimized Linux kernel 7.0.x with the BORE scheduler, RSEQ abort latency observability, and performance/security tuning targeted at the Lenovo LOQ 15IRH8.

## Features

### Scheduler
- **BORE Scheduler** — Burst-Oriented Response Enhancer for desktop responsiveness (vanilla-compatible variant; CachyOS-required version intentionally not used).
- **`CONFIG_RSEQ_SLICE_EXTENSION=y`** — RSEQ time slice extension. Graduated to mainline in Linux 7.0; was custom patch 9002 in 6.19.
  - Runtime tunable: `/sys/kernel/debug/rseq/slice_ext_nsec` (range 5000–50000 ns)
  - Observability via `/sys/kernel/debug/rseq/stats`
- **9003-rseq-latency-histogram patch** — 5-bucket abort latency histogram + `avg_ns`, ported from 6.19.
- **1000 Hz timer**, **dynamic preemption** (`CONFIG_PREEMPT_DYNAMIC=y`).

### Compiler & CPU Optimizations
- **LTO Clang Full** (`CONFIG_LTO_CLANG_FULL=y`) — whole-program link-time optimization via Clang.
- **march=native** (`CONFIG_X86_NATIVE_CPU=y`) — tuned for Intel i5-13420H (13th Gen Raptor Lake).
- Built with **Clang/LLVM-19** + **ccache**.

### Storage, Memory, Network
- **NVMe cluster-aware IRQ affinity** — graduated to mainline in 7.0; was patch 9010 in 6.19. Each NVMe queue pins 1:1 to a CPU.
- **ZRAM** (`CONFIG_ZRAM=y`, zstd compression).
- **ZSWAP** (`CONFIG_ZSWAP=y`, zstd compression, enabled by default).
- **BBRv3 TCP congestion control** (`CONFIG_DEFAULT_TCP_CONG="bbr"`).

### Security
- **RANDSTRUCT Full** (`CONFIG_RANDSTRUCT_FULL=y`) — randomized layouts for sensitive kernel structures. Requires NVIDIA driver to be re-patched after each driver package update (handled by `scripts/nvidia-randstruct-fix.sh`).

### DKMS Modules (Auto-Rebuilt by Build Pipeline)
- **NVIDIA 610.43.02** — open kernel modules, with automatic RANDSTRUCT compatibility fixes.
- **LenovoLegionLinux** — pulled directly from upstream [johnfanv2/LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) master. The kernel patch `9100-platform-profile-accept-custom` lets userspace (TLP, etc.) write `custom` to the aggregate `/sys/firmware/acpi/platform_profile`, replacing the need for an out-of-tree profile alias.
- **xpadneo** — advanced Xbox controller driver (rumble, battery reporting, low-latency).

## Target Hardware

- **Device**: Lenovo LOQ 15IRH8
- **CPU**: Intel i5-13420H (13th Gen, 8 cores / 12 threads)
- **GPU**: NVIDIA GeForce RTX 3050 6GB (Optimus — i915 display, NVIDIA render)
- **RAM**: 8 GB
- **OS**: Debian GNU/Linux 13 (trixie)

The build pipeline is parameterized enough that it should work on similar hardware; the kernel config is named `config-7.0-march-native` to make it clear that the binary is hardware-specific.

## Installation

### Build from source

```bash
./scripts/update-and-build-7.0.sh
```

The script handles 9 steps: detect latest `v7.0.x` tag → clean → apply patches → configure → build → install → NVIDIA DKMS check → LenovoLegionLinux DKMS update (upstream master) → summary.

For unattended runs:
```bash
./scripts/update-and-build-7.0.sh --yes
```

To skip the kernel update check (use whatever's already checked out):
```bash
./scripts/update-and-build-7.0.sh --skip-update
```

### Install on a different machine (portable installer)

```bash
./scripts/create-portable-installer.sh 7.0
# Copy the resulting tarball, then on target:
tar -xzf BobZKernel-*-installer.tar.gz
cd installer-*/
sudo ./install.sh
```

## Verification

After reboot, expected state:

```bash
uname -r
# 7.0.11-BobZKernel (or current point release)

# LTO + native CPU
grep -E "^CONFIG_LTO_CLANG_FULL|^CONFIG_X86_NATIVE_CPU" /boot/config-$(uname -r)

# BORE active
sudo sysctl kernel.sched_bore
# kernel.sched_bore = 1

# RSEQ slice extension + histogram
sudo cat /sys/kernel/debug/rseq/stats

# NVMe cluster-aware (each queue pinned to its own CPU)
grep nvme0q /proc/interrupts

# Lenovo platform profile choices
cat /sys/firmware/acpi/platform_profile_choices
# low-power balanced performance max-power custom
```

## Patch Stack (7.0)

In `patches/cachyos-7.0/`:

- `0001-bore.patch` — BORE scheduler (vanilla variant, no `CONFIG_CACHY` required).
- `9003-rseq-latency-histogram.patch` — abort latency histogram (5 bins + avg_ns).
- `0001-acpi-call.patch`, `0001-rt-i915.patch`, `dkms-clang.patch` — CachyOS support patches.
- `9100-platform-profile-accept-custom.patch` — lets the aggregate `/sys/firmware/acpi/platform_profile` accept writes of `custom` (needed so TLP can drive the legion-laptop "custom" profile directly).

Patches pending consideration for 7.0:
- **Per-thread RSEQ abort suppression** (was 9004 on 6.19, exponential backoff 10ms → 320ms).
- **Revocable Resource Management** (was 6.18-only, never ported forward).

## Directory Structure

```
BobZKernel/
├── builds/
│   └── linux-7.0/                # Kernel source (gitignored — checked out by build script)
├── scripts/
│   ├── update-and-build-7.0.sh   # Main pipeline (9 steps)
│   ├── build-kernel-7.0.sh       # Kernel build with LTO + ccache
│   ├── install-kernel-7.0.sh     # Install with DKMS, initramfs, GRUB
│   ├── nvidia-randstruct-fix.sh  # Re-applies __no_randomize_layout post NVIDIA update
│   ├── configure-nvidia-suspend.sh
│   ├── monitor-rseq-stats.sh
│   └── ...                        # Plus assorted RSEQ/NVIDIA tooling
├── patches/
│   └── cachyos-7.0/              # 7.0 patch set
├── configs/
│   └── config-7.0-march-native   # Kernel config (LTO Full, march=native, ...)
├── CONTEXT/                       # Project documentation
│   ├── PROJECT-OVERVIEW.md
│   ├── BUILD-STATUS.md
│   ├── BUILD-TROUBLESHOOTING.md
│   ├── QUICK-START.md
│   └── DEBUG-PRINTK-LOCATIONS.md  # RSEQ debug printk reference
└── tests/
    └── rseq-slice-extension/      # RSEQ tests (carried over from 6.19)
```

Legacy branches `linux-6.19`, `linux-6.18`, etc. remain available for historical reference.

## Troubleshooting

See `CONTEXT/BUILD-TROUBLESHOOTING.md` for detailed error solutions.

**NVIDIA suspend crash after driver update** — Run `sudo scripts/nvidia-randstruct-fix.sh`. RANDSTRUCT shuffles struct layouts each kernel build; the NVIDIA DKMS source needs `__no_randomize_layout` re-applied each time the driver package is updated.

**LenovoLegionLinux platform_profile not showing up** — On kernel 7.0 the driver registers a virtual platform device. If `/sys/class/platform-profile/` is empty, check `dmesg | grep legion` for probe errors; re-run the build script to pull the latest upstream LLL commit.

**TLP config writes silently rejected** — TLP doesn't validate, but the kernel does. Accepted profile names on this hardware: `low-power`, `balanced`, `performance`, `max-power`, `custom`. The `custom` profile (purple LED, AC power mode) requires patch `9100-platform-profile-accept-custom` in the running kernel — without it the aggregate sysfs returns `-EINVAL` on any write of `custom`.

## Credits

- **Linux Kernel** — Linus Torvalds and contributors.
- **Thomas Gleixner** — RSEQ time slice extension mechanism (graduated to mainline in 7.0).
- **Masahito Suzuki** — BORE CPU scheduler.
- **Tzung-Bi Shih (Google)** — Revocable resource management (6.18 backport).
- **CachyOS Team** — Performance patches.
- **LLVM Project** — Clang/LLVM compiler infrastructure.
- **johnfanv2 and contributors** — [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) (upstream).
- **atar-axis** — [xpadneo](https://github.com/atar-axis/xpadneo) Xbox controller driver.

## License

Linux kernel is licensed under GPLv2. Patches retain their respective upstream licenses.
