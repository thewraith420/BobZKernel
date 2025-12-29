# Power Optimizations Applied to BobZKernel

**Date Applied:** December 28, 2025
**Kernel Version:** 6.14.0-BobZKernel
**Profile:** Conservative (Recommended for stability)

## Summary

Applied comprehensive power management optimizations for the Lenovo LOQ 15IRH8 laptop with hybrid graphics (Intel UHD + NVIDIA RTX 3050). These optimizations work together with TLP to provide excellent battery life while maintaining full performance on AC power.

---

## 1. GRUB Boot Parameters

**File:** `/etc/default/grub`

**Changes Made:**
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 nvidia-drm.modeset=1 pcie_aspm.policy=default intel_idle.max_cstate=8"
```

**New Parameters Added:**
- `i915.enable_guc=3` - Enable Intel GPU GuC submission and HuC firmware loading
  - Improves GPU power efficiency
  - Expected savings: 0.3-0.7W

- `i915.enable_fbc=1` - Enable framebuffer compression
  - Reduces memory bandwidth usage
  - Expected savings: 0.1-0.3W

- `pcie_aspm.policy=default` - PCIe Active State Power Management
  - Conservative approach (can upgrade to `powersupersave` if stable)
  - Expected savings: 1-2W with aggressive policy

- `intel_idle.max_cstate=8` - Allow deepest CPU sleep states
  - Enables maximum CPU idle power savings
  - Expected savings: 0.5-1.5W during idle

**Applied by:** `sudo update-grub`
**Status:** ✅ Applied, requires reboot to take effect

---

## 2. TLP Configuration

**File:** `/etc/tlp.conf`
**Backup:** `/etc/tlp.conf.backup-YYYYMMDD-HHMMSS`

### Changes Made:

#### PCIe ASPM
```bash
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave
```
- On battery: Aggressive PCIe power management
- Expected savings: 1-2W

#### Runtime Power Management
```bash
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_DRIVER_DENYLIST="nouveau radeon"
```
- Allows devices to enter low-power states when idle
- Excludes nouveau and radeon (we use NVIDIA proprietary driver)

#### USB Autosuspend
```bash
USB_AUTOSUSPEND=1
```
- Suspends idle USB devices automatically
- If any USB device misbehaves, add to `USB_DENYLIST`

#### NVMe/SATA Power Management
```bash
AHCI_RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_BAT=auto
AHCI_RUNTIME_PM_TIMEOUT=15
```
- Enables Aggressive Link Power Management (ALPM)
- 15-second timeout before entering low-power state

#### Audio Power Saving
```bash
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1
SOUND_POWER_SAVE_CONTROLLER=Y
```
- Powers down Intel HDA audio when idle on battery
- Controller power management enabled

#### Intel GPU Frequency Scaling
```bash
INTEL_GPU_MIN_FREQ_ON_AC=0
INTEL_GPU_MIN_FREQ_ON_BAT=100
INTEL_GPU_MAX_FREQ_ON_AC=0
INTEL_GPU_MAX_FREQ_ON_BAT=800
INTEL_GPU_BOOST_FREQ_ON_AC=0
INTEL_GPU_BOOST_FREQ_ON_BAT=0
```
- On AC: No limits (0 = use defaults)
- On battery: Min 100 MHz, Max 800 MHz (reduced from 1400 MHz max)
- Hardware range: 100-1400 MHz

**Applied by:** `sudo tlp start`
**Status:** ✅ Applied and active (currently in battery mode)

---

## 3. Expected Battery Life Impact

### Conservative Profile (Current)
- **Idle:** 2-4W savings → ~30-60 minutes extra battery life
- **Light use:** 1.5-3W savings → ~20-40 minutes extra
- **Medium use:** 1-2W savings → ~15-25 minutes extra

### If Upgraded to Aggressive Profile
Potential additional savings by changing:
- `pcie_aspm.policy=default` → `pcie_aspm.policy=powersupersave`
- Add: `nvidia.NVreg_DynamicPowerManagement=2` (NVIDIA runtime PM)

Could provide:
- **Additional 5-15W savings** when NVIDIA GPU is idle
- **Total possible:** 8-20W savings during light use

---

## 4. Verification Commands

After reboot, verify the optimizations are working:

### Check TLP Status
```bash
sudo tlp-stat -s
```

### Check PCIe ASPM
```bash
sudo tlp-stat -e | grep -i aspm
```

### Check Runtime PM
```bash
sudo tlp-stat -e | grep -i runtime
```

### Check Intel GPU Frequencies
```bash
sudo tlp-stat -g
cat /sys/class/drm/card2/gt_cur_freq_mhz
cat /sys/class/drm/card2/gt_max_freq_mhz
```

### Monitor Power Consumption
```bash
sudo powertop  # Install if needed: sudo apt install powertop
```

### Check Current Draw (if supported)
```bash
cat /sys/class/power_supply/BAT0/power_now
# Divide by 1000000 to get watts
```

---

## 5. Troubleshooting

### If USB devices stop working:
1. Identify device: `lsusb`
2. Add to denylist in `/etc/tlp.conf`:
   ```bash
   USB_DENYLIST="1234:5678"  # Replace with actual device ID
   ```
3. Restart TLP: `sudo tlp start`

### If system feels sluggish on battery:
1. Increase CPU minimum performance:
   ```bash
   CPU_MIN_PERF_ON_BAT=30  # Current is 20
   ```
2. Change platform profile:
   ```bash
   PLATFORM_PROFILE_ON_BAT=balanced  # Current is "quiet"
   ```

### If NVIDIA GPU has issues waking from suspend:
(Not currently enabled, but for future reference if testing aggressive profile)
1. Remove `nvidia.NVreg_DynamicPowerManagement=2` from GRUB
2. Add nvidia to runtime PM denylist:
   ```bash
   RUNTIME_PM_DRIVER_DENYLIST="nouveau radeon nvidia"
   ```

---

## 6. Existing TLP Settings (Preserved)

These settings were already configured and remain unchanged:

```bash
TLP_ENABLE=1
DISK_IDLE_SECS_ON_BAT=0  # NVMe doesn't benefit from disk spin-down

# CPU Governor and Performance
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_MIN_PERF_ON_BAT=20

# Platform Profile
PLATFORM_PROFILE_ON_AC=balanced-performance
PLATFORM_PROFILE_ON_BAT=quiet

# WiFi Power
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=off  # Disabled for stability

# Battery Charge Threshold
STOP_CHARGE_THRESH_BAT0=1  # Custom threshold if set
```

---

## 7. Next Steps

1. **Reboot** to apply GRUB boot parameter changes
2. **Test battery life** during normal usage
3. **Monitor stability** for a few days
4. **Consider upgrading** to aggressive profile if conservative is stable

### To Upgrade to Aggressive Profile:

Edit `/etc/default/grub`:
```bash
# Change this parameter:
pcie_aspm.policy=default → pcie_aspm.policy=powersupersave

# Add this parameter:
nvidia.NVreg_DynamicPowerManagement=2
```

Then run:
```bash
sudo update-grub
sudo reboot
```

---

## 8. Files Modified

- ✅ `/etc/default/grub` - Boot parameters updated
- ✅ `/etc/tlp.conf` - Power management settings added
- ✅ Backups created for both files

**Applied:** December 28, 2025
**Ready for reboot and testing**
