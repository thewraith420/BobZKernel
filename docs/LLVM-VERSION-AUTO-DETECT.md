# LLVM Version Auto-Detection Fix

## Problem
When moving the kernel build environment from Linux Mint (with Clang 20) to Debian 13 (with Clang 19), all build scripts had hardcoded `LLVM=-20` references that caused build failures with "clang-20: not found" errors.

## Root Cause
1. Config files from Linux Mint contained `CONFIG_CC_VERSION_TEXT="Ubuntu clang version 20.1.2"`
2. All scripts hardcoded `LLVM=-20` flag for make commands
3. `make olddefconfig` would fail before build-kernel.sh was even called

## Solution
Added LLVM version auto-detection to all scripts that invoke make:

```bash
# Auto-detect LLVM version
if command -v clang-19 &> /dev/null; then
    LLVM_VERSION="-19"
elif command -v clang-20 &> /dev/null; then
    LLVM_VERSION="-20"
elif command -v clang-18 &> /dev/null; then
    LLVM_VERSION="-18"
else
    LLVM_VERSION=""  # Use system default clang
fi
```

## Files Modified
- `scripts/build-kernel.sh` - Auto-detect LLVM version for kernel compilation
- `scripts/update-and-build.sh` - Auto-detect LLVM version for make olddefconfig and build
- `scripts/install-kernel.sh` - Auto-detect LLVM version for make install/modules_install
- `scripts/build-vmware-modules.sh` - Auto-detect LLVM version for VMware module builds

## Testing
After these changes, the build scripts will automatically work on any system with Clang 18, 19, or 20, or fallback to the system default clang if available.

## Date
2026-02-03
