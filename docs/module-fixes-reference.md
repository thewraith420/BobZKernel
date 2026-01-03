# Module Fixes Reference for 6.18 BORE Kernel

This document summarizes all module compatibility fixes required for the 6.18 BORE kernel built with Clang/LTO_FULL.

## Automated Fixes (via scripts)

### 1. NVIDIA Driver (580.95.05)
**Issue:** `get_dev_pagemap()` API changed in kernel 6.18  
**Location:** `/usr/src/nvidia-580.95.05/nvidia-uvm/uvm_va_range_device_p2p.c`  
**Fix:** Remove second NULL parameter  
```c
// Old (fails on 6.18+)
get_dev_pagemap(page_to_pfn(page), NULL)

// New (6.18+ compatible)
get_dev_pagemap(page_to_pfn(page))
```
**Script:** `scripts/patch-dkms-sources.sh`

### 2. xpadneo (Xbox Controller Driver)
**Issue:** `ida_simple_get/remove()` deprecated since kernel 6.0  
**Location:** `/usr/src/hid-xpadneo-*/src/hid-xpadneo.c`  
**Fix:** Replace with `ida_alloc/ida_free()` and add `<linux/idr.h>` header  
```c
// Old API
ida_simple_get(&xpadneo_device_id_allocator, 0, 0, GFP_KERNEL)
ida_simple_remove(&xpadneo_device_id_allocator, xdata->id)

// New API
ida_alloc(&xpadneo_device_id_allocator, GFP_KERNEL)
ida_free(&xpadneo_device_id_allocator, xdata->id)
```
**Script:** `scripts/patch-dkms-sources.sh`

### 3. VMware Modules (vmmon, vmnet)
**Issue:** Clang strict-prototypes enforcement requires explicit void parameters  
**Locations:**
- `vmmon-only/driver.c`
- `vmnet-only/driver.c`
- `vmnet-only/smac_compat.c`

**Fix:** Add `void` parameter to empty function declarations  
```c
// Old (fails with Clang -Werror=strict-prototypes)
VNetFreeInterfaceList()
SMACL_GetUptime()

// New (Clang compatible)
VNetFreeInterfaceList(void)
SMACL_GetUptime(void)
```
**Script:** `scripts/build-vmware-modules.sh`  
**Build:** Must use kernel kbuild with `LLVM=1 CC=clang LD=ld.lld` to match kernel compiler

## Build Order

The installation script (`scripts/install-kernel.sh`) handles everything automatically:

1. **Install kernel & modules** - Core kernel installation
2. **Compress modules** - zstd compression to reduce initramfs size
3. **Patch DKMS sources** - Apply compatibility fixes via `patch-dkms-sources.sh`
4. **DKMS autoinstall** - Rebuild NVIDIA, xpadneo, LenovoLegionLinux
5. **Build VMware modules** - Compile vmmon/vmnet with Clang via `build-vmware-modules.sh`
6. **Generate initramfs** - Create initrd with all modules
7. **Update GRUB** - Make new kernel bootable

## Module Status

| Module | Status | Location |
|--------|--------|----------|
| nvidia | ✅ Working | `/lib/modules/6.18.0-BobZKernel-6.18/updates/dkms/` |
| xpadneo | ✅ Working | `/lib/modules/6.18.0-BobZKernel-6.18/updates/dkms/` |
| LenovoLegionLinux | ✅ Working | `/lib/modules/6.18.0-BobZKernel-6.18/updates/dkms/` |
| vmmon | ✅ Working | `/lib/modules/6.18.0-BobZKernel-6.18/misc/` |
| vmnet | ✅ Working | `/lib/modules/6.18.0-BobZKernel-6.18/misc/` |

## Verification Commands

```bash
# Check all modules load
lsmod | grep nvidia
lsmod | grep xpadneo
lsmod | grep legion
lsmod | grep vmmon
lsmod | grep vmnet

# Check module info
modinfo nvidia
modinfo hid-xpadneo
modinfo vmmon

# Verify kernel compiler
cat /proc/version
# Should show: clang version 18.1.3

# Check VMware functionality
systemctl status vmware
```

## Troubleshooting

### If NVIDIA fails to load
```bash
sudo dkms remove nvidia/580.95.05 --all
sudo dkms install nvidia/580.95.05 -k $(uname -r)
sudo modprobe nvidia
```

### If VMware modules fail to load
```bash
cd /tmp && sudo /home/bob/buildstuff/BobzKernel/scripts/build-vmware-modules.sh $(uname -r)
sudo modprobe vmmon vmnet
```

### Check build logs
```bash
# DKMS build logs
sudo dkms status
cat /var/lib/dkms/nvidia/580.95.05/build/make.log

# Kernel build log
cat /home/bob/buildstuff/BobzKernel/builds/linux/build.log
```

## Notes

- All DKMS modules are rebuilt with Clang to match the kernel compiler
- VMware modules use kernel kbuild (not standalone Makefile) to ensure compiler flags match
- Module compression uses zstd for faster boot and smaller initramfs
- Module signatures use SHA512 for enhanced security
