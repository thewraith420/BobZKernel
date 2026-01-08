# BobZKernel Fresh Build Guide (6.18.3)

## Critical Issue: CachyOS Patches Don't Apply to Upstream Kernel

**PROBLEM**: The CachyOS patches in this repository may become outdated as the kernel advances. When cloning a fresh upstream kernel (especially stable releases like 6.18.3), patches created for earlier versions (6.18.0, 6.18.1) will fail to apply due to code changes.

**SYMPTOM**:
- `apply-patches.sh` reports "3-way merge also failed"
- Patches are skipped with conflicts
- BORE scheduler patch fails to apply
- Build errors about "version control conflict marker in file" like `<<<<<<< ours`

## Solution: Download Fresh CachyOS Patches

### Step-by-Step Process

#### 1. Clone Fresh Kernel Source (6.18.3)

```bash
cd /home/bob/buildstuff/BobZKernel/builds
# Remove old kernel if exists
rm -rf linux-6.18

# Clone FULL kernel (not --depth=1, we need full history for patches)
git clone --branch linux-6.18.y https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-6.18
```

**Why full clone?** The patches use git's 3-way merge which requires git history blobs to resolve conflicts.

#### 2. Download Fresh CachyOS Patches

```bash
cd /home/bob/buildstuff/BobZKernel/patches

# Backup old patches
mv cachyos-6.18 cachyos-6.18-backup-$(date +%Y%m%d)

# Clone CachyOS patches repo (sparse checkout for 6.18 only)
git clone --depth=1 --filter=blob:none --sparse https://github.com/CachyOS/kernel-patches.git temp
cd temp
git sparse-checkout set 6.18

# Copy 6.18 patches to our structure
cp -r 6.18 ../cachyos-6.18
cd ..
rm -rf temp
```

#### 3. Organize Patches (CRITICAL STEP)

The CachyOS repo has this structure:
```
cachyos-6.18/
├── 0001-amd-pstate.patch
├── 0002-asus.patch
├── 0003-autofdo.patch
├── 0004-bbr3.patch
├── 0005-block.patch
├── 0006-cachy.patch
├── 0007-crypto.patch
├── 0008-fixes.patch
├── 0009-intel-pstate.patch
├── 0010-sched-ext.patch
├── 0011-t2.patch
├── all/
│   └── 0001-cachyos-base-all.patch
├── sched/
│   ├── 0001-bore-cachy.patch  ← WE NEED THIS!
│   ├── 0001-bore.patch
│   ├── 0001-prjc-cachy.patch
│   └── 0001-prjc.patch
├── sched-dev/
└── misc/
```

**CRITICAL**: The BORE scheduler patch is in the `sched/` subdirectory, not the root! Copy it to root:

```bash
cd /home/bob/buildstuff/BobZKernel/patches/cachyos-6.18
cp sched/0001-bore-cachy.patch ./0001-bore-cachy.patch
```

Verify you have these key patches:
```bash
ls -lh *.patch
```

Should see:
- `0001-bore-cachy.patch` (~36K) - BORE scheduler
- `0004-bbr3.patch` (~126K) - BBRv3 TCP congestion control
- `0006-cachy.patch` (~287K) - CachyOS optimizations

#### 4. Create Config Symlink

The `update-and-build.sh` script expects `.config-6.18` but we have `config-6.18.3-march-native`:

```bash
cd /home/bob/buildstuff/BobZKernel/configs
ln -sf config-6.18.3-march-native .config-6.18
```

#### 5. Apply Patches

```bash
cd /home/bob/buildstuff/BobZKernel

# Reset kernel to clean state first
cd builds/linux-6.18
git reset --hard v6.18.3
git clean -fd
cd ../..

# Apply patches with --force (auto-commits before applying)
./scripts/apply-patches.sh 6.18 --force
```

**Expected Result**:
- 11-12 patches applied successfully
- BORE patch may show as "skipped" in summary but actually applies
- Some whitespace warnings are OK
- NO "version control conflict markers" errors

#### 6. Verify BORE Scheduler Applied

Even if the summary says BORE was skipped, verify manually:

```bash
cd builds/linux-6.18

# Check if BORE scheduler file exists
ls -la kernel/sched/bore.c

# Check if BORE config option exists
grep -A5 "config SCHED_BORE" init/Kconfig
```

Should see:
```
config SCHED_BORE
	bool "Burst-Oriented Response Enhancer"
	default y
	help
	  In Desktop and Mobile computing, one might prefer interactive
	  tasks to keep responsive no matter what they run in the background.
```

If BORE is NOT there, manually apply it:
```bash
git apply /home/bob/buildstuff/BobZKernel/patches/cachyos-6.18/0001-bore-cachy.patch
```

#### 7. Verify All Patches

```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/verify-patches.sh 6.18
```

Should see:
```
✓ Using CONFIG_SCHED_BORE (correct)
✓ All key optimization options enabled
✓ No issues found! Patches look good.
```

#### 8. Build the Kernel

```bash
./scripts/build-kernel.sh
```

**During Config Questions**:
- You'll be asked about new kernel options
- Hit **Enter** to accept defaults for options you don't know
- The defaults are usually correct (set by the patches)
- Answer specific ones you know (like CPU type if asked)

**Build Time**: 15-30 minutes depending on CPU cores

**What to Watch For**:
- NO "version control conflict marker" errors
- Compilation progresses through many files
- Final LTO linking phase takes longest
- Log saved to `build-6.18.log`

#### 9. Verify Build Success

```bash
# Check for built kernel
ls -lh builds/linux-6.18/arch/x86/boot/bzImage

# Check kernel version
cd builds/linux-6.18
make kernelrelease
# Should show: 6.18.3-BobZKernel

# Verify optimizations in config
grep -E "CONFIG_SCHED_BORE=|CONFIG_LTO_CLANG_FULL=|CONFIG_X86_NATIVE_CPU=|CONFIG_HZ=" .config
```

Should see:
```
CONFIG_SCHED_BORE=y
CONFIG_X86_NATIVE_CPU=y
CONFIG_HZ=1000
CONFIG_LTO_CLANG_FULL=y
```

## Why This Happens

1. **Kernel updates faster than patches**: CachyOS creates patches for kernel X.Y.0, but by the time you build, kernel is at X.Y.3
2. **Code changes break patches**: Even minor stable updates change line numbers and code context
3. **Shallow clone lacks history**: `git clone --depth=1` doesn't have the git blobs needed for 3-way merge
4. **Patch structure confusion**: BORE scheduler is in `sched/` subdirectory, easy to miss

## Verification Checklist

Before building, verify:

- [ ] Full kernel clone (not shallow)
- [ ] Fresh CachyOS patches downloaded
- [ ] BORE patch copied from `sched/` to root
- [ ] `.config-6.18` symlink exists
- [ ] Patches applied (11-12 patches)
- [ ] `kernel/sched/bore.c` exists
- [ ] `verify-patches.sh` passes
- [ ] No "conflict marker" errors

## Quick Recovery

If build fails with conflict markers:

```bash
# 1. Reset kernel
cd /home/bob/buildstuff/BobZKernel/builds/linux-6.18
git reset --hard v6.18.3
git clean -fd

# 2. Resolve conflicts by accepting applied changes
git checkout --ours include/linux/tcp.h include/net/tcp.h include/uapi/linux/tcp.h net/ipv4/tcp_output.c net/ipv4/tcp_timer.c
git add .

# 3. Continue build
cd /home/bob/buildstuff/BobZKernel
./scripts/build-kernel.sh
```

## Debug Configuration

**CRITICAL**: Verify debug symbols are OFF (prevents huge module sizes):

```bash
grep "CONFIG_DEBUG_INFO" builds/linux-6.18/.config
```

Should see:
```
CONFIG_DEBUG_INFO_NONE=y
# CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT is not set
# CONFIG_DEBUG_INFO_DWARF4 is not set
# CONFIG_DEBUG_INFO_DWARF5 is not set
```

If debug is ON, disable it:
```bash
cd builds/linux-6.18
make LLVM=1 menuconfig
# Navigate to: Kernel hacking -> Compile-time checks and compiler options
# Set "Debug information" to "None"
make LLVM=1 olddefconfig
```

## Reference Documentation

- CachyOS Patches: https://github.com/CachyOS/kernel-patches
- Kernel Stable: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
- Build Logs: `/home/bob/buildstuff/BobZKernel/build-6.18.log`

## Success Indicators

Build successful when:
1. No compile errors
2. `bzImage` created (~15-25 MB)
3. All optimizations enabled (BORE, LTO, march=native, 1000Hz)
4. Modules normal size (not bloated with debug symbols)
5. `verify-patches.sh` passes

---

**Last Updated**: 2026-01-07
**Kernel Version**: 6.18.3
**CachyOS Patches**: Fresh from main branch
**Build System**: Clang/LLVM 20.1.2
