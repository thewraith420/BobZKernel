# BobZKernel — Optimized Linux 7.3

Custom optimized Linux kernel **7.3.x** with the BORE scheduler, lazy preemption, RSEQ abort latency observability, Waydroid/Android support, and performance/security tuning. Primary target is the Lenovo LOQ 15IRH8 laptop; **hardware-specific variants** live in separate branches and ship as separate GitHub releases.

## Hardware variants

| Variant | Branch | Target hardware | Release |
|---|---|---|---|
| **Default (laptop)** | `master` / `linux-7.3` | Intel Raptor Lake (Lenovo LOQ 15IRH8, 12th-14th gen) | [v7.3.5](https://github.com/thewraith420/BobZKernel/releases/tag/v7.3.5) · last 7.2: [v7.2.8](https://github.com/thewraith420/BobZKernel/releases/tag/v7.2.8) |
| **Nightfall** | `nightfall-kernel` | Most x86-64 PCs (Secure Boot off), for [Nightfall Boot Manager](https://github.com/thewraith420/nightfall-boot-manager) | [v7.2.7-nightfall](https://github.com/thewraith420/BobZKernel/releases/tag/v7.2.7-nightfall) |
| **workpc** | `workpc` | AMD FX-series Piledriver desktop (AM3+ with Radeon HD7000-class iGPU) | [v7.1.0-workpc](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.0-workpc) |
| **Generic x86-64-v2** | `generic-build` | Universal modern x86-64 (Intel Nehalem 2008+, AMD Bulldozer 2011+) | [v7.1.1-generic](https://github.com/thewraith420/BobZKernel/releases/tag/v7.1.1-generic) |
| **Pixel Slate** *(retired)* | `pixel-slate-7.2` | Google Pixel Slate (codename `nocturne`, Skylake/Kaby Lake) | [v7.2.6-pixel-slate](https://github.com/thewraith420/BobZKernel/releases/tag/v7.2.6-pixel-slate) |

Each variant uses the same core patch stack and feature set, but differs in CPU codegen target (`-march=native` / `-march=bdver2` / `-march=skylake` / `-march=x86-64-v2`) and driver subset (workpc keeps Radeon built-in for early KMS; Nightfall is trimmed to boot a wide range of PCs; etc.). Variant branches move to a new major version on their own schedule, so some are still on 7.1 or 7.2. Pick the variant that matches your hardware.

The Pixel Slate variant is retired: its test device no longer works, so nothing new can be hardware-tested on it. Its last work, including the GBOS bare-metal config, is committed on `pixel-slate-7.2`.

## New in 7.3

Things this kernel has that the 7.2 builds didn't:

- **BORE 7.0.0** (up from 6.6.3) — a major update of the scheduler, now with a configurable floor on the base time slice (`CONFIG_MIN_BASE_SLICE_NS`, 2 ms by default) so it can't overschedule and lose throughput.
- **Lazy preemption** (`CONFIG_PREEMPT_LAZY=y`) — 7.3 removes the old "voluntary" model on x86, and lazy preemption is its upstream replacement: scheduler-driven, close to full preemption, but less eager to preempt ordinary tasks while they hold locks. Still a dynamic-preempt kernel, so `preempt=full` on the kernel command line switches to full preemption without a rebuild.
- **Cache-aware load balancing** (`CONFIG_SCHED_CACHE=y`) — upstream's new option to keep a process's threads on the same last-level cache. It does nothing on the LOQ, where all 12 threads already share one L3, but it helps CPUs with several cache domains (multi-CCD Ryzen and similar).
- **Partitioned random kmalloc caches** (`CONFIG_KMALLOC_PARTITION_RANDOM=y`) — new hardening that picks a slab cache per allocation site with a per-boot random seed, making it harder for exploits to place objects next to each other. Replaces the older `RANDOM_KMALLOC_CACHES`.
- **Compressed AppArmor policy** (`CONFIG_SECURITY_APPARMOR_COMPRESSED_POLICY=y`) — policy can be loaded compressed, so userspace doesn't have to decompress its cache first, and less kernel memory is used.
- **DRM fence race fixed upstream** — a race between signalling a display fence and reading its name (`SYNC_IOC_FILE_INFO`) could hit a `BUG_ON` and panic the kernel. Android graphics code triggers it; it panicked GBOS on the Pixel Slate four times. We carried André Draszik's fix as patch 9210 on 7.2; 7.3.5 includes it, so no patch is needed.
- **NVIDIA DKMS fix for 7.3** — 7.3 changed the GPU-memory cgroup API (`dmem_cgroup_register_region()`), which breaks NVIDIA 615.x. `scripts/patch-dkms-sources.sh` now fixes the DKMS source automatically during install; newer drivers (620+) support 7.3 natively and are left alone.

## Features

### Scheduler
- **BORE Scheduler 7.0.0** — Burst-Oriented Response Enhancer for desktop responsiveness (vanilla-compatible variant; the CachyOS-only version, which needs `CONFIG_CACHY`, is intentionally not used).
- **`CONFIG_RSEQ_SLICE_EXTENSION=y`** — RSEQ time slice extension. Graduated to mainline in Linux 7.0.
  - Runtime tunable: `/sys/kernel/debug/rseq/slice_ext_nsec` (range 5000–50000 ns)
  - Observability via `/sys/kernel/debug/rseq/stats`
- **9003-rseq-latency-histogram patch** — 5-bucket abort latency histogram + `avg_ns`, ported from 6.19.
- **1000 Hz timer**, **lazy preemption** with **dynamic preemption** (`CONFIG_PREEMPT_DYNAMIC=y`), **cache-aware load balancing**.

### Compiler & CPU Optimizations
- **LTO Clang Full** (`CONFIG_LTO_CLANG_FULL=y`) — whole-program link-time optimization via Clang.
- **Per-variant CPU codegen** — `-march=native` (laptop), `-march=bdver2` (workpc), `-march=skylake` (pixel-slate), or `-march=x86-64-v2` (generic).
- Built with **Clang/LLVM-19** + **ccache**.

### Storage, Memory, Network
- **NVMe cluster-aware IRQ affinity** — graduated to mainline in 7.0. Each NVMe queue pins 1:1 to a CPU.
- **ZRAM** (`CONFIG_ZRAM=y`, zstd compression).
- **ZSWAP** (`CONFIG_ZSWAP=y`, zstd compression, enabled by default).
- **BBR TCP congestion control** (`CONFIG_DEFAULT_TCP_CONG="bbr"`, mainline BBR).

### Android / Waydroid
The laptop kernel runs Waydroid, including GoogleBook OS (GBOS) under Waydroid, with no extra modules:
- **Binder built in** (`CONFIG_ANDROID_BINDER_IPC=y`, binderfs, devices `binder,hwbinder,vndbinder`).
- **Legacy iptables** (filter/nat/mangle/raw, IPv4 + IPv6) — Android's `netd` configures networking through the legacy API, not nftables.
- **AppArmor `cred_getsecid` fix** (patch 9102) — lets binder attach a caller security context on an AppArmor-only kernel. Without it, Android 17's `odsign` aborts in a loop and boot stops at the boot animation.

### Security
- **RANDSTRUCT Full** (`CONFIG_RANDSTRUCT_FULL=y`) — randomized layouts for sensitive kernel structures.
- **Partitioned random kmalloc caches** and **compressed AppArmor policy** (see [New in 7.3](#new-in-73)).

### DKMS Modules (laptop variant)
- **NVIDIA 620.70.06** — open kernel modules. The install script fixes known kernel API breaks in the DKMS source automatically (`scripts/patch-dkms-sources.sh`).
- **LenovoLegionLinux** — pulled directly from upstream [johnfanv2/LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) master. The kernel patch `9100-platform-profile-accept-custom` lets userspace (TLP, etc.) write `custom` to the aggregate `/sys/firmware/acpi/platform_profile`, replacing the need for an out-of-tree profile alias.
- **xpadneo** — advanced Xbox controller driver (rumble, battery reporting, low-latency).

Other variants don't ship DKMS modules — `workpc` has an AMD Radeon iGPU, and `pixel-slate`, `nightfall-kernel` and `generic-build` are configured for their target hardware in-tree.

## Target Hardware (default variant)

- **Device**: Lenovo LOQ 15IRH8
- **CPU**: Intel i5-13420H (13th Gen, 8 cores / 12 threads)
- **GPU**: NVIDIA GeForce RTX 3050 6GB (Optimus — i915 display, NVIDIA render)
- **RAM**: 8 GB
- **OS**: Debian GNU/Linux 13 (trixie)

The build pipeline is parameterized; the `master` branch defaults to `march=native` for the LOQ. Other variants on their respective branches override codegen and driver subset.

## Installation

### Build from source

Pick the variant for your hardware:

```bash
git clone https://github.com/thewraith420/BobZKernel
cd BobZKernel

# Default (laptop, march=native) — master branch is already checked out
./scripts/update-and-build-7.3.sh
```

Other variants are on their own branches and build with whichever pipeline that
branch is currently on — check out the branch first and run the script that's
actually there (`ls scripts/update-and-build-*.sh`), since a variant branch may
be one or two major versions behind `master` at any given time:

```bash
git checkout nightfall-kernel # Nightfall (most x86-64 PCs)
git checkout workpc           # AMD Piledriver
git checkout generic-build    # Universal x86-64-v2

./scripts/update-and-build-7.1.sh   # or -7.2.sh / -7.3.sh, whichever that branch has
```

The script handles 9 steps: detect latest `v7.3.x` tag → clean → apply patches → configure → build → install → NVIDIA DKMS check → LenovoLegionLinux DKMS update (upstream master) → summary.

First-time setup: if `builds/linux-7.3/` doesn't exist, Step 1 auto-clones the stable kernel tree.

For unattended runs:
```bash
./scripts/update-and-build-7.3.sh --yes
```

To skip the kernel update check (use whatever's already checked out):
```bash
./scripts/update-and-build-7.3.sh --skip-update
```

### Install on a different machine (portable installer)

When the build pipeline reaches Step 6, pick option 2 instead of installing locally:

```bash
./scripts/create-portable-installer-7.3.sh
# Or via the Step 6 prompt during update-and-build-7.3.sh
```

Copy the tarball to the target machine, then:

```bash
tar -xzf BobZKernel-*-installer.tar.gz
sudo ./install.sh
```

The installer auto-detects your distro and bootloader (Debian/Ubuntu/Mint, Fedora/RHEL, Arch/Manjaro, openSUSE).

### Install pre-built (from GitHub Releases)

Pre-built tarballs for the variants above are attached to their respective releases — see the [Hardware variants table](#hardware-variants).

## Verification

After reboot, expected state on the laptop variant:

```bash
uname -r
# 7.3.5-BobZKernel (or current point release)

# LTO + native CPU
grep -E "^CONFIG_LTO_CLANG_FULL|^CONFIG_X86_NATIVE_CPU" /boot/config-$(uname -r)

# BORE active
sudo sysctl kernel.sched_bore
# kernel.sched_bore = 1

# Preemption model (the active one is in parentheses)
sudo cat /sys/kernel/debug/sched/preempt
# full (lazy)

# RSEQ slice extension + histogram
sudo cat /sys/kernel/debug/rseq/stats

# NVMe cluster-aware (each queue pinned to its own CPU)
grep nvme0q /proc/interrupts

# Lenovo platform profile choices
cat /sys/firmware/acpi/platform_profile_choices
# low-power balanced performance max-power custom

# Waydroid binder devices
ls /dev/binderfs
```

## Patch Stack (7.3)

In `patches/cachyos-7.3/`:

- `0001-bore.patch` — BORE scheduler 7.0.0 (vanilla variant, no `CONFIG_CACHY` required; from sirlucjan's `linux7.3-bore7.0.0`).
- `9003-rseq-latency-histogram.patch` — abort latency histogram (5 bins + avg_ns).
- `0001-acpi-call.patch`, `dkms-clang.patch` — CachyOS support patches.
- `9100-platform-profile-accept-custom.patch` — lets the aggregate `/sys/firmware/acpi/platform_profile` accept writes of `custom` (needed so TLP can drive the legion-laptop "custom" profile directly).
- `9101-ideapad-allow-fast-plus-conservation-charge.patch` — `ideapad-laptop` treated the EC reporting Rapid Charge + Conservation Mode together as an error (`-EINVAL` on every read of `charge_types`, roughly every 5s), but that combination is a real, intentional state on this hardware (Conservation caps the charge ceiling, Rapid Charge governs how fast it gets there below that cap). Drops the error path so `charge_types` reads a sensible value instead of bare I/O errors.
- `9102-apparmor-cred-getsecid.patch` — implements AppArmor's `cred_getsecid` hook, so binder can attach a caller security context (needed by Android 17 under Waydroid).

**Going 7.2 → 7.3: nothing dropped, one patch refreshed.** BORE moves from 6.6.3 to 7.0.0, because no 6.6.x patch exists for 7.3; sirlucjan and firelzrd/bore-scheduler both publish vanilla 7.0.0 for this kernel line (CachyOS only ships its `CONFIG_CACHY` variant). Every other patch carried forward unchanged and applies cleanly to `v7.3.5` (line offsets only, no fuzz). None of our fixes landed upstream in 7.3, so all are still needed. Config carried forward via `olddefconfig`, with one deliberate change: 7.3 removed `PREEMPT_VOLUNTARY` on x86, so this kernel uses `PREEMPT_LAZY`, its upstream replacement, rather than full preemption.

**Earlier transitions:** 7.1 → 7.2 carried everything forward unchanged. 7.0 → 7.1 dropped `0001-rt-i915.patch` (a PREEMPT_RT shim, a no-op for our config) and `0001-cgroup-vram.patch` (broken by TTM stable backports; CachyOS dropped it too).

Patches pending consideration:
- **Per-thread RSEQ abort suppression** (was 9004 on 6.19, exponential backoff 10ms → 320ms).
- **Revocable Resource Management** — pure infrastructure with no in-tree consumers; deliberately not ported forward past 6.18.

## Directory Structure

```
BobZKernel/
├── builds/
│   └── linux-7.3/                  # Kernel source (gitignored — auto-cloned by build script)
├── scripts/
│   ├── update-and-build-7.3.sh     # Main pipeline (9 steps)
│   ├── build-kernel-7.3.sh         # Kernel build with LTO + ccache (per-branch KCFLAGS)
│   ├── install-kernel-7.3.sh       # Install with DKMS, initramfs, GRUB
│   ├── create-portable-installer-7.3.sh
│   ├── patch-dkms-sources.sh       # Fixes known kernel API breaks in DKMS sources before building
│   ├── nvidia-randstruct-fix.sh    # Older NVIDIA RANDSTRUCT workaround (see Troubleshooting)
│   ├── configure-nvidia-suspend.sh
│   ├── monitor-rseq-stats.sh
│   └── ...                          # Plus assorted RSEQ/NVIDIA tooling, and the 7.2 scripts
├── patches/
│   └── cachyos-7.3/                # 7.3 patch set (older sets kept alongside)
├── configs/
│   └── config-7.3-march-native     # Laptop (Intel Raptor Lake); variant configs live on their branches
├── CONTEXT/                         # Project documentation
│   ├── PROJECT-OVERVIEW.md
│   ├── BUILD-STATUS.md
│   ├── BUILD-TROUBLESHOOTING.md
│   └── QUICK-START.md
└── tests/
    └── rseq-slice-extension/        # RSEQ tests (carried over from 6.19)
```

Branch tags `workpc-6.18-archive`, `generic-build-6.18-archive`, `pixel-slate-6.18-archive` preserve each variant's pre-rebase tip from before the 7.1 migration. Historical branches `linux-7.2`, `linux-7.1`, `linux-7.0`, `linux-6.19`, `linux-6.18` remain available for reference — each frozen at its confirmed-working tip at the point `master` moved on to the next major version.

## Troubleshooting

See `CONTEXT/BUILD-TROUBLESHOOTING.md` for detailed error solutions.

**NVIDIA fails to build for a new kernel** — `scripts/install-kernel-7.3.sh` runs `scripts/patch-dkms-sources.sh` first, which fixes known kernel API breaks in the NVIDIA DKMS source (currently the 6.18 `get_dev_pagemap()` change and the 7.3 `dmem_cgroup_register_region()` change). It only touches the exact old code, so drivers that already support the kernel are left alone.

**NVIDIA suspend crash with RANDSTRUCT** — Older drivers (610.x and earlier) needed `sudo scripts/nvidia-randstruct-fix.sh` after every driver update: RANDSTRUCT shuffled a callback struct shared with NVIDIA's precompiled blob, so suspend called the wrong function. From 615 on, NVIDIA protects that struct itself (it adds a non-pointer field, which exempts the struct from shuffling), so the script should no longer be needed. Suspend has not yet been tested on 615+; if it hangs, run the script and report it.

**LenovoLegionLinux platform_profile not showing up** — On kernel 7.x the driver registers a virtual platform device. If `/sys/class/platform-profile/` is empty, check `dmesg | grep legion` for probe errors; re-run the build script to pull the latest upstream LLL commit.

**TLP config writes silently rejected** — TLP doesn't validate, but the kernel does. Accepted profile names on Lenovo Legion/LOQ hardware: `low-power`, `balanced`, `performance`, `max-power`, `custom`. The `custom` profile (purple LED, AC power mode) requires patch `9100-platform-profile-accept-custom` in the running kernel — without it the aggregate sysfs returns `-EINVAL` on any write of `custom`. Fn+Q overrides the profile by hand until TLP sets it again.

**Step 7 NVIDIA DKMS failure after choosing portable installer** — Expected and benign. Step 7 tries to verify NVIDIA DKMS against the kernel that was supposed to be installed locally; if you picked option 2 (portable installer) at Step 6, no kernel was actually installed on this machine, so Step 7 has nothing to find. The portable tarball is fine.

## Credits

- **Linux Kernel** — Linus Torvalds and contributors.
- **Thomas Gleixner** — RSEQ time slice extension mechanism (graduated to mainline in 7.0).
- **Masahito Suzuki** — BORE CPU scheduler.
- **Piotr Gorski (sirlucjan)** — vanilla BORE patches for each kernel release.
- **André Draszik (Linaro)** — DRM CRTC fence race fix (carried as 9210 on 7.2, upstream in 7.3).
- **Tzung-Bi Shih (Google)** — Revocable resource management (6.18 backport).
- **CachyOS Team** — Performance patches.
- **LLVM Project** — Clang/LLVM compiler infrastructure.
- **johnfanv2 and contributors** — [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux) (upstream).
- **atar-axis** — [xpadneo](https://github.com/atar-axis/xpadneo) Xbox controller driver.

## License

Linux kernel is licensed under GPLv2. Patches retain their respective upstream licenses.
