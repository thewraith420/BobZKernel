# AC Performance Optimizations for BobZKernel

**Date Applied:** December 28, 2025
**Kernel Version:** 6.14.0-BobZKernel
**Profile:** Maximum Performance on AC Power

## Summary

Configured maximum performance settings for when the Lenovo LOQ 15IRH8 is plugged into AC power. These settings work automatically with TLP - when you plug in, the system switches to high-performance mode; when you unplug, it switches to power-saving mode.

---

## Philosophy: Automatic AC/Battery Switching

The power optimizations are designed to give you:
- **Maximum Performance** when plugged in (no limits, full speed)
- **Maximum Battery Life** when on battery (conservative, power-saving)
- **Automatic Switching** handled by TLP (no manual intervention needed)

---

## AC Performance Settings (Active When Plugged In)

### 1. CPU Performance
```bash
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_BOOST_ON_AC=1
SCHED_POWERSAVE_ON_AC=0
```

**What this does:**
- Sets CPU governor to "performance" mode (maximum frequency)
- Enables Intel Turbo Boost (up to 5.0 GHz)
- Disables scheduler power saving (spreads tasks across all cores for parallelism)
- CPU runs at full speed with no frequency throttling

**Performance impact:** Full CPU power available

---

### 2. Platform Profile
```bash
PLATFORM_PROFILE_ON_AC=performance
```

**What this does:**
- Sets ACPI platform profile to "performance"
- Tells firmware to prioritize performance over power saving
- Affects fan curves, thermal limits, and power delivery

**Performance impact:** Better sustained performance under load

---

### 3. Intel GPU (Integrated Graphics)
```bash
INTEL_GPU_MIN_FREQ_ON_AC=0
INTEL_GPU_MAX_FREQ_ON_AC=0
```

**What this does:**
- No frequency limits (0 = use hardware defaults)
- GPU can run from 100 MHz (idle) to 1400 MHz (full load)
- Dynamic frequency scaling based on load

**Performance impact:** Full iGPU performance available

---

### 4. PCIe ASPM (Link Power Management)
```bash
PCIE_ASPM_ON_AC=performance
```

**What this does:**
- Sets PCIe Active State Power Management to "performance" mode
- Keeps PCIe links active and responsive
- Reduces latency for NVMe SSD, WiFi, NVIDIA GPU

**Performance impact:**
- Faster NVMe SSD access
- Lower latency for discrete GPU
- Better network responsiveness

---

### 5. Runtime Power Management
```bash
RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_AC=on
```

**What this does:**
- Allows devices to enter low-power states when idle (not disabled!)
- Keeps drives responsive with fast wake-up
- Balances performance with reasonable idle power savings

**Performance impact:** Minimal - devices wake instantly when needed

---

### 6. Audio
```bash
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_CONTROLLER=Y
```

**What this does:**
- Disables audio power saving timeout on AC
- Audio hardware stays active for zero-latency playback
- Controller can still power manage when completely idle

**Performance impact:** No audio latency or pops when starting playback

---

### 7. USB
```bash
USB_AUTOSUSPEND=1
```

**What this does:**
- Allows USB devices to suspend when idle
- Does NOT affect devices while in use
- Reduces idle power consumption

**Performance impact:** None - devices wake instantly on use

---

## Battery Saving Settings (Active When Unplugged)

For comparison, here's what happens automatically on battery:

```bash
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_BOOST_ON_BAT=0                    # Turbo Boost disabled
CPU_MIN_PERF_ON_BAT=20                # Minimum 20% performance
PLATFORM_PROFILE_ON_BAT=quiet         # Silent operation priority
INTEL_GPU_MAX_FREQ_ON_BAT=800         # GPU limited to 800 MHz
PCIE_ASPM_ON_BAT=powersupersave       # Aggressive PCIe power saving
SCHED_POWERSAVE_ON_BAT=1              # Consolidate tasks to fewer cores
SOUND_POWER_SAVE_ON_BAT=1             # Power down audio when idle
```

---

## GRUB Boot Parameters

The current GRUB settings are balanced and don't need changes for AC performance:

```bash
i915.enable_guc=3           # Intel GPU microcontroller (efficiency)
i915.enable_fbc=1           # Framebuffer compression (saves bandwidth)
pcie_aspm.policy=default    # Default PCIe power management
intel_idle.max_cstate=8     # Allow deep CPU sleep when idle
nvidia-drm.modeset=1        # NVIDIA DRM kernel mode setting
```

**Why these work for both AC and battery:**
- TLP overrides `pcie_aspm.policy` dynamically (performance on AC, powersupersave on battery)
- Intel GPU features (GuC, FBC) improve efficiency without sacrificing performance
- Deep C-states only activate when CPU is idle - no impact during load
- NVIDIA modesetting is required for proper Wayland/hybrid graphics support

---

## Performance Verification

### When Plugged Into AC Power

1. **Check TLP Status:**
   ```bash
   sudo tlp-stat -s
   ```
   Should show: `Mode = ac`

2. **Verify CPU Governor:**
   ```bash
   cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```
   Should show: `performance`

3. **Check CPU Boost:**
   ```bash
   cat /sys/devices/system/cpu/intel_pstate/no_turbo
   ```
   Should show: `0` (Turbo enabled)

4. **Check Platform Profile:**
   ```bash
   cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "Not available"
   ```
   Should show: `performance` (if supported)

5. **Verify Intel GPU Frequencies:**
   ```bash
   sudo tlp-stat -g | grep "gt_.*_freq_mhz"
   ```
   Should show: No artificial limits, can reach 1400 MHz

6. **Check PCIe ASPM:**
   ```bash
   sudo tlp-stat -e | grep -i aspm
   ```
   Should show: ASPM status for devices

7. **Monitor CPU Frequencies Under Load:**
   ```bash
   watch -n 1 'grep MHz /proc/cpuinfo | head -12'
   ```
   Should reach boost frequencies (4.5-5.0 GHz under load)

---

## Expected Performance

### On AC Power:
- **CPU:** Full performance, Turbo Boost active (up to 5.0 GHz)
- **iGPU:** Up to 1400 MHz
- **NVIDIA GPU:** Full performance when active
- **NVMe SSD:** Maximum performance (PCIe Gen4 speeds)
- **Memory:** No limitations
- **Thermals:** Performance profile (fans more aggressive)

### On Battery Power:
- **CPU:** Power-efficient, Turbo Boost disabled, 20-100% performance range
- **iGPU:** Limited to 800 MHz (57% of max)
- **NVIDIA GPU:** Should be off (using iGPU only)
- **NVMe SSD:** Aggressive power management
- **Memory:** No limitations
- **Thermals:** Quiet profile (fans less aggressive)

---

## Troubleshooting

### System feels slow on AC power:

1. **Verify you're actually on AC:**
   ```bash
   sudo tlp-stat -s | grep "Mode"
   ```

2. **Check if TLP is running:**
   ```bash
   sudo systemctl status tlp
   ```

3. **Manually switch to AC mode for testing:**
   ```bash
   sudo tlp ac
   ```

### CPU not reaching boost frequencies:

1. **Check thermal throttling:**
   ```bash
   sudo tlp-stat -t
   ```

2. **Verify Turbo is enabled:**
   ```bash
   cat /sys/devices/system/cpu/intel_pstate/no_turbo
   ```
   Should be `0`. If `1`, Turbo is disabled.

3. **Check for thermal or power limits:**
   ```bash
   sudo dmesg | grep -i "throttl"
   ```

### NVIDIA GPU not performing well:

1. **Verify NVIDIA is active:**
   ```bash
   nvidia-smi
   ```

2. **Check power management mode:**
   ```bash
   nvidia-smi -q -d POWER
   ```

3. **Ensure proper driver is loaded:**
   ```bash
   lsmod | grep nvidia
   ```

---

## Advanced: Further Performance Tuning

If you need even more performance on AC, consider these additional optimizations:

### 1. Disable Runtime PM for NVIDIA
```bash
# Add to /etc/tlp.conf:
RUNTIME_PM_DRIVER_DENYLIST="nouveau radeon nvidia"
```

### 2. Force Maximum CPU Performance
```bash
# Add to /etc/tlp.conf:
CPU_MIN_PERF_ON_AC=100
CPU_MAX_PERF_ON_AC=100
```

### 3. Increase CPU TDP Limits (Advanced - may increase heat/power)
```bash
# Check current limits:
sudo rdmsr 0x610 -f 14:0  # Package power limit

# Requires additional kernel parameters and MSR tools
# Not recommended unless you understand thermal implications
```

### 4. Disable CPU C-States for Lower Latency (High Power Usage)
```bash
# Add to GRUB cmdline:
intel_idle.max_cstate=0 processor.max_cstate=0

# WARNING: Significantly increases idle power consumption
# Only use for latency-critical workloads
```

---

## Files Modified

- ✅ `/etc/tlp.conf` - AC performance settings configured
- ✅ `/etc/default/grub` - Already optimized (no changes needed)
- ✅ Backup created: `/etc/tlp.conf.backup-YYYYMMDD-HHMMSS`

---

## Summary Table

| Feature | On Battery | On AC Power |
|---------|-----------|-------------|
| CPU Governor | powersave | performance |
| Turbo Boost | Disabled | Enabled |
| CPU Min Performance | 20% | No limit |
| Platform Profile | quiet | performance |
| Intel GPU Max Freq | 800 MHz | 1400 MHz |
| PCIe ASPM | powersupersave | performance |
| Scheduler | Power save | Performance |
| Audio Power Save | Enabled | Disabled |

---

**Status:** ✅ Configured and Active
**Reboot Required:** No (TLP changes active immediately)
**Automatic:** Yes (switches automatically when you plug/unplug power)

---

## Next Steps

1. **Plug in AC power** and verify performance settings activate
2. **Run benchmarks** to confirm full performance is available
3. **Monitor temperatures** under load to ensure cooling is adequate
4. **Test battery life** to confirm power savings work when unplugged

The system is now configured for maximum performance on AC and maximum efficiency on battery!
