# Quick Start for Continuing Work

## Current Status
- ✅ All fixes in place and committed
- ✅ Patches verified and integrated  
- ✅ ccache cleared for clean build
- ✅ Kernel source reset to known good state
- 🔄 **CURRENT**: Fresh build in progress

## Starting Fresh Build
```bash
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh --resume --yes
```

### What This Does:
1. Skips upstream update (--resume)
2. Applies all 4 patches
3. Copies config for current branch
4. Builds with LLVM-19 + ccache
5. Creates portable installer if successful

## Monitoring Build

### Check if still running:
```bash
ps aux | grep make | grep -v grep
```

### Check recent build output:
```bash
tail -50 build-6.18-*.log
```

### Check for errors:
```bash
tail -100 build-6.18-*.log | grep -i "error\|failed"
```

## If Build Fails

### 1. Check the error:
```bash
tail -200 build-6.18-*.log | grep -B 5 -A 10 "error:"
```

### 2. Verify all fixes are in place:
```bash
# BORE terminator
sed -n '376,379p' builds/linux-6.18/kernel/sched/bore.c
# Should show: }, {}, };

# RSEQ stub
sed -n '844,852p' builds/linux-6.18/kernel/rseq.c  
# Should show: SYSCALL_DEFINE0(rseq_slice_yield)

# Scheduler fixes
sed -n '13138p; 13195p; 13434p' builds/linux-6.18/kernel/sched/fair.c
# Should show: zero_vruntime (not min_vruntime)

# CONFIG enabled
grep "CONFIG_RSEQ" builds/linux-6.18/.config
# Should show both: CONFIG_RSEQ=y and CONFIG_RSEQ_SLICE_EXTENSION=y
```

### 3. Clean and retry:
```bash
rm -rf ~/.cache/ccache/*
cd /home/bob/buildstuff/BobZKernel/builds/linux-6.18
git reset --hard HEAD
cd /home/bob/buildstuff/BobZKernel
./scripts/update-and-build.sh --resume --yes
```

## After Successful Build

### Install kernel:
```bash
cd /home/bob/buildstuff/BobZKernel
# Option 1: Use installer script
sudo ./install.sh

# Option 2: Use portable installer
cd installer-6.18.8-BobZKernel*/
sudo ./install.sh
```

### Verify after reboot:
```bash
# Check kernel version
uname -r
# Should show: 6.18.9-BobZKernel+

# Check RSEQ feature
cat /proc/sys/kernel/rseq_slice_extension_nsec
# Should show sysctl value (30000 default)

# Run RSEQ tests
cd /home/bob/buildstuff/BobZKernel/tests/rseq-slice-extension
./run_all_tests.sh
```

## Key Directories

| Path | Purpose |
|------|---------|
| `patches/` | All kernel patches to apply |
| `builds/linux-6.18/` | Kernel source tree |
| `scripts/update-and-build.sh` | Main build orchestrator |
| `scripts/build-kernel.sh` | Low-level build script |
| `configs/` | Kernel config templates |
| `lib/modules/` | Built kernel modules |
| `boot/` | Kernel image files |
| `tests/rseq-slice-extension/` | RSEQ feature tests |
| `CONTEXT/` | **← This documentation** |

## Git Quick Reference

```bash
# View recent commits
git log --oneline -10

# Show what changed
git diff HEAD~1

# See current branch
git branch

# View patch files
ls -la patches/000*.patch

# Check uncommitted changes
git status
```

## Important Config Locations

- **Active build config**: `builds/linux-6.18/.config`
- **Backup configs**: `configs/config-6.18.*`
- **System optimizations**: `/etc/tlp.conf`, `/etc/modprobe.d/`

## If You Need to Revert Everything

```bash
# Back to stable commit
git reset --hard 0a04fad

# Clean kernel source
cd builds/linux-6.18
git reset --hard HEAD
git clean -fd

# Clear ccache
rm -rf ~/.cache/ccache/*
```

## Contact Info for This Context
- **Project**: BobZKernel 6.18.9 with RSEQ Slice Extension
- **Status**: Kernel operational, all features working
- **Last Update**: February 7, 2026
- **Next**: Continue development as needed

---

**See PROJECT-OVERVIEW.md for detailed technical information**
**See BUILD-TROUBLESHOOTING.md for error recovery**
**See GIT-COMMITS.md for commit history and patch details**
