# Important Git Commits

## Current HEAD
```
5a8d5af (HEAD -> rseq-timeslice) Revert Gemini build fixes - return to stable configuration
```

## Critical Commits (Recent to Older)

### Stable Configuration (CURRENT)
```
5a8d5af - Revert Gemini build fixes - return to stable configuration
  Removed: 9999-gemini-build-fixes.patch
  Removed: Gemini patch integration from build script
  Reset: kernel/linux-6.18 source to clean state
  
0a04fad - Add scheduler vruntime field name fix patch and integrate into build workflow
  Added: patches/0004-fix-scheduler-vruntime-field-names.patch
  Modified: scripts/update-and-build.sh (added Step 4.8)
  Targets: 3 compilation errors in kernel/sched/fair.c
  
9f1cf6e - Update RSEQ patch with prctl integration fixes
  Modified: patches/0002-rseq-timeslice-extension.patch
  Added: prctl(PR_RSEQ_SLICE_EXTENSION_SET) support
  
69485c9 - Fix objtool build in update-and-build.sh for glibc 2.41
  Fixed: Debian glibc 2.41 compatibility issue
  
d940fcc - Add ccache support to kernel builds
  Added: ccache detection and configuration
  Enabled: Automatic caching of compiled objects
  
6321161 - Fix LLVM version auto-detection across all build scripts
  Fixed: Proper LLVM-19 detection in all scripts
```

## What Each Patch Does

### 0001-revocable-resource-management.patch
- Adds revocable resource management infrastructure
- 6 file modifications
- Base dependency for RSEQ features

### 0002-rseq-timeslice-extension.patch  
- **PRIMARY FEATURE**: RSEQ time slice extension
- 21 file modifications, 937 lines
- Adds:
  - syscall 470: sys_rseq_slice_yield
  - prctl PR_RSEQ_SLICE_EXTENSION_SET/GET
  - /proc/sys/kernel/rseq_slice_extension_nsec sysctl
  - SYSCALL_WORK_SYSCALL_RSEQ_SLICE entry work hook
  - Timer-based slice enforcement
  - Grant/deny state machine

### 0003-rseq-timeslice-debian-fixes.patch
- Fixes for Debian glibc 2.41
- 4 file modifications
- Ensures compilation compatibility

### 0004-fix-scheduler-vruntime-field-names.patch
- **CRITICAL BUILD FIX**
- 1 file modification (kernel/sched/fair.c)
- 3 targeted hunks:
  - Line 13138: se_fi_update() function
  - Line 13195: cfs_prio_less() function  
  - Line 13434: init_cfs_rq() function
- Fixes upstream kernel code using wrong field names

## Reverting Changes

### To revert to before Gemini (RECOMMENDED)
```bash
git reset --hard 0a04fad
```
This returns to the stable scheduler fix without Gemini complications.

### To revert to even earlier state
```bash
git log --oneline | head -20
git reset --hard <commit-hash>
```

### To check what changed
```bash
git diff 0a04fad 5a8d5af
git show 5a8d5af
```

## Branch Information
```
Branch: rseq-timeslice
Tracking: origin/rseq-timeslice (custom branch for RSEQ work)
Base: Linux 6.18.4 (v6.18.4 tag)
```

## How Patches Persist Across Builds

1. **Problem**: `scripts/update-and-build.sh` does `git reset --hard HEAD` when --resume not used
   - This wipes any loose source edits
   
2. **Solution**: Put all fixes in patches/ folder and apply in build script
   - Patches are applied fresh on each build
   - Changes persist through source resets
   
3. **Verification**: After build, fixes appear in source because patches were applied:
   ```bash
   cd builds/linux-6.18
   git log --oneline | grep -i "patch\|fix"
   # Shows patch commits applied to this kernel tree
   ```

## Adding New Fixes

### Proper way (persists):
1. Make change in builds/linux-6.18/
2. Commit with git: `git commit -am "Fix description"`
3. Export patch: `git format-patch -1 HEAD -o ../../patches/`
4. Add to update-and-build.sh script
5. Commit both to main repo

### Wrong way (doesn't persist):
1. Edit files in builds/linux-6.18/
2. Run build
3. Changes get wiped by next `git reset --hard`
4. Have to redo everything

## Current State Summary

✅ **All fixes properly committed to git**
✅ **All patches stored in patches/ folder**
✅ **All patches integrated into build script**
✅ **Gemini chaos reverted, clean state restored**
✅ **Ready for build**

Last successful kernel compile:
- Config backed up: `configs/.config-6.18.20260204`
- Portable installer created: `installer-6.18.8-BobZKernel-*`
