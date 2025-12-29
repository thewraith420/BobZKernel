# GRUB Power Management Configuration

## Current GRUB Parameters
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 acpi_osi=Linux i915.enable_dpcd_backlight=0 nvidia-drm.modeset=1"
```

## Recommended Power Optimizations to Add

### 1. PCIe ASPM (Active State Power Management)
**Purpose:** Enable aggressive PCIe power saving
**Parameters:**
- `pcie_aspm=force` - Force ASPM even if BIOS doesn't enable it
- `pcie_aspm.policy=powersupersave` - Most aggressive power saving

**Power Savings:** 1-2W on battery

### 2. Intel CPU Power Management
**Purpose:** Better CPU idle states and frequency scaling
**Parameters:**
- `intel_pstate=active` - Use Intel P-state driver (default, confirm it's active)
- `intel_idle.max_cstate=8` - Allow deepest C-states for better battery

**Power Savings:** 0.5-1.5W in idle

### 3. Intel GPU Power Management
**Purpose:** Better integrated GPU power efficiency
**Parameters:**
- `i915.enable_guc=3` - Enable GuC submission and HuC firmware loading
- `i915.enable_fbc=1` - Enable framebuffer compression (reduce memory bandwidth)
- `i915.fastboot=1` - Skip some initialization (faster boot, less power)

**Already have:** `i915.enable_dpcd_backlight=0` (good, prevents backlight issues)

### 4. NVIDIA Runtime PM (Optional)
**Purpose:** Allow NVIDIA GPU to power down when not in use
**Parameters:**
- `nvidia-drm.modeset=1` - Already set ✓
- `nvidia.NVreg_DynamicPowerManagement=2` - Enable dynamic power management

**Power Savings:** Significant on battery when GPU idle (can disable GPU completely)

## Proposed New Configuration

**Conservative (Recommended):**
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 nvidia-drm.modeset=1 pcie_aspm.policy=default intel_idle.max_cstate=8"
```

**Aggressive (Maximum Battery Life):**
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 i915.fastboot=1 nvidia-drm.modeset=1 nvidia.NVreg_DynamicPowerManagement=2 pcie_aspm=force pcie_aspm.policy=powersupersave intel_idle.max_cstate=8"
```

## Parameter Breakdown

| Parameter | Effect | Risk | Power Savings |
|-----------|--------|------|---------------|
| `pcie_aspm=force` | Force PCIe ASPM | Low-Medium | 1-2W |
| `pcie_aspm.policy=powersupersave` | Aggressive PCIe PM | Low | 1-2W |
| `intel_idle.max_cstate=8` | Deep CPU sleep | Very Low | 0.5-1.5W |
| `i915.enable_guc=3` | Intel GPU GuC/HuC | Low | 0.3-0.7W |
| `i915.enable_fbc=1` | Framebuffer compression | Very Low | 0.1-0.3W |
| `i915.fastboot=1` | Fast boot, less init | Very Low | Boot time only |
| `nvidia.NVreg_DynamicPowerManagement=2` | NVIDIA runtime PM | Medium | 5-15W when idle |

## Recommendation

Start with **Conservative** profile, test for stability. If stable after a few days, can try **Aggressive** for maximum battery life.

TLP will work alongside these parameters - TLP controls CPU governor and other runtime settings, while these boot parameters set hardware capabilities.

## How to Apply

1. Edit /etc/default/grub
2. Update GRUB_CMDLINE_LINUX_DEFAULT line
3. Run: `sudo update-grub`
4. Reboot

## Script to Apply Conservative Profile

```bash
#!/bin/bash
# Backup current grub config
sudo cp /etc/default/grub /etc/default/grub.backup-$(date +%Y%m%d-%H%M%S)

# Update GRUB_CMDLINE_LINUX_DEFAULT
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 nvidia-drm.modeset=1 pcie_aspm.policy=default intel_idle.max_cstate=8"|' /etc/default/grub

# Update grub
sudo update-grub

echo "GRUB updated with conservative power settings"
echo "Reboot to apply changes"
```
