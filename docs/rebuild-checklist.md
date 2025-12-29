# BobZKernel Rebuild Checklist

When rebuilding the kernel from scratch or on a new system, here's what carries over automatically vs what needs to be configured.

---

## ✅ Automatic (Saved in Kernel Config)

These are **built into the kernel** via `configs/.config`:

**Network:**
- ✅ BBR TCP congestion control (default)
- ✅ CAKE QoS scheduler
- ✅ FQ_CODEL scheduler

**Memory:**
- ✅ ZRAM with ZSTD compression
- ✅ ZSWAP with ZSTD + zsmalloc (enabled by default)
- ✅ KSM (Kernel Same-Page Merging)
- ✅ Transparent Huge Pages

**I/O:**
- ✅ BFQ scheduler
- ✅ Kyber scheduler
- ✅ Deadline scheduler

**QoL:**
- ✅ PSI (Pressure Stall Information)
- ✅ FUTEX2 (Wine/Proton support)
- ✅ BPF JIT always on

**Build Settings:**
- ✅ NVMe drivers built-in (not modules)
- ✅ Module compression: ZSTD
- ✅ Kernel compression: ZSTD
- ✅ BTF debug: Disabled

**When you run:**
```bash
make KCONFIG_CONFIG=../../configs/.config LOCALVERSION=-BobZKernel -j10
```
All these features are automatically included!

---

## ⚠️ Manual (System Configuration)

These are **system-level configs** that need to be in place:

### 1. Initramfs Hooks (Critical for Clean Boot)
**Location:** `/etc/initramfs-tools/hooks/`

**Required files:**
- `exclude-nvidia-initramfs` - Prevents NVIDIA early loading
- `exclude-i915-initramfs` - Prevents i915 early loading
- `exclude-nouveau` - Excludes nouveau driver

**Status:** ✅ Already installed on your system
**Restore:** `sudo ./system-configs/restore-configs.sh`

**Without these:** Initramfs will be huge (~243MB) and boot will flicker

---

### 2. Initramfs Configuration
**Location:** `/etc/initramfs-tools/initramfs.conf`

**Required settings:**
```bash
MODULES=dep
COMPRESS=zstd
```

**Status:** ✅ Already configured
**Restore:** `sudo ./system-configs/restore-configs.sh`

**Without this:** Initramfs will include unnecessary modules

---

### 3. GRUB Boot Parameters
**Location:** `/etc/default/grub`

**Required line:**
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 vt.handoff=7 consoleblank=0 rd.systemd.show_status=false rd.udev.log_level=0 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 nvidia-drm.modeset=1 pcie_aspm.policy=default intel_idle.max_cstate=8 vt.global_cursor_default=0 console=tty1 systemd.unit=graphical.target"
```

**Status:** ✅ Already configured
**Restore:** `sudo ./system-configs/restore-configs.sh` then `sudo update-grub`

**Without this:** No silent boot, no power optimizations

---

### 4. TLP Power Management
**Location:** `/etc/tlp.conf`

**Required:** AC/Battery power profiles configured

**Status:** ✅ Already configured
**Restore:** `sudo ./system-configs/restore-configs.sh`

**Without this:** No automatic power switching, battery life not optimized

---

### 5. Module Blacklists
**Location:** `/etc/modprobe.d/blacklist-nouveau.conf`

**Required:**
```bash
blacklist nouveau
options nouveau modeset=0
```

**Status:** ✅ Already configured
**Restore:** `sudo ./system-configs/restore-configs.sh`

**Without this:** Nouveau might conflict with NVIDIA

---

### 6. fstab EFI Mount
**Location:** `/etc/fstab`

**Required:** EFI partition with `nofail,x-systemd.device-timeout=1`

**Status:** ✅ Already configured
**Restore:** Manually edit or use `sudo ./system-configs/restore-configs.sh`

**Without this:** Boot might pause at EFI mount

---

## Fresh System Setup

If setting up BobZKernel on a **fresh Linux Mint installation**:

### Step 1: Install Dependencies
```bash
sudo apt-get update
sudo apt-get install -y build-essential bc bison flex libelf-dev libssl-dev \
    libncurses-dev zstd dkms tlp
```

### Step 2: Restore System Configurations
```bash
cd /home/bob/buildstuff/BobzKernel
sudo ./system-configs/restore-configs.sh
```

This will automatically configure:
- GRUB parameters
- Initramfs hooks and config
- TLP power management
- Module blacklists
- fstab

### Step 3: Build Kernel
```bash
cd builds/linux
make KCONFIG_CONFIG=../../configs/.config LOCALVERSION=-BobZKernel -j10
```

### Step 4: Install
```bash
cd ../..
sudo ./scripts/install-kernel.sh
```

### Step 5: Reboot
```bash
sudo reboot
```

---

## Existing System (Just Rebuilding)

If you're just rebuilding on the **current system** (everything already configured):

```bash
# Build
cd builds/linux
make KCONFIG_CONFIG=../../configs/.config LOCALVERSION=-BobZKernel -j10

# Install
cd ../..
sudo ./scripts/install-kernel.sh

# Reboot
sudo reboot
```

**The install script automatically:**
1. Installs kernel image
2. Installs and compresses modules
3. Builds DKMS modules (NVIDIA)
4. Generates initramfs (hooks auto-run)
5. Updates GRUB

Everything just works!

---

## Verification After Build

### Check Kernel Config Was Used
```bash
zcat /proc/config.gz | grep CONFIG_TCP_CONG_BBR
# Should show: CONFIG_TCP_CONG_BBR=y
```

### Check Initramfs Size
```bash
ls -lh /boot/initrd.img-6.14.0-BobZKernel
# Should be ~75MB (not >100MB)
```

### Check Graphics Drivers Excluded
```bash
lsinitramfs /boot/initrd.img-6.14.0-BobZKernel | grep -E "i915/i915.ko|nvidia.*\.ko" | wc -l
# Should be 0 or 1 (only nvidia-wmi-ec-backlight is OK)
```

### Check GRUB Parameters
```bash
cat /proc/cmdline | grep "i915.enable_guc"
# Should show the parameter in the command line
```

### Check TLP Active
```bash
sudo tlp-stat -s | grep "State"
# Should show: State = enabled
```

---

## Summary

| Component | Automatic? | Location |
|-----------|-----------|----------|
| **Kernel optimizations** | ✅ Yes | `configs/.config` |
| **Initramfs hooks** | ❌ No | `/etc/initramfs-tools/hooks/` |
| **Initramfs config** | ❌ No | `/etc/initramfs-tools/initramfs.conf` |
| **GRUB parameters** | ❌ No | `/etc/default/grub` |
| **TLP config** | ❌ No | `/etc/tlp.conf` |
| **Module blacklists** | ❌ No | `/etc/modprobe.d/` |

**On current system:** Just rebuild and install - system configs already in place
**On fresh system:** Run `restore-configs.sh` first, then build

---

**Last Updated:** December 28, 2025
