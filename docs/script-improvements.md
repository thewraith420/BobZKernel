# Build Scripts Improvements - Version Switching

## What Was Fixed

### 1. **apply-patches.sh** - Intelligent Patch Management
**Before:** Failed immediately on uncommitted changes or patch conflicts
**After:**
- `--continue-on-failure` flag to skip optional patches with conflicts
- `--force` flag to auto-commit uncommitted changes before patching
- Uses [patch-config.sh](../patches/patch-config.sh) to define which patches are required vs optional per version
- Graceful degradation: continues build even if optional patches fail
- Clear summary showing which patches succeeded/skipped/failed

### 2. **patch-config.sh** - Per-Version Patch Configuration
**New file** that defines:
- Which patches to apply for each kernel version
- Patch priority: `required`, `optional`, or `skip`
- 6.14 configuration skips BORE (known conflicts)
- 6.18 configuration includes full CachyOS suite

### 3. **apply-march-native.sh** - Automated CPU Optimization
**New file** that:
- Applies `-march=native -mtune=native` to kernel Makefile
- Creates backup of original Makefile
- Auto-commits the change to git
- Can be run standalone or as part of workflow
- Shows which CPU features will be used (e.g., Alderlake)

### 4. **build-kernel.sh** - Multi-Version Support
**Before:** Hardcoded for 6.18
**After:**
- Accepts version parameter: `./build-kernel.sh 6.14`
- Automatically selects correct kernel directory
- Automatically selects correct config file
- Falls back to 6.18 if version not specified

### 5. **update-and-build.sh** - Complete Automated Workflow
**Improvements:**
- Now 7 steps instead of 6 (added march=native step)
- Passes kernel version to all sub-scripts
- Uses `--continue-on-failure --force` for patch application
- Continues build even if optional patches fail
- More robust error handling

## New Workflow

### Quick Build (6.14 or 6.18)
```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh 6.14 --skip-update --skip-install --yes
```

### What Happens Automatically:
1. **Clean** - `make mrproper`
2. **Optimize** - Apply march=native (with auto-commit)
3. **Patch** - Apply CachyOS patches (skips conflicts gracefully)
4. **Verify** - Check for patch issues
5. **Configure** - Apply `.config-6.14` or `.config-6.18`
6. **Build** - Compile kernel with LLVM/Clang + LTO
7. **Install** - (optional) Install kernel and modules

### Switching Between Versions
Super smooth now! Just change the version number:
```bash
# Build 6.14
./scripts/update-and-build.sh 6.14 --skip-update --skip-install --yes

# Build 6.18  
./scripts/update-and-build.sh 6.18 --skip-update --skip-install --yes
```

## Patch Configuration System

### patches/patch-config.sh
```bash
# 6.14 patch configuration
PATCHES_6_14=(
    "0004-bbr3.patch:required"       # BBRv3 (required)
    "0005-cachy.patch:optional"      # CachyOS base (may have conflicts)
    "0009-zstd.patch:optional"       # ZSTD compression
)

# 6.18 patch configuration
PATCHES_6_18=(
    "0001-bore-cachy.patch:required"  # BORE scheduler
    "0004-bbr3.patch:required"        # BBRv3
    "0006-cachy.patch:required"       # CachyOS base
    # ... more patches
)
```

### Patch Priorities
- **required** - Build fails if patch fails (critical patches)
- **optional** - Skipped if conflicts detected (nice-to-have)
- **skip** - Explicitly skip this patch for this version

## Error Handling

### Before
- Script exits on first patch failure
- Manual intervention required for uncommitted changes
- No distinction between critical and optional patches

### After
- Continues through patch failures (with `--continue-on-failure`)
- Auto-commits uncommitted changes (with `--force`)
- Only fails on required patches
- Clear summary of what succeeded vs skipped

## Benefits

1. **Zero manual intervention** - Fully automated from clean to build
2. **Version switching** - One command to switch between 6.14 and 6.18
3. **Fault tolerant** - Continues build even with patch conflicts
4. **Patch management** - Easy to enable/disable patches per version
5. **march=native** - Automatically applied and committed
6. **Clear feedback** - Knows exactly what succeeded and what didn't

## Example Output

```
═══ Step 3/7: Applying CachyOS Patches ═══
Kernel: 6.14
Patches configured: 3

Applying: 0004-bbr3.patch [required]
✓ Applied with 3-way merge

Applying: 0005-cachy.patch [optional]
⊘ Skipping optional patch (conflicts)

Applying: 0009-zstd.patch [optional]
✓ Applied cleanly

=== Patch Application Summary ===
Successfully applied: 2 patches
Skipped patches: 1
  ⊘ 0005-cachy.patch (conflicts)
✓ Patch application complete!
```

## Files Modified

- [scripts/apply-patches.sh](../scripts/apply-patches.sh)
- [scripts/build-kernel.sh](../scripts/build-kernel.sh)
- [scripts/update-and-build.sh](../scripts/update-and-build.sh)

## Files Created

- [scripts/apply-march-native.sh](../scripts/apply-march-native.sh)
- [patches/patch-config.sh](../patches/patch-config.sh)

## Testing

All improvements tested with 6.14 build:
- ✅ march=native applied automatically
- ✅ BBRv3 patch applied with 3-way merge
- ✅ ZSTD patch applied cleanly
- ✅ CachyOS cachy patch skipped gracefully (expected conflicts)
- ✅ Build proceeded without manual intervention
