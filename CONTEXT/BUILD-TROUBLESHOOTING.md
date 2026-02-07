# Build Troubleshooting Guide
**Last Updated**: February 5, 2026 - 07:15 EST

## Known Compilation Errors & Solutions

### Error 1: "no member named 'min_vruntime' in 'struct cfs_rq'"
**Cause**: Scheduler field name changed in kernel 6.18 EEVDF implementation

**Solution**: Fix #5 in fix-build-conflicts.sh
- Replaces all `cfs_rq->min_vruntime` → `cfs_rq->zero_vruntime`
- Replaces all `cfs_rq->min_vruntime_fi` → `cfs_rq->zero_vruntime_fi`
- Affects kernel/sched/fair.c (10 occurrences)

**Status**: ✅ Automated in fix-build-conflicts.sh

### Error 2: "redefinition of 'sysctl_sched_migration_cost'"
**Cause**: Unconditional definition conflicts with CONFIG_CACHY conditional block

**Solution**: Fix #4 in fix-build-conflicts.sh
- Removes standalone `__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;`
- Keeps only the CONFIG_CACHY ifdef version

**Status**: ✅ Automated in fix-build-conflicts.sh

### Error 3: "#endif without #if" in fair.c
**Cause**: Multi-line comment missing closing `*/` before preprocessor directive

**Solution**: Fix #5 ensures proper comment formatting
- Preserves comment block integrity
- Fixed by vruntime replacement sed commands

**Status**: ✅ Fixed as side effect of other fixes

### Error 4: "version control conflict marker in file" (bore.c)
**Cause**: Merge conflict markers from patch 9002 application

**Solution**: Fix #6 in fix-build-conflicts.sh
```bash
sed -i '/<<<<<<< ours/,/>>>>>>> theirs/{/<<<<<<< ours/d; /=======/d; />>>>>>> theirs/d}'
```

**Status**: ✅ Automated in fix-build-conflicts.sh

### Error 5: "duplicate 'static'" in revocable.c
**Cause**: `DEFINE_SRCU` macro already includes `static` keyword

**Solution**: Fix #7 in fix-build-conflicts.sh
```c
// BEFORE:
static DEFINE_SRCU(revocable_srcu);

// AFTER:
DEFINE_SRCU(revocable_srcu);
```

**Status**: ✅ Automated in fix-build-conflicts.sh

### Error 6: "implicit declaration of function 'hrtimer_init'"
**Cause**: Kernel 6.18 API changed to `hrtimer_setup()`

**Solution**: Fix #8 in fix-build-conflicts.sh
```c
// BEFORE:
hrtimer_init(&st->timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);
st->timer.function = rseq_slice_expired;

// AFTER:
hrtimer_setup(&st->timer, rseq_slice_expired, CLOCK_MONOTONIC, HRTIMER_MODE_REL_PINNED_HARD);
```

**Status**: ✅ Automated in fix-build-conflicts.sh

### Error 7: RSEQ sysctl not appearing in /proc/sys/kernel/
**Cause**: Kernel 6.18 requires `register_sysctl_init()` instead of `register_sysctl()`

**Solution**: Fix #9 in fix-build-conflicts.sh
```c
// BEFORE:
register_sysctl("kernel", rseq_slice_ext_sysctl);

// AFTER:
register_sysctl_init("kernel", rseq_slice_ext_sysctl);
```

**Impact**: Sysctl won't appear until kernel rebuilt with this fix
**Status**: ✅ Fix applied to source, needs rebuild

### Error 8: "ld.lld-19: error: undefined symbol: __x64_sys_rseq_slice_yield"
**Cause**: RSEQ syscall in syscall table but stub not compiled when CONFIG_RSEQ_SLICE_EXTENSION disabled

**Solution**: Stub already in patch 9002 (RSEQ slice extension)
```c
#else /* !CONFIG_RSEQ_SLICE_EXTENSION */
SYSCALL_DEFINE0(rseq_slice_yield)
{
    return 0;
}
#endif
```

**Status**: ✅ Included in patch 9002

### Error 9: Merge conflict markers in multiple files
**Cause**: Patch 9002 (RSEQ) conflicts with existing code

**Affected Files**:
- init/Kconfig
- include/linux/thread_info.h
- kernel/rseq.c

**Solution**: Fixes #1, #2, #3 in fix-build-conflicts.sh
- Automatically removes all `<<<<<<< ours`, `=======`, `>>>>>>> theirs` markers
- Keeps appropriate code sections

**Status**: ✅ Automated in fix-build-conflicts.sh

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
