# Power/Performance Optimization Plan for Lenovo LOQ 15IRH8

## Hardware
- CPU: Intel Core i5-13420H (Raptor Lake, 12 cores)
- GPU: Intel UHD Graphics (integrated) + NVIDIA RTX 3050 6GB (discrete)
- Storage: NVMe SSD
- Current Kernel: 6.14.0-BobZKernel

## Goal
- Maximum battery life on battery power
- Maximum gaming performance on AC power
- Seamless integration with TLP

## Optimization Steps

### 1. Kernel Configuration Changes

#### A. Enable PCIe ASPM (Active State Power Management)
**Impact:** 1-2W power savings on battery
```
CONFIG_PCIEASPM=y
CONFIG_PCIEASPM_DEFAULT=y
CONFIG_PCIEASPM_POWERSAVE=y
CONFIG_PCIEASPM_POWER_SUPERSAVE=y
CONFIG_PCIEASPM_PERFORMANCE=y
```

#### B. Enable Runtime PM
**Impact:** Automatic device power management
```
CONFIG_PM_RUNTIME=y (should already be enabled)
```

#### C. CPU Frequency Scaling
**Impact:** Better P-state control
```
CONFIG_X86_INTEL_PSTATE=y (already enabled)
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y (already enabled)
```

### 2. Kernel Boot Parameters

Add to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub:

```
pcie_aspm=force
pcie_aspm.policy=powersupersave
```

### 3. TLP Configuration Enhancements

#### GPU Power Management
```
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto

# NVIDIA GPU runtime PM
RUNTIME_PM_DRIVER_DENYLIST="nouveau"  # We use proprietary nvidia
```

#### PCIe Runtime PM
```
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave
```

### 4. NVIDIA Power Management

Enable NVIDIA runtime PM for better battery life when GPU is idle:
- Create udev rules for NVIDIA PM
- Configure nvidia-powerd service

### 5. Expected Results

**On Battery:**
- PCIe ASPM powersupersave mode
- CPU powersave governor
- NVIDIA GPU suspended when not in use
- Intel GPU active for desktop
- Estimated: 1.5-3W power savings

**On AC:**
- PCIe ASPM default/performance mode
- CPU performance governor
- Full GPU performance available
- No power limits

### 6. Testing Plan

1. Build kernel with new config
2. Update boot parameters
3. Update TLP config
4. Test battery life (idle, light use)
5. Test gaming performance (AC power)
6. Monitor with `powertop` and `tlp-stat`

## Implementation Order

1. Update kernel config (add ASPM)
2. Rebuild kernel
3. Update GRUB boot parameters
4. Update TLP configuration
5. Test and validate
