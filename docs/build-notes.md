# BobZKernel Build Notes

## Overview
Custom Linux kernel 6.14 optimized for Lenovo LOQ 15IRH8 laptop.

## Key Configuration Fixes

### 1. NVMe Boot Fix
NVMe drivers must be built INTO the kernel (not as modules) to prevent "can't find root fs" panic:
```
CONFIG_NVME_CORE=y
CONFIG_BLK_DEV_NVME=y
```

### 2. BTF Disabled
BTF debug info causes build failures - disabled to fix:
```
# CONFIG_DEBUG_INFO_BTF is not set
```

### 3. VFAT Built-in
VFAT filesystem support built-in for /boot/efi:
```
CONFIG_VFAT_FS=y
CONFIG_FAT_FS=y
```

### 4. PCIe ASPM Enabled
Power management for PCIe devices:
```
CONFIG_PCIEASPM=y
CONFIG_PCIEASPM_PERFORMANCE=y
```

### 5. Nouveau Kept as Module
Nouveau is compiled as module (for fallback) but:
- Blacklisted in /etc/modprobe.d/blacklist-nouveau.conf
- Excluded from initramfs via hook
- Can be enabled if NVIDIA driver fails

### 6. XE Driver Disabled
Intel XE driver disabled (i915 is sufficient):
```
# CONFIG_DRM_XE is not set
```

## Initramfs Optimizations

### Size Reduction: 662MB → 22MB

1. **MODULES=dep** in /etc/initramfs-tools/initramfs.conf
   - Only includes modules needed for boot hardware

2. **Module Compression**
   - All modules compressed with zstd (.ko → .ko.zst)
   - Done automatically by install script

3. **Nouveau Exclusion**
   - Hook at /usr/share/initramfs-tools/hooks/exclude-nouveau
   - Removes 237MB from initramfs

4. **Old Firmware Exclusion**
   - /etc/initramfs-tools/conf.d/exclude-old-firmware.conf

## System Configuration Files

### /etc/modprobe.d/blacklist-nouveau.conf
```
blacklist nouveau
options nouveau modeset=0
```

### /etc/initramfs-tools/initramfs.conf
```
MODULES=dep
COMPRESS=zstd
```

### /etc/initramfs-tools/modules
```
vfat
fat
```

### /etc/fstab (EFI mount)
```
UUID=F4A0-1630  /boot/efi  vfat  umask=0077,nofail,x-systemd.device-timeout=1  0  2
```
- `nofail` - Continue boot if mount fails
- `x-systemd.device-timeout=1` - Only wait 1 second

### /etc/default/grub
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 acpi_osi=Linux i915.enable_dpcd_backlight=0 nvidia-drm.modeset=1"
```

## Build Process

### Prerequisites
```bash
sudo apt-get install build-essential bc bison flex libelf-dev libssl-dev zstd
```

### Build Commands
```bash
cd /home/bob/buildstuff/BobzKernel
./scripts/build-kernel.sh 10    # Use -j10 (adjust for your RAM)
sudo ./scripts/install-kernel.sh
```

### Install Script Steps
1. Install kernel image
2. Install modules
3. Compress modules with zstd
4. Build DKMS modules (NVIDIA, etc.)
5. Regenerate initramfs
6. Update GRUB

## Hardware
- CPU: Intel Core i5-13420H (Raptor Lake, 12 cores)
- GPU: Intel UHD Graphics + NVIDIA RTX 3050 6GB
- Storage: NVMe SSD (ext4)
- RAM: 7.5GB

## Troubleshooting

### NVIDIA Module Won't Load
```bash
sudo dkms remove nvidia/580.95.05 -k $(uname -r)
sudo dkms install nvidia/580.95.05 -k $(uname -r)
sudo modprobe nvidia
```

### Need Nouveau as Fallback
```bash
sudo rm /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u -k $(uname -r)
sudo reboot
```

### Kernel Panic on Boot
Boot into generic kernel from GRUB menu, then:
```bash
# Check if NVMe is built-in
grep CONFIG_BLK_DEV_NVME /boot/config-6.14.0-BobZKernel
# Should show: CONFIG_BLK_DEV_NVME=y (not =m)
```

### Initramfs Too Large
```bash
# Regenerate with exclusions
sudo update-initramfs -u -k $(uname -r)
ls -lh /boot/initrd.img-$(uname -r)
# Should be ~20-30MB
```

## Performance Comparison

| Metric | Generic Kernel | BobZKernel |
|--------|---------------|------------|
| Initramfs Size | 79MB | 22MB |
| Boot Time | Normal | Faster |
| NVMe Support | Module | Built-in |
| ASPM | Default | Enabled |
