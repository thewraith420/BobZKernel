# BobZKernel Documentation

**Last Updated:** February 22, 2026
**Kernel Version:** Linux 6.19.3-BobZKernel+
**Status:** Production - RSEQ slice extension fully functional

## Documentation Structure

### Core Documentation

**📋 [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md)** - START HERE
- Current kernel status and version
- Project goals and hardware specs
- Key features (RSEQ, BORE, CachyOS patches)
- Build workflow and commands
- DKMS module management
- Quick reference commands

### Technical Deep-Dives

**🔍 [RSEQ-INVESTIGATION-COMPLETE.md](RSEQ-INVESTIGATION-COMPLETE.md)**
- Complete RSEQ slice extension investigation and resolution
- Four bugs discovered and fixed
- Performance metrics (91% yield rate achieved)
- Timeline from problem to solution
- Technical details of the fixes

**🐛 [DEBUG-PRINTK-LOCATIONS.md](DEBUG-PRINTK-LOCATIONS.md)**
- Debug instrumentation reference
- Locations of all debug printk statements
- How to re-add debugging if needed
- Output interpretation guide

**🔧 [BUILD-TROUBLESHOOTING.md](BUILD-TROUBLESHOOTING.md)**
- Common compilation errors and solutions
- DKMS module build issues
- Compiler and build system problems
- Generic troubleshooting guidance

## Quick Navigation

### I want to...

**...understand what this project is:**
→ Read [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md)

**...build the kernel:**
→ See "Build Workflow" section in [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md)
→ Run: `./scripts/update-and-build.sh`

**...understand how RSEQ works:**
→ Read [RSEQ-INVESTIGATION-COMPLETE.md](RSEQ-INVESTIGATION-COMPLETE.md)
→ See "Technical Details" and "RSEQ Lifecycle" sections

**...troubleshoot build errors:**
→ Check [BUILD-TROUBLESHOOTING.md](BUILD-TROUBLESHOOTING.md)
→ Check [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md) "Known Issues & Solutions"

**...add debug tracing:**
→ See [DEBUG-PRINTK-LOCATIONS.md](DEBUG-PRINTK-LOCATIONS.md)

**...check RSEQ performance:**
```bash
sudo cat /sys/kernel/debug/rseq/stats
```

**...rebuild DKMS modules:**
```bash
sudo dkms install nvidia/590.48.01 -k $(uname -r)
sudo dkms install hid-xpadneo/v0.10-pre-259-gfc1b13a -k $(uname -r)
```

## File Summary

| File | Purpose | When to Read |
|------|---------|--------------|
| README.md (this file) | Navigation and overview | First time, finding docs |
| PROJECT-OVERVIEW.md | Main project documentation | Setup, building, daily use |
| RSEQ-INVESTIGATION-COMPLETE.md | RSEQ deep technical details | Understanding RSEQ, debugging |
| DEBUG-PRINTK-LOCATIONS.md | Debug instrumentation reference | Adding debugging, troubleshooting |
| BUILD-TROUBLESHOOTING.md | Build error solutions | When builds fail |

## Key Achievements

✅ **RSEQ Slice Extension:** Fully functional with 91% yield rate
✅ **System-wide Gaming Support:** ProtonGE-RSEQ integration working
✅ **179 Threads Engaged:** Per-thread RSEQ initialization successful
✅ **Optimal Tuning:** 30µs slice duration provides best performance
✅ **Clean LLVM Builds:** Kernel compiles with Clang/LLVM 19
✅ **DKMS Integration:** All drivers rebuild automatically

## External Projects

**ProtonGE-RSEQ:**
- Location: `/home/bob/buildstuff/proton-ge-rseq/`
- Purpose: Wine/Proton with RSEQ support for gaming
- Status: Working perfectly

**PipeWire-RSEQ:**
- Location: `/home/bob/buildstuff/pipewire-rseq/`
- Purpose: System-wide audio improvements via RSEQ
- Status: Planning phase, documentation complete

## Important Locations

**Kernel Source:**
```
/home/bob/buildstuff/BobZKernel/builds/linux-6.19/
```

**Patches:**
```
/home/bob/buildstuff/BobZKernel/patches/cachyos-6.19/9002-rseq-slice-extension.patch
```

**Build Scripts:**
```
/home/bob/buildstuff/BobZKernel/scripts/update-and-build.sh
```

**RSEQ Stats:**
```
/sys/kernel/debug/rseq/stats
```

**RSEQ Configuration:**
```
/proc/sys/kernel/rseq_slice_extension_nsec
```

## Version History

**6.19.3-BobZKernel+ (Current):**
- RSEQ slice extension fully working
- BORE scheduler integrated
- CachyOS patches applied
- LLVM 19 compilation
- NVIDIA 590.48.01 support

**6.19.0-BobZKernel-dirty:**
- Initial 6.19 port
- RSEQ not fully functional (pre-fix)

**6.18.9-BobZKernel+:**
- Previous stable release
- RSEQ debugging phase
- Sysctl issues resolved

## Git Repository

**Branch:** linux-6.19
**Remote:** origin (local)
**Upstream:** Linux stable kernel

**Common commands:**
```bash
git status
git log --oneline -10
git diff
```

## Support & Resources

**Kernel Documentation:**
- RSEQ: `Documentation/rseq.txt` in kernel source
- Build: `Documentation/kbuild/` in kernel source

**External Resources:**
- Linux kernel: https://kernel.org
- CachyOS: https://github.com/CachyOS/linux-cachyos
- BORE scheduler: https://github.com/firelzrd/bore-scheduler

## Maintenance

**Regular tasks:**
- Monitor kernel.org for security updates
- Check RSEQ stats during gaming sessions
- Rebuild DKMS modules after kernel updates
- Backup working configs before major changes

**Before upgrading kernel:**
1. Backup current config: `cp .config ~/config-backup-$(date +%Y%m%d)`
2. Document current working state
3. Test new kernel in non-production environment
4. Keep old kernel as fallback in GRUB

## Contact

This is a personal custom kernel project for:
- **System:** Lenovo LOQ 15IRH8
- **User:** bob
- **Use Case:** Gaming (ESO) and general desktop use

---

**For new session starting point:** Read [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md) first!
