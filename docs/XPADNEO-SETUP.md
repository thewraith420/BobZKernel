# Xbox Controller Driver (xpadneo) Setup

## Overview

The `hid-xpadneo` driver provides advanced Xbox controller support for Linux with features like:
- Proper rumble/force feedback support
- Battery level reporting
- Trigger rumble (Xbox One S and newer)
- Button remapping support
- Low-latency mode

## Installation Status

✅ **Installed**: hid-xpadneo v0.10-pre-259-gfc1b13a
✅ **DKMS Integration**: Automatically rebuilds with each kernel update
✅ **Module Loaded**: Available for Xbox controllers

## Verifying Installation

```bash
# Check DKMS status
sudo dkms status hid-xpadneo

# Check if module is loaded
lsmod | grep xpadneo

# Load module if not loaded
sudo modprobe hid-xpadneo
```

## Automatic Rebuilding

The xpadneo driver is installed as a DKMS module. When you build and install a new BobZKernel:

1. The install script automatically detects xpadneo in `/usr/src/`
2. Rebuilds it with Clang to match the kernel compiler
3. Installs it for the new kernel version
4. Compresses with zstd

No manual intervention needed!

## Configuration

xpadneo configuration is in `/etc/modprobe.d/xpadneo.conf` (if customized).

Default settings work well for most users.

## Pairing Xbox Controller

1. Put controller in pairing mode (hold pairing button)
2. Use bluetoothctl or your desktop's Bluetooth manager
3. Controller should auto-load the xpadneo driver
4. Check with: `dmesg | grep -i xpadneo`

## Troubleshooting

**Controller not detected:**
```bash
# Check if module loaded
lsmod | grep xpadneo

# If not loaded:
sudo modprobe hid-xpadneo

# Check system log
dmesg | tail -50 | grep -i xpadneo
```

**After kernel rebuild:**
```bash
# Verify module rebuilt for new kernel
sudo dkms status hid-xpadneo

# Should show: installed for current kernel version
uname -r
```

## Credits

- **xpadneo** - [atar-axis](https://github.com/atar-axis/xpadneo) - Advanced Xbox controller driver for Linux
