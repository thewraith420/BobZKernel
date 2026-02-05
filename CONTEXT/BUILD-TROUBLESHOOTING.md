# Build Troubleshooting Guide

## Known Compilation Errors & Solutions

### Error 1: "no member named 'min_vruntime_fi' in 'struct cfs_rq'"
**Cause**: Scheduler field name mismatch in upstream kernel code vs. local struct definition

**Solution**: Apply patch 0004-fix-scheduler-vruntime-field-names.patch
- Replaces all `min_vruntime` → `zero_vruntime`
- Replaces all `min_vruntime_fi` → `zero_vruntime_fi`
- Affects lines 13138, 13195, 13434 in kernel/sched/fair.c

**Verification**:
```bash
cd builds/linux-6.18
sed -n '13138p; 13195p; 13434p' kernel/sched/fair.c
# Should show zero_vruntime references, not min_vruntime
```

### Error 2: "sysctl table check failed: kernel/(null) procname is null"
**Cause**: BORE scheduler sysctl array missing null terminator

**Solution**: In kernel/sched/bore.c, ensure line 378 has `{}`
```c
},
{}  // <-- This terminator was missing
};
```

**Verification**:
```bash
sed -n '376,379p' builds/linux-6.18/kernel/sched/bore.c
```

### Error 3: "ld.lld-19: error: undefined symbol: __x64_sys_rseq_slice_yield"
**Cause**: RSEQ syscall in table but stub not compiled when CONFIG_RSEQ_SLICE_EXTENSION disabled

**Solution**: Add stub syscall in kernel/rseq.c
```c
#else /* !CONFIG_RSEQ_SLICE_EXTENSION */
SYSCALL_DEFINE0(rseq_slice_yield)
{
    return 0;
}
#endif
```

**Verification**:
```bash
sed -n '844,852p' builds/linux-6.18/kernel/rseq.c
```

## Build Failure Recovery

### If build fails:
1. **Check log**: `tail -200 build-6.18-*.log | grep -A 10 "error:"`
2. **Clean cache**: `rm -rf ~/.cache/ccache/*`
3. **Reset source**: `cd builds/linux-6.18 && git reset --hard HEAD`
4. **Resume**: `./scripts/update-and-build.sh --resume --yes`

### If patches don't apply:
1. Check kernel source is at correct commit: `git log --oneline | head -5`
2. Verify patches exist: `ls -la patches/000*.patch`
3. Try manual patch: `cd builds/linux-6.18 && git apply -v ../../patches/00XX-*.patch`

### If config issues occur:
1. Verify CONFIG_RSEQ_SLICE_EXTENSION=y in .config
2. Re-run olddefconfig: `make LLVM=-19 HOSTCC=gcc HOSTCXX=g++ olddefconfig`
3. Check for new config options not set

## Common Pitfalls

### ❌ Gemini patches made things worse
- Tried to apply broad fixes that conflicted with targeted patches
- Created duplicate definitions and merge conflicts
- **SOLUTION**: Reverted entirely, returned to minimal targeted fixes

### ❌ ccache stale objects
- Old object files from previous builds with wrong code
- **SOLUTION**: Clear with `rm -rf ~/.cache/ccache/*` before important builds

### ❌ Build script cleans source without saving changes
- `git reset --hard HEAD` wipes local modifications
- **SOLUTION**: Always put fixes in patches or git commits, not loose source edits

### ❌ CONFIG changes mid-build
- Compiler still using old .o files from previous config
- **SOLUTION**: Delete affected .o files or do full clean rebuild

## Patch Management

### Creating a new patch:
1. Make changes in builds/linux-6.18/
2. Generate diff: `git diff kernel/sched/fair.c > new.patch`
3. Move to patches/ folder
4. Add to update-and-build.sh script
5. Commit everything to git

### Testing a patch without building:
```bash
cd builds/linux-6.18
git apply --check ../../patches/test.patch
```

### Updating existing patches:
1. Edit in builds/linux-6.18/
2. Commit changes with git
3. Export: `git format-patch -1 HEAD`
4. Replace patch file
5. Commit to git

## Performance Notes

- **Full build**: ~2-3 hours on i5-13420H (first time)
- **Incremental with ccache**: ~30-45 minutes (if minimal changes)
- **With LTO Clang Full**: Adds ~20-30% to compile time but better optimization
- **march=native**: Improves runtime performance, adds ~5% to compile time

## Debug Tips

### View current build progress:
```bash
ps aux | grep make | grep -v grep | wc -l
# If > 10 processes, build is active
```

### Check build log in real-time:
```bash
tail -f build-6.18-*.log | grep "^  CC\|^  LD\|error:"
```

### Verify patches applied to source:
```bash
cd builds/linux-6.18
git log --oneline | head -15
# Should show patch commits
```

### Check specific file for fix:
```bash
grep -n "zero_vruntime_fi" kernel/sched/fair.c | wc -l
# Should return > 0 if patch applied
```
