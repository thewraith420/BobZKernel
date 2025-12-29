# TLP Configuration Optimizations for Hybrid Graphics

## Current TLP Configuration Analysis

**Current Settings (Good):**
- ✓ CPU governor: `performance` on AC, `powersave` on battery
- ✓ Energy policy: `performance` on AC, `balance_power` on battery
- ✓ Platform profile: `balanced-performance` on AC, `quiet` on battery
- ✓ WiFi power: off (good for stability)

**Missing/Recommended Settings:**
- PCIe ASPM policy control
- Runtime PM for devices
- NVIDIA GPU runtime power management
- USB autosuspend tuning
- NVMe power management

## Recommended TLP Additions

### 1. PCIe ASPM Control
Work with kernel boot parameters for maximum power savings

```bash
# PCIe Active State Power Management
# On AC: use default/performance for stability
# On battery: use powersupersave for maximum savings
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave
```

### 2. Runtime Power Management
Enable aggressive runtime PM for devices on battery

```bash
# Runtime PM for PCI(e) devices
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

# Exclude nouveau from runtime PM (we use nvidia)
RUNTIME_PM_DRIVER_DENYLIST="nouveau radeon"
```

### 3. NVIDIA GPU Power Management
Critical for battery life - allow NVIDIA to suspend when idle

```bash
# NVIDIA GPU runtime power management
# Requires nvidia.NVreg_DynamicPowerManagement=2 in kernel cmdline
# On battery, enable runtime PM for NVIDIA GPU
RUNTIME_PM_ON_BAT=auto

# Alternatively, for more aggressive control:
# Disable NVIDIA GPU completely on battery (use Intel only)
# Uncomment if you don't need discrete GPU on battery:
# RUNTIME_PM_DEVICE_DENYLIST="0000:01:00.0"  # NVIDIA GPU PCI address
```

### 4. USB Autosuspend
Save power by suspending idle USB devices

```bash
# USB autosuspend
USB_AUTOSUSPEND=1

# Exclude devices that don't work well with autosuspend (e.g., some mice)
# USB_DENYLIST="1234:5678"  # Add problematic device IDs if needed
```

### 5. NVMe Power Management
Your NVMe SSD supports power states - use them

```bash
# NVMe power saving
# ALPM: Aggressive Link Power Management
AHCI_RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_BAT=auto

# NVMe ASPM
AHCI_RUNTIME_PM_TIMEOUT=15
```

### 6. Audio Power Saving
Intel HDA audio can power down when idle

```bash
# Audio power saving
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1
SOUND_POWER_SAVE_CONTROLLER=Y
```

### 7. Intel GPU Power Management (i915)
Work with kernel parameters for best results

```bash
# Intel GPU frequency limits
# On AC: no limits
# On battery: limit max frequency for power savings
INTEL_GPU_MIN_FREQ_ON_AC=0
INTEL_GPU_MIN_FREQ_ON_BAT=0
INTEL_GPU_MAX_FREQ_ON_AC=0
INTEL_GPU_MAX_FREQ_ON_BAT=800

# Intel GPU boost
INTEL_GPU_BOOST_FREQ_ON_AC=0
INTEL_GPU_BOOST_FREQ_ON_BAT=0
```

## Complete Recommended TLP Configuration

Add these lines to `/etc/tlp.conf`:

```bash
# PCIe ASPM
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# Runtime Power Management
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_DRIVER_DENYLIST="nouveau radeon"

# USB Autosuspend
USB_AUTOSUSPEND=1

# SATA/NVMe ALPM
AHCI_RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_BAT=auto
AHCI_RUNTIME_PM_TIMEOUT=15

# Audio Power Saving
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1
SOUND_POWER_SAVE_CONTROLLER=Y

# Intel GPU Frequency Scaling
INTEL_GPU_MIN_FREQ_ON_AC=0
INTEL_GPU_MIN_FREQ_ON_BAT=0
INTEL_GPU_MAX_FREQ_ON_AC=0
INTEL_GPU_MAX_FREQ_ON_BAT=800
INTEL_GPU_BOOST_FREQ_ON_AC=0
INTEL_GPU_BOOST_FREQ_ON_BAT=0

# Disk settings (keep your current DISK_IDLE_SECS_ON_BAT=0)
# No changes needed - NVMe doesn't benefit from APM

# Keep your existing settings:
# TLP_ENABLE=1
# DISK_IDLE_SECS_ON_BAT=0
# CPU_SCALING_GOVERNOR_ON_AC=performance
# CPU_SCALING_GOVERNOR_ON_BAT=powersave
# CPU_ENERGY_PERF_POLICY_ON_AC=performance
# CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
# CPU_MIN_PERF_ON_BAT=20
# PLATFORM_PROFILE_ON_AC=balanced-performance
# PLATFORM_PROFILE_ON_BAT=quiet
# WIFI_PWR_ON_AC=off
# WIFI_PWR_ON_BAT=off
# STOP_CHARGE_THRESH_BAT0=1
```

## How to Apply

### Option 1: Manual Edit
```bash
sudo nano /etc/tlp.conf
# Add the recommended settings
sudo tlp start  # Restart TLP to apply changes
```

### Option 2: Script (Automated)
```bash
#!/bin/bash
# Backup current TLP config
sudo cp /etc/tlp.conf /etc/tlp.conf.backup-$(date +%Y%m%d-%H%M%S)

# Append optimizations
sudo tee -a /etc/tlp.conf > /dev/null << 'EOF'

# === Power Optimizations for Lenovo LOQ 15IRH8 ===
# Added: $(date)

# PCIe ASPM
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# Runtime Power Management
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_DRIVER_DENYLIST="nouveau radeon"

# USB Autosuspend
USB_AUTOSUSPEND=1

# SATA/NVMe ALPM
AHCI_RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_BAT=auto
AHCI_RUNTIME_PM_TIMEOUT=15

# Audio Power Saving
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1
SOUND_POWER_SAVE_CONTROLLER=Y

# Intel GPU Frequency Scaling
INTEL_GPU_MIN_FREQ_ON_AC=0
INTEL_GPU_MIN_FREQ_ON_BAT=0
INTEL_GPU_MAX_FREQ_ON_AC=0
INTEL_GPU_MAX_FREQ_ON_BAT=800
INTEL_GPU_BOOST_FREQ_ON_AC=0
INTEL_GPU_BOOST_FREQ_ON_BAT=0
EOF

# Restart TLP
sudo tlp start

echo "TLP optimizations applied!"
echo "Check status with: tlp-stat -s"
```

## Expected Impact

### On Battery
- **Idle power:** -2 to -4W (significant battery life increase)
- **Light use:** -1.5 to -3W
- **NVIDIA GPU suspended:** -5 to -15W when not gaming

### On AC
- **Performance:** No impact (performance settings maintained)
- **Gaming:** Full GPU power available
- **No throttling:** All limits removed on AC

## Verification Commands

After applying changes:

```bash
# Check TLP status
sudo tlp-stat -s

# Check PCIe ASPM status
sudo tlp-stat -e | grep -i aspm

# Check runtime PM status
sudo tlp-stat -e | grep -i runtime

# Check GPU frequencies
sudo intel_gpu_frequency  # If available
cat /sys/class/drm/card0/gt_cur_freq_mhz

# Monitor power consumption (install powertop first)
sudo powertop
```

## Troubleshooting

**If USB devices stop working:**
- Add device ID to USB_DENYLIST

**If NVIDIA doesn't wake from suspend:**
- Remove nvidia.NVreg_DynamicPowerManagement=2 from kernel cmdline
- Set RUNTIME_PM_DRIVER_DENYLIST to include nvidia

**If system feels sluggish on battery:**
- Increase CPU_MIN_PERF_ON_BAT from 20 to 30 or 40
- Change PLATFORM_PROFILE_ON_BAT from "quiet" to "balanced"
