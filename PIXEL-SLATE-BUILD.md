# Pixel Slate Kernel Build

## Overview

The `pixel-slate` branch contains BobZKernel optimized for Google Pixel Slate (Nocturne). This branch is based on the generic-build but includes specific drivers and configurations for Pixel Slate hardware.

## Key Hardware-Specific Changes

### Camera System (Critical)
The Pixel Slate has dual IMX cameras managed by Intel Skylake INT3472 power management and an IPU3 processor. These configurations MUST be built-in (=y) not as modules (=m) to ensure proper initialization order:

```
CONFIG_INTEL_SKL_INT3472=y          # Camera power management
CONFIG_REGULATOR_TPS68470=y         # Voltage regulator for cameras  
CONFIG_COMMON_CLK_TPS68470=y        # Clock provider for regulators
CONFIG_VIDEO_IPU3_CIO2=y            # IPU3 CIO2 interface
CONFIG_IPU_BRIDGE=y                 # Bridge between ISP and sensors
CONFIG_VIDEO_IMX355=y               # Rear camera sensor
CONFIG_VIDEO_IMX319=y               # Front camera sensor
CONFIG_V4L2_FWNODE=y                # Device tree support for V4L2
CONFIG_V4L2_ASYNC=y                 # Asynchronous probing
```

**Why built-in?** ACPI initialization must happen after these drivers are loaded to properly wire up power management. Loading as modules after ACPI finalizes breaks camera power control.

### Audio System
The Pixel Slate uses Intel High Definition Audio (HDA) with specific codec support. Audio drivers are kept as modules (=m) for flexibility:

```
CONFIG_SND_HDA=m                    # HDA core
CONFIG_SND_HDA_INTEL=m              # Intel HDA controller
CONFIG_SND_HDA_GENERIC=m            # Generic HDA codec
CONFIG_SND_HDA_CODEC_HDMI=m         # HDMI audio support
CONFIG_SND_HDA_POWER_SAVE_DEFAULT=15 # Power saving
```

### Display/GPU
- Intel integrated graphics (i915)
- HDMI support

## Building for Pixel Slate

```bash
# Switch to pixel-slate branch
git checkout pixel-slate

# Build
./scripts/update-and-build.sh --skip-install

# Install to Pixel Slate
sudo ./scripts/install-kernel.sh 6.18
```

## Differences from Generic Build

| Component | Generic | Pixel Slate |
|-----------|---------|------------|
| Camera drivers | Modules (=m) | Built-in (=y) |
| IPU3 drivers | Modules (=m) | Built-in (=y) |
| Audio | Standard HDA | HDA optimized |
| Target | Any x86-64 | Pixel Slate only |
| Version | 6.18.6-BobZKernel-generic | 6.18.6-BobZKernel-pixel-slate |

## Troubleshooting

### Cameras not working
- Check kernel logs: `dmesg | grep -i camera`
- Verify drivers loaded: `lsmod | grep -E 'ipu3|imx|int3472'`
- These MUST be built-in, not modules

### Audio issues
- Check: `cat /proc/asound/cards`
- Reload: `sudo modprobe -r snd_hda_intel && sudo modprobe snd_hda_intel`

### Power management
- Camera power manager: `dmesg | grep -i tps68470`
- Monitor: `grep CONFIG_REGULATOR_TPS68470 /boot/config-$(uname -r)`

## Version History

- **6.18.6-BobZKernel-pixel-slate+** - Updated to 6.18.6 with generic-build as base
- **6.18.4-BobZKernel-pixel-slate** - Previous version on 6.18.4

