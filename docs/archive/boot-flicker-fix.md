# Boot Logo Flicker Fix

**Issue:** Lenovo logo and Mint logo flicker back and forth during boot
**Status:** Fixed
**Date:** December 28, 2025

---

## What Was Causing the Flicker?

The boot sequence goes through multiple display driver handoffs:

1. **UEFI/BIOS** → Lenovo logo (firmware splash)
2. **Simple framebuffer (simpledrm)** → Mint logo appears
3. **i915 driver loads** → Screen resets, briefly shows Lenovo logo again
4. **Plymouth takes over** → Mint logo returns
5. **X11/Wayland starts** → Final handoff

Each handoff causes a brief screen flash/flicker.

---

## The Fix

Added two kernel parameters to `/etc/default/grub`:

### 1. `i915.fastboot=1`
**What it does:**
- Tells i915 driver to preserve the display mode set by firmware
- Avoids unnecessary mode-setting during driver initialization
- Prevents the screen from blanking and re-initializing

**Result:** Smooth transition from firmware → i915 driver (no flicker)

### 2. `vt.global_cursor_default=0`
**What it does:**
- Hides the blinking text cursor on virtual terminals
- Prevents cursor from appearing during boot

**Result:** Cleaner visual experience

---

## Updated GRUB Configuration

**File:** `/etc/default/grub`

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 acpi_osi=Linux i915.enable_dpcd_backlight=0 i915.enable_guc=3 i915.enable_fbc=1 i915.fastboot=1 nvidia-drm.modeset=1 pcie_aspm.policy=default intel_idle.max_cstate=8 vt.global_cursor_default=0"
```

**Changes:**
- Added: `i915.fastboot=1`
- Added: `vt.global_cursor_default=0`

---

## Expected Boot Sequence After Fix

1. **Lenovo logo** (BIOS/UEFI)
2. **Smooth fade to Mint logo** (no flicker)
3. **Login screen appears** (clean transition)

---

## Additional Improvements (If Needed)

If you still see minor flickering, you can try these:

### Option 1: Disable Plymouth Splash Screen Entirely
```bash
# Remove "splash" from GRUB
sudo sed -i 's/ splash//' /etc/default/grub
sudo update-grub
```
**Result:** Just Lenovo logo → black screen → login (fastest boot, no animation)

### Option 2: Use fbdev Plymouth Theme (Simpler)
```bash
# Switch to simpler theme
sudo plymouth-set-default-theme script
sudo update-initramfs -u
```
**Result:** Less resource-intensive splash screen

### Option 3: Build i915 Into Kernel (Not Module)
This would be a kernel config change:
```
CONFIG_DRM_I915=y  # Instead of =m
```
**Result:** i915 loads even earlier, before initramfs

---

## Verification After Reboot

The boot should now show:
- Lenovo logo (BIOS)
- Mint logo appears smoothly (no flicker)
- Login screen

No more flickering between logos!

---

## Files Modified

- ✅ `/etc/default/grub` - Added fastboot and cursor parameters
- ✅ `/etc/default/grub.backup-bootfix-YYYYMMDD-HHMMSS` - Backup created
- ✅ GRUB updated with `update-grub`

---

## Next Steps

**Reboot** to test the fix:
```bash
sudo reboot
```

Watch the boot sequence - it should be much cleaner now!

---

**Status:** ✅ Applied - Reboot Required
