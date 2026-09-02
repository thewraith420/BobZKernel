# BobZKernel — Optimized Linux 7.2 (Pixel Slate variant, TESTING)

**This is the `pixel-slate-7.2` testing branch — not the daily-driver kernel.** Forked from `pixel-slate` (Linux 7.1.x, still the stable/daily-driver branch) to try Linux 7.2.x on the same hardware. All 14 patches (BORE, RSEQ, platform-profile, acpi-call, dkms-clang, and the 9200-9208 Nocturne-specific fixes) ported and verified to apply clean + compile clean against pristine v7.2.2, but **this branch has not yet been built end-to-end or run on real hardware.** Stay on `pixel-slate` (7.1) until this is proven stable, then it can replace it.

Linux 7.2.x built specifically for the **Google Pixel Slate** (codename `nocturne`). Compiled with `-march=skylake -mtune=skylake` to match the Slate's 8th gen Y-series CPU.

The config carries ~156 driver trimmings against the laptop default (most server/legacy/non-Intel drivers stripped, ChromeOS EC sensors and AVS audio kept). Result: smaller kernel image (~102 MB tarball vs ~117 MB for the laptop variant).

For the multi-variant project overview (laptop, workpc, generic, ...) see the [master branch README](https://github.com/thewraith420/BobZKernel/tree/master). For just the binary for this variant, see [v7.1.0-pixel-slate](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.0-pixel-slate).

## Hardware variants

| Variant | Branch | Target hardware | Release |
|---|---|---|---|
| **Default (laptop)** | `master` / `linux-7.1` | Intel Raptor Lake (Lenovo LOQ 15IRH8, 12th-14th gen) | [v7.1.0](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.0) |
| **workpc** | `workpc` | AMD FX-series Piledriver desktop (AM3+ with Radeon HD7000-class iGPU) | [v7.1.0-workpc](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.0-workpc) |
| **Pixel Slate** | `pixel-slate` | Google Pixel Slate (codename `nocturne`, Skylake/Kaby Lake) | [v7.1.0-pixel-slate](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.0-pixel-slate) |
| **Generic x86-64-v2** | `generic-build` | Universal modern x86-64 (Intel Nehalem 2008+, AMD Bulldozer 2011+) | [v7.1.1-generic](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.1-generic) |

Each variant uses the same core patch stack and feature set, but differs in CPU codegen target (`-march=native` / `-march=bdver2` / `-march=skylake` / `-march=x86-64-v2`) and driver subset (Pixel Slate keeps ChromeOS EC drivers + AVS audio; workpc keeps Radeon built-in for early KMS; etc.). Pick the variant that matches your hardware.

## Features

### Scheduler
- **BORE Scheduler** — Burst-Oriented Response Enhancer for desktop responsiveness (vanilla-compatible variant; CachyOS-required version intentionally not used).
- **`CONFIG_RSEQ_SLICE_EXTENSION=y`** — RSEQ time slice extension. Graduated to mainline in Linux 7.0.
  - Runtime tunable: `/sys/kernel/debug/rseq/slice_ext_nsec` (range 5000–50000 ns)
  - Observability via `/sys/kernel/debug/rseq/stats`
- **9003-rseq-latency-histogram patch** — 5-bucket abort latency histogram + `avg_ns`, ported from 6.19.
- **1000 Hz timer**, **dynamic preemption** (`CONFIG_PREEMPT_DYNAMIC=y`).

### Compiler & CPU Optimizations
- **LTO Clang Full** (`CONFIG_LTO_CLANG_FULL=y`) — whole-program link-time optimization via Clang.
- **Per-variant CPU codegen** — `-march=native` (laptop), `-march=bdver2` (workpc), `-march=skylake` (pixel-slate), or `-march=x86-64-v2` (generic).
- Built with **Clang/LLVM-19** + **ccache**.

### Storage, Memory, Network
- **NVMe cluster-aware IRQ affinity** — graduated to mainline in 7.0. Each NVMe queue pins 1:1 to a CPU.
- **ZRAM** (`CONFIG_ZRAM=y`, zstd compression).
- **ZSWAP** (`CONFIG_ZSWAP=y`, zstd compression, enabled by default).
- **BBRv3 TCP congestion control** (`CONFIG_DEFAULT_TCP_CONG="bbr"`).

### Security
- **RANDSTRUCT Full** (`CONFIG_RANDSTRUCT_FULL=y`) — randomized layouts for sensitive kernel structures. Requires NVIDIA driver to be re-patched after each driver package update (handled by `scripts/nvidia-randstruct-fix.sh`; only relevant to variants that run NVIDIA).

### DKMS Modules (laptop variant)
- **NVIDIA 610.43.02** — open kernel modules, with automatic RANDSTRUCT compatibility fixes.
- **LenovoLegionLinux** — pulled directly from upstream [johnfanv2/LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) master. The kernel patch `9100-platform-profile-accept-custom` lets userspace (TLP, etc.) write `custom` to the aggregate `/sys/firmware/acpi/platform_profile`, replacing the need for an out-of-tree profile alias.
- **xpadneo** — advanced Xbox controller driver (rumble, battery reporting, low-latency).

Other variants don't ship DKMS modules — `workpc` has an AMD Radeon iGPU, `pixel-slate` and `generic-build` are configured for their target hardware in-tree.

## Target Hardware (Pixel Slate variant)

Verified on:

- **Device**: Google Pixel Slate (codename `nocturne`)
- **CPU**: Intel 8th gen Y-series (Skylake / Kaby Lake era)
- **GPU**: Integrated Intel iGPU (`i915`)
- **EC**: Nuvoton NPCX796F running `nocturne_v2.2.x` firmware — accelerometer, gyro, light, lid switch, battery, fingerprint all routed via `cros_ec`
- **Audio**: Maxim MAX98373 codec via Intel **AVS** driver (not SOF — there's no SOF topology for the Slate's Skylake+MAX98373 combo, so kernel falls back to AVS, which works fine)
- **Display**: 3000×2000 @ 3:2 touchscreen with i2c-hid Atmel maXTouch
- **OS tested**: Ubuntu 25.10 with GNOME Shell 49.0 on Wayland

## Required userspace for full functionality

The kernel exposes the hardware correctly, but two userspace pieces are needed alongside it:

### 1. Accelerometer mount matrix (for auto-rotation)

`/etc/udev/rules.d/99-pixel-slate-accelerometer.rules`:
```
ACTION=="add", SUBSYSTEM=="iio", ATTRS{name}=="cros-ec-accel", ENV{ACCEL_MOUNT_MATRIX}="0, 1, 0; -1, 0, 0; 0, 0, 1"
```

Without this, iio-sensor-proxy has no idea how the accelerometer is physically oriented relative to the screen, and GNOME/Phosh/etc. won't auto-rotate or will rotate in the wrong direction.

### 2. Kernel cmdline (module blacklist + backlight)

Add to your kernel command line:
```
module_blacklist=hid_google_hammer,cros_usbpd_notify i915.enable_dpcd_backlight=2 i915.enable_psr=0
```

- **`hid_google_hammer`** — **required, not just a preference.** This is not "skip it if you don't use the pogo-pin keyboard": on this board (MrChromebox coreboot, no depthcharge) loading it is a **kernel crash**, a general protection fault during module load from a NULL/garbage `cros_ec_device` pointer in `__cbas_ec_probe()` (root-caused and reported upstream; see `9206-hid-google-hammer-null-check.patch`, carried in this build as defense-in-depth but not yet validated as a full replacement for the blacklist — keep the blacklist regardless of whether that patch is present). Without the blacklist, expect a GPF ~1 second into boot and a machine that eventually limps past it via deferred-probe retry ~10s later, not a clean boot.
- `cros_usbpd_notify` — known to cause dmesg spam or instability on Slate; blacklisting it is a known fix.
- **`i915.enable_dpcd_backlight=2`** (FORCE_VESA) — **required for brightness control to work.** The Slate's eDP panel sets brightness over DPCD AUX but enables the backlight via the PWM pin. This forces i915 to the VESA AUX backlight interface (skipping the Intel HDR path). Pairs with the `9200-i915-pixel-slate-aux-backlight.patch` in this build, which reverts a 7.x change that otherwise rejects this panel (it requires `AUX_ENABLE_CAP`, which the Slate lacks) and silently falls back to a non-functional native PWM backlight. Without both the patch **and** this cmdline, the brightness slider/keys appear to work but the panel never physically dims.
- `i915.enable_psr=0` — disables Panel Self-Refresh (avoids eDP quirks on this panel).

## Installation

### Build from source

Pick the variant for your hardware:

```bash
git clone https://github.com/thewraith420/BobZKernel
cd BobZKernel

# Default (laptop, march=native) — master branch is already checked out
./scripts/update-and-build-7.1.sh

# Or pick a variant:
git checkout workpc        # AMD Piledriver
git checkout pixel-slate   # Google Pixel Slate
git checkout generic-build # Universal x86-64-v2

./scripts/update-and-build-7.1.sh
```

The script handles 9 steps: detect latest `v7.1.x` tag → clean → apply patches → configure → build → install → NVIDIA DKMS check → LenovoLegionLinux DKMS update (upstream master) → summary.

First-time setup: if `builds/linux-7.1/` doesn't exist, Step 1 auto-clones the stable kernel tree.

For unattended runs:
```bash
./scripts/update-and-build-7.1.sh --yes
```

To skip the kernel update check (use whatever's already checked out):
```bash
./scripts/update-and-build-7.1.sh --skip-update
```

### Install on a different machine (portable installer)

When the build pipeline reaches Step 6, pick option 2 instead of installing locally:

```bash
./scripts/create-portable-installer-7.1.sh
# Or via the Step 6 prompt during update-and-build-7.1.sh
```

Produces a ~100-120 MB tarball. Copy to the target machine, then:

```bash
tar -xzf BobZKernel-*-installer.tar.gz
sudo ./install.sh
```

The installer auto-detects your distro and bootloader (Debian/Ubuntu/Mint, Fedora/RHEL, Arch/Manjaro, openSUSE).

### Install pre-built (from GitHub Releases)

Pre-built tarballs for the variants above are attached to their respective releases — see the [Hardware variants table](#hardware-variants).

## Verification

After reboot on the Slate:

```bash
uname -r
# 7.1.0-BobZKernel-pixel-slate (or current point release)

# BORE active
sudo sysctl kernel.sched_bore
# kernel.sched_bore = 1

# Cros-EC sensors enumerated (accel + gyro + light)
ls /sys/bus/iio/devices/
# iio:device{0..3} mapped to acpi-als, cros-ec-accel, cros-ec-gyro, cros-ec-light

# iio-sensor-proxy receiving the mount matrix from the udev rule
sudo udevadm info /sys/bus/iio/devices/iio:device1 | grep ACCEL_MOUNT_MATRIX
# E: ACCEL_MOUNT_MATRIX=0, 1, 0; -1, 0, 0; 0, 0, 1

# AVS audio modules loaded
lsmod | grep -E "^snd_soc_avs"

# monitor-sensor reports orientation (KEY auto-rotate test)
sudo monitor-sensor
# === Has accelerometer (orientation: ...)
# Tilt changed: face-up
```

## Patch Stack (7.1)

In `patches/cachyos-7.1/`:

- `0001-bore.patch` — BORE scheduler (vanilla variant, no `CONFIG_CACHY` required).
- `9003-rseq-latency-histogram.patch` — abort latency histogram (5 bins + avg_ns).
- `0001-acpi-call.patch`, `dkms-clang.patch` — CachyOS support patches.
- `9100-platform-profile-accept-custom.patch` — lets the aggregate `/sys/firmware/acpi/platform_profile` accept writes of `custom` (needed so TLP can drive the legion-laptop "custom" profile directly).

**Dropped going 7.0 → 7.1:**
- `0001-rt-i915.patch` — PREEMPT_RT compatibility shim. CachyOS dropped it for 7.1; we don't build PREEMPT_RT, so the IS_ENABLED guards compile-time-evaluate to true. The patch was a no-op for our config.
- `0001-cgroup-vram.patch` — dmem cgroup VRAM controller. Already dropped in 7.0.11 (TTM stable backports broke it); CachyOS dropped it for 7.1 too. Not exercised on single-user laptop with no container GPU workloads.

Patches pending consideration:
- **Per-thread RSEQ abort suppression** (was 9004 on 6.19, exponential backoff 10ms → 320ms).
- **Revocable Resource Management** — pure infrastructure with no in-tree consumers; deliberately not ported forward past 6.18.

## Directory Structure

```
BobZKernel/
├── builds/
│   └── linux-7.1/                  # Kernel source (gitignored — auto-cloned by build script)
├── scripts/
│   ├── update-and-build-7.1.sh     # Main pipeline (9 steps)
│   ├── build-kernel-7.1.sh         # Kernel build with LTO + ccache (per-branch KCFLAGS)
│   ├── install-kernel-7.1.sh       # Install with DKMS, initramfs, GRUB
│   ├── create-portable-installer-7.1.sh
│   ├── nvidia-randstruct-fix.sh    # Re-applies __no_randomize_layout post NVIDIA update
│   ├── configure-nvidia-suspend.sh
│   ├── monitor-rseq-stats.sh
│   └── ...                          # Plus assorted RSEQ/NVIDIA tooling
├── patches/
│   └── cachyos-7.1/                # 7.1 patch set
├── configs/
│   ├── config-7.1-march-native     # Laptop (Intel Raptor Lake)
│   ├── config-7.1-workpc           # AMD Piledriver + Radeon (on workpc branch)
│   ├── config-7.1-pixel-slate      # Google Pixel Slate (on pixel-slate branch)
│   └── config-7.1-generic          # Universal x86-64-v2 (on generic-build branch)
├── CONTEXT/                         # Project documentation
│   ├── PROJECT-OVERVIEW.md
│   ├── BUILD-STATUS.md
│   ├── BUILD-TROUBLESHOOTING.md
│   └── QUICK-START.md
└── tests/
    └── rseq-slice-extension/        # RSEQ tests (carried over from 6.19)
```

Branch tags `workpc-6.18-archive`, `generic-build-6.18-archive`, `pixel-slate-6.18-archive` preserve each variant's pre-rebase tip from before the 7.1 migration. Historical branches `linux-7.0`, `linux-6.19`, `linux-6.18` remain available for reference.

## Troubleshooting

See `CONTEXT/BUILD-TROUBLESHOOTING.md` for detailed error solutions.

**NVIDIA suspend crash after driver update** — Run `sudo scripts/nvidia-randstruct-fix.sh`. RANDSTRUCT shuffles struct layouts each kernel build; the NVIDIA DKMS source needs `__no_randomize_layout` re-applied each time the driver package is updated.

**LenovoLegionLinux platform_profile not showing up** — On kernel 7.x the driver registers a virtual platform device. If `/sys/class/platform-profile/` is empty, check `dmesg | grep legion` for probe errors; re-run the build script to pull the latest upstream LLL commit.

**TLP config writes silently rejected** — TLP doesn't validate, but the kernel does. Accepted profile names on Lenovo Legion/LOQ hardware: `low-power`, `balanced`, `performance`, `max-power`, `custom`. The `custom` profile (purple LED, AC power mode) requires patch `9100-platform-profile-accept-custom` in the running kernel — without it the aggregate sysfs returns `-EINVAL` on any write of `custom`.

**Step 7 NVIDIA DKMS failure after choosing portable installer** — Expected and benign. Step 7 tries to verify NVIDIA DKMS against the kernel that was supposed to be installed locally; if you picked option 2 (portable installer) at Step 6, no kernel was actually installed on this machine, so Step 7 has nothing to find. The portable tarball is fine.

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
