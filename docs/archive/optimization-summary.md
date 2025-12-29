# Kernel Optimization Summary for 6.14.0-BobZKernel

## Optimizations Applied

### 1. Initramfs Size Reduction

**Before:** 662MB → 296MB → **Target: ~100MB**

**Changes:**
- ✅ Changed `MODULES=most` to `MODULES=dep` (only load needed modules)
- ✅ Disabled nouveau driver in kernel (CONFIG_DRM_NOUVEAU=n)
- ✅ Disabled XE driver in kernel (CONFIG_DRM_XE=n)
- ✅ Blacklisted nouveau in /etc/modprobe.d/
- ✅ Excluded old NVIDIA firmware versions
- ✅ Excluded LVM tools (not using LVM)

**Expected Savings:**
- Nouveau: -237MB
- XE: -110MB
- Old firmware: -144MB
- Total: ~390MB saved

### 2. Power Management Features

**Kernel Config Changes:**
- ✅ Enabled PCIe ASPM (CONFIG_PCIEASPM=y)
- ✅ Enabled Intel IDLE driver (CONFIG_INTEL_IDLE=y)
- ✅ Enabled Intel RAPL power monitoring (CONFIG_INTEL_RAPL=y)
- ✅ Thermal management (Intel PowerClamp, PKG_TEMP, etc.)

**Expected Benefits:**
- 1-2W power savings on battery from PCIe ASPM
- Better CPU C-state transitions
- Improved thermal management

### 3. Boot Configuration (NVMe Fix)

**Critical Fixes:**
- ✅ NVMe drivers built into kernel (CONFIG_BLK_DEV_NVME=y)
- ✅ NVMe core built-in (CONFIG_NVME_CORE=y)
- ✅ Prevents "can't find root fs" kernel panic

### 4. Next Steps (Pending)

**GRUB Configuration:**
Add to /etc/default/grub:
```
pcie_aspm.policy=powersupersave
intel_idle.max_cstate=8
```

**TLP Enhancements:**
- Configure PCIe ASPM policy per power mode
- Enable NVIDIA runtime PM on battery
- Optimize CPU scaling

### 5. Hardware-Specific Optimizations

**CPU:** Intel Core i5-13420H (Raptor Lake)
- Using Intel P-state driver
- HWP (Hardware P-States) enabled
- EPP (Energy Performance Preference) available

**GPU:** Hybrid Graphics
- Intel UHD (i915) - integrated, always on
- NVIDIA RTX 3050 - discrete, can suspend on battery

**Storage:** NVMe SSD
- NVMe power management enabled
- Built-in drivers for fast boot

## Estimated Impact

### Battery Life (compared to stock kernel)
- **Idle:** +15-25% (PCIe ASPM, better C-states)
- **Light use:** +10-15% (dynamic power management)
- **Heavy use:** +5-10% (thermal improvements)

### Performance on AC
- **Gaming:** Same or better (no power limits)
- **CPU:** Full performance mode available
- **GPU:** Full RTX 3050 performance

### Boot Time
- **Faster:** Smaller initramfs loads quicker
- **More reliable:** NVMe built-in prevents panics

## Files Modified

- /home/bob/buildstuff/BobzKernel/configs/.config
- /etc/initramfs-tools/initramfs.conf (MODULES=dep)
- /etc/modprobe.d/blacklist-nouveau.conf
- /etc/initramfs-tools/conf.d/exclude-old-firmware.conf
- /etc/initramfs-tools/conf.d/no-lvm.conf
- /home/bob/buildstuff/BobzKernel/scripts/install-kernel.sh (DKMS auto-build)

## Build Command

```bash
cd /home/bob/buildstuff/BobzKernel
./scripts/build-kernel.sh 8
sudo ./scripts/install-kernel.sh
```

## Verification

After boot, check:
```bash
# Verify initramfs size (should be ~100MB)
ls -lh /boot/initrd.img-6.14.0-BobZKernel

# Check PCIe ASPM is available
cat /sys/module/pcie_aspm/parameters/policy

# Verify NVIDIA modules loaded
nvidia-smi

# Check power consumption (on battery)
sudo powertop
```
