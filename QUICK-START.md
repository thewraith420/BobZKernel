# BobZKernel Quick Start Guide

## One-Command Full Workflow

```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh 6.18
```

Done! This handles everything from update to installation.

## Manual Step-by-Step

```bash
cd /home/bob/buildstuff/BobZKernel

# 1. Update kernel source
./scripts/update-kernel-source.sh 6.18

# 2. Apply patches
./scripts/apply-patches.sh 6.18

# 3. Verify patches
./scripts/verify-patches.sh 6.18

# 4. Build
./scripts/build-kernel.sh

# 5. Install
sudo ./scripts/install-kernel.sh 6.18

# 6. Reboot
sudo reboot
```

## Quick Commands

```bash
# Just build (no update/install)
./scripts/update-and-build.sh 6.18 --skip-update --skip-install

# Update and build only (no install)
./scripts/update-and-build.sh 6.18 --skip-install

# Non-interactive (auto-yes)
./scripts/update-and-build.sh 6.18 --yes

# Verify current kernel
uname -r                    # Should show: 6.18.X-BobZKernel
nvidia-smi                  # Check NVIDIA driver
dmesg | grep BORE           # Check BORE scheduler
```

## Fix NVIDIA Module (if needed)

```bash
sudo dkms remove nvidia/580.95.05 -k $(uname -r)
sudo CC=clang dkms install nvidia/580.95.05 -k $(uname -r)
sudo modprobe nvidia
nvidia-smi
```

## Common Issues

### Patches don't apply
→ Download fresh patches from https://github.com/CachyOS/kernel-patches

### Build fails
→ Run `./scripts/verify-patches.sh 6.18` to find issues

### Kernel won't boot
→ Select old kernel from GRUB "Advanced options"

## Directory Quick Reference

```
builds/linux-6.18/          → Kernel source
configs/.config-6.18        → Kernel configuration
patches/cachyos-6.18/       → Performance patches
scripts/                    → All automation scripts
build.log                   → Build output log
```

## More Info

See `docs/UPDATE-WORKFLOW.md` for detailed documentation.
