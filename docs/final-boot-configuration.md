# Final Boot Configuration for BobZKernel

**Date:** December 28, 2025
**Status:** Optimized and Working

---

## Boot Sequence Achievement

**Final boot experience:**
1. Lenovo logo (BIOS/UEFI)
2. Plymouth splash (keeps screen covered during kernel init)
3. Login screen

**Boot time:** ~17 seconds total (vs 30s for generic kernel)
- Firmware: 4.4s
- Loader: 2.3s
- Kernel: 2.9s
- Userspace: 8.2s

---

## Key Files Modified

### 1. GRUB Configuration
**File:** `/etc/default/grub`

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 vt.handoff=7 consoleblank=0 rd.systemd.show_status=false rd.udev.log_level=0 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 nvidia-drm.modeset=1 pcie_aspm.policy=default intel_idle.max_cstate=8 vt.global_cursor_default=0 console=tty1 systemd.unit=graphical.target"
```

**Key parameters:**
- `quiet splash` - Silent boot with Plymouth
- `loglevel=0` - Suppress kernel messages
- `vt.handoff=7` - Hand off to VT7 for display manager
- `vt.global_cursor_default=0` - Hide cursor
- `console=tty1` - Direct console to tty1
- `initcall_blacklist=simpledrm_platform_driver_init` - Prevent simpledrm (REMOVED in final config as it wasn't needed)

### 2. Initramfs Hooks

#### `/etc/initramfs-tools/hooks/exclude-nvidia-initramfs`
```bash
#!/bin/sh
# Exclude NVIDIA modules from initramfs to prevent early loading
# This fixes boot logo flickering caused by NVIDIA/i915 display handoff
# NVIDIA will still load normally after boot from /lib/modules

PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

case $1 in
prereqs)
    prereqs
    exit 0
    ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Remove NVIDIA DKMS modules from initramfs
rm -rf "${DESTDIR}/usr/lib/modules/"*/updates/dkms/nvidia*.ko* 2>/dev/null || true
rm -rf "${DESTDIR}/lib/modules/"*/updates/dkms/nvidia*.ko* 2>/dev/null || true

# Remove excessive NVIDIA firmware (keep only what's needed for this GPU)
# Your RTX 3050 is GA107, so we only need ga107 firmware
find "${DESTDIR}/usr/lib/firmware/nvidia" -mindepth 1 -maxdepth 1 -type d ! -name 'ga107' -exec rm -rf {} \; 2>/dev/null || true

exit 0
```

**Purpose:** Prevents NVIDIA from loading in initramfs
**Effect:** Reduces initramfs size, eliminates early GPU conflicts

---

#### `/etc/initramfs-tools/hooks/exclude-i915-initramfs`
```bash
#!/bin/sh
# Exclude i915 from initramfs to prevent early loading and display flickering
# i915 will load normally after boot from /lib/modules
# This gives smooth boot: BIOS logo -> Plymouth -> Login (no flicker)

PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

case $1 in
prereqs)
    prereqs
    exit 0
    ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Remove i915 module from initramfs
rm -rf "${DESTDIR}/usr/lib/modules/"*/kernel/drivers/gpu/drm/i915 2>/dev/null || true
rm -rf "${DESTDIR}/lib/modules/"*/kernel/drivers/gpu/drm/i915 2>/dev/null || true

# Remove i915 firmware as well (not needed in initramfs)
rm -rf "${DESTDIR}/usr/lib/firmware/i915" 2>/dev/null || true
rm -rf "${DESTDIR}/lib/firmware/i915" 2>/dev/null || true

exit 0
```

**Purpose:** Prevents i915 from loading in initramfs
**Effect:** Eliminates display mode-setting flicker during boot

---

#### `/etc/initramfs-tools/hooks/exclude-nouveau` (Existing)
```bash
#!/bin/sh
# Exclude nouveau driver from initramfs
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in
    prereqs) prereqs; exit 0;;
esac
rm -rf "${DESTDIR}/lib/modules/"*/kernel/drivers/gpu/drm/nouveau 2>/dev/null || true
rm -rf "${DESTDIR}/usr/lib/modules/"*/kernel/drivers/gpu/drm/nouveau 2>/dev/null || true
exit 0
```

**Purpose:** Excludes nouveau (we use NVIDIA proprietary)
**Effect:** Smaller initramfs, no driver conflicts

---

### 3. Initramfs Configuration
**File:** `/etc/initramfs-tools/initramfs.conf`

```bash
MODULES=dep
COMPRESS=zstd
```

**MODULES=dep:** Only include modules needed for boot (not "most")
**COMPRESS=zstd:** Fast decompression, good compression ratio

---

### 4. Module Blacklisting
**File:** `/etc/modprobe.d/blacklist-nouveau.conf`

```bash
blacklist nouveau
options nouveau modeset=0
```

**Purpose:** Prevent nouveau from ever loading

---

## Initramfs Size Evolution

| Stage | Size | Contents |
|-------|------|----------|
| Initial (generic) | 79MB | Minimal, no graphics drivers |
| After adding i915 | 243MB | i915 + firmware for fast display |
| After removing NVIDIA | 120MB | i915 only |
| **Final (optimal)** | **75MB** | No graphics drivers in initramfs |

**Current:** 75MB - Smaller than generic kernel!

---

## Why This Configuration Works

### The Flicker Problem
When graphics drivers load in initramfs:
1. Firmware shows BIOS logo
2. Driver loads → mode-set → brief screen reset
3. Plymouth shows Mint logo
4. Driver finishes init → another mode-set → flicker
5. Display manager starts

### The Solution
By keeping graphics drivers OUT of initramfs:
1. Firmware shows BIOS logo (stays on screen)
2. Plymouth starts (shows Mint logo)
3. Graphics drivers load from system (smooth handoff)
4. Display manager starts (clean transition)

---

## Critical Boot Sequence Timing

**BobZKernel (optimized):**
```
[0.0s]  BIOS/UEFI starts
[4.4s]  Kernel loads
[7.3s]  Userspace starts
[8.0s]  Plymouth active
[15.8s] i915 loads (from /lib/modules, not initramfs)
[16.0s] fbcon takes over
[16.0s] lightdm starts (simultaneously with fbcon)
[17.7s] Login screen ready
```

**Generic kernel (for comparison):**
```
[0.0s]  BIOS/UEFI starts
[4.4s]  Kernel loads
[17.1s] Userspace starts
[27.1s] i915 loads
[30.3s] Login screen ready
```

BobZKernel is **12.6 seconds faster!**

---

## Files to Preserve for Future Builds

### Essential System Files (Already Configured)
- `/etc/default/grub` - Boot parameters
- `/etc/initramfs-tools/initramfs.conf` - Initramfs settings
- `/etc/initramfs-tools/hooks/exclude-nvidia-initramfs` - NVIDIA exclusion
- `/etc/initramfs-tools/hooks/exclude-i915-initramfs` - i915 exclusion
- `/etc/initramfs-tools/hooks/exclude-nouveau` - Nouveau exclusion
- `/etc/modprobe.d/blacklist-nouveau.conf` - Nouveau blacklist
- `/etc/tlp.conf` - Power management (from Phase 1)
- `/etc/fstab` - EFI mount with nofail option

### Documentation (In Repository)
- `/home/bob/buildstuff/BobzKernel/docs/build-notes.md`
- `/home/bob/buildstuff/BobzKernel/docs/power-optimizations-applied.md`
- `/home/bob/buildstuff/BobzKernel/docs/ac-performance-optimizations.md`
- `/home/bob/buildstuff/BobzKernel/docs/phase1-easy-optimizations.md`
- `/home/bob/buildstuff/BobzKernel/docs/boot-flicker-fix.md`
- `/home/bob/buildstuff/BobzKernel/docs/final-boot-configuration.md` (this file)

---

## Kernel Configuration Changes (Phase 1)

### Saved in: `configs/.config`

**Network:**
- `CONFIG_TCP_CONG_BBR=y` - BBR TCP congestion control (default)
- `CONFIG_NET_SCH_CAKE=y` - CAKE QoS scheduler
- `CONFIG_NET_SCH_FQ_CODEL=y` - FQ_CODEL scheduler

**Memory:**
- `CONFIG_ZRAM=y` - Compressed swap in RAM
- `CONFIG_ZRAM_DEF_COMP_ZSTD=y` - ZSTD compression for ZRAM
- `CONFIG_ZSWAP_DEFAULT_ON=y` - Enable ZSWAP by default
- `CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD=y` - ZSTD for ZSWAP
- `CONFIG_ZSWAP_ZPOOL_DEFAULT_ZSMALLOC=y` - zsmalloc allocator
- `CONFIG_KSM=y` - Kernel same-page merging
- `CONFIG_TRANSPARENT_HUGEPAGE=y` - THP support

**I/O:**
- `CONFIG_IOSCHED_BFQ=y` - BFQ I/O scheduler
- `CONFIG_MQ_IOSCHED_KYBER=y` - Kyber scheduler
- `CONFIG_MQ_IOSCHED_DEADLINE=y` - Deadline scheduler

**QoL:**
- `CONFIG_PSI=y` - Pressure stall information
- `CONFIG_FUTEX2=y` - For Wine/Proton
- `CONFIG_BPF_JIT_ALWAYS_ON=y` - BPF JIT
- `CONFIG_SND_HRTIMER=y` - High-res audio timer

---

## Rebuild Instructions

When building a new kernel with these optimizations:

1. **Use the saved config:**
   ```bash
   cp configs/.config builds/linux/.config
   cd builds/linux
   make olddefconfig
   ```

2. **Build the kernel:**
   ```bash
   make LOCALVERSION=-BobZKernel -j10
   ```

3. **Install:**
   ```bash
   cd ../..
   sudo ./scripts/install-kernel.sh
   ```

4. **Verify hooks are in place:**
   ```bash
   ls -la /etc/initramfs-tools/hooks/exclude-*
   # Should show: exclude-i915-initramfs, exclude-nvidia-initramfs, exclude-nouveau
   ```

5. **Check GRUB config:**
   ```bash
   grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
   # Verify all boot parameters are present
   ```

The hooks will automatically run during `update-initramfs` to exclude graphics drivers.

---

## Troubleshooting

### If boot flickers return:
1. Check initramfs size: `ls -lh /boot/initrd.img-$(uname -r)`
   - Should be ~75MB, not >100MB
2. Verify graphics drivers excluded:
   ```bash
   lsinitramfs /boot/initrd.img-$(uname -r) | grep -E "i915/i915.ko|nvidia.*\.ko"
   # Should return nothing or only nvidia-wmi-ec-backlight
   ```
3. Rebuild initramfs if needed:
   ```bash
   sudo update-initramfs -u -k $(uname -r)
   ```

### If boot is slow:
1. Check boot timing: `systemd-analyze`
2. Check critical chain: `systemd-analyze critical-chain`
3. Verify TLP power settings aren't affecting boot

---

## Summary

**Achievements:**
- ✅ Clean boot (no flicker, no console text)
- ✅ Fast boot (17s vs 30s generic)
- ✅ Small initramfs (75MB vs 79MB generic)
- ✅ Phase 1 optimizations (BBR, ZRAM, ZSWAP, BFQ)
- ✅ Power management (AC performance, battery efficiency)
- ✅ All changes documented and reproducible

**Status:** Production-ready custom kernel optimized for Lenovo LOQ 15IRH8

---

**Last Updated:** December 28, 2025
