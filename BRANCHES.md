# BobZKernel Branch Strategy

## Active Branches

### `stable` (Default)
**Purpose:** Current production kernel, fully tested and running

**Current Build:** Linux 6.14.0-BobZKernel  
**Optimizations:** LTO Full, march=native, BORE scheduler, BBRv3, CachyOS patches  
**Status:** ✅ Active, kernel booting and functional

**Changes to make only via pull request from `dev` branch**

---

### `dev`
**Purpose:** Integration branch for experimental features and optimizations

**Used for:**
- Testing new kernel configurations
- Performance tuning experiments
- Module/initramfs optimization
- Pre-release testing before merge to `stable`

**Testing workflow:**
1. Create feature branch off `dev`
2. Test thoroughly on hardware
3. Submit PR to merge into `stable`

---

## Feature Branches

### `feature/6.18-lts`
**Purpose:** Upgrade to Linux 6.18 LTS kernel

**Goals:**
- Migrate from 6.14 to 6.18 (longer support: Dec 2027 vs shorter 6.14 lifecycle)
- Apply latest CachyOS patches for 6.18
- Maintain all current optimizations (BORE, BBRv3, LTO Full, march=native)
- Benchmark and validate performance

**Target merge:** After successful testing, merge to `dev` then `stable`

**Related docs:**
- [6.18 Build Plan](docs/6.18-build-plan.md)
- [Future Build Ideas](docs/future-build-ideas.md)

---

### `feature/generic-build`
**Purpose:** Create distributable kernel for others (non-march=native)

**Rationale:**
- Current kernel optimized only for i5-13450HX (march=native)
- Create shareable version for any modern x86-64 CPU (2015+)
- Maintain performance optimizations (BORE, LTO, BBRv3) but sacrifice ~2-3% for compatibility

**Key differences:**
- Disable `CONFIG_MNATIVE_INTEL`
- Enable `CONFIG_GENERIC_CPU` or `CONFIG_MSKYLAKE`
- Re-enable common WiFi/Realtek drivers (compat boost)
- Keep gaming/performance features enabled

**Naming:** 6.14.0-BobZKernel-Generic

**Related docs:**
- [Future Build Ideas - Shareable Generic Build](docs/future-build-ideas.md#2-shareable-generic-build)

---

### `feature/recovery-usb`
**Purpose:** Lightweight recovery/rescue kernel for portable USB

**Philosophy:** Maximum hardware compatibility over performance

**Design:**
- Boot on ANY x86-64 system (work laptops, servers, old/new hardware)
- Generic CPU support (all AMD/Intel generations)
- All common hardware drivers enabled (WiFi, storage, filesystem)
- Recovery tools: DM-crypt, LVM, RAID, NBD support

**Rationale:** Need rescue kernel that works everywhere, not just your laptop

**Related docs:**
- [Future Build Ideas - Recovery USB Lightweight Kernel](docs/future-build-ideas.md#3-recovery-usb-lightweight-kernel)

---

## Branch Workflow

### Making a change:
1. **For stable updates:** Create feature branch off `dev`, test, PR to `stable`
2. **For 6.18 work:** Work on `feature/6.18-lts`
3. **For generic build:** Work on `feature/generic-build`
4. **For recovery USB:** Work on `feature/recovery-usb`

### Before committing:
- Update relevant docs in `docs/`
- Update config file in `configs/` if kernel config changed
- Add meaningful commit message with context

### Merging to stable:
- All testing complete on hardware ✅
- No regressions from current build
- Performance verified (if applicable)
- Documentation updated

---

## Current Status

| Branch | Kernel | Status | Last Update |
|--------|--------|--------|-------------|
| `stable` | 6.14.0-BobZKernel | ✅ Active | Jan 2026 |
| `dev` | 6.14.0-BobZKernel | 🔧 Ready | Jan 2026 |
| `feature/6.18-lts` | 6.18.0 (planned) | 📋 Planned | — |
| `feature/generic-build` | 6.14.0-Generic | 📋 Planned | — |
| `feature/recovery-usb` | 6.14.0-Recovery | 📋 Planned | — |

---

## Git Commands Reference

**View all branches:**
```bash
git branch -a
```

**Switch branches:**
```bash
git checkout stable      # Switch to stable
git checkout dev         # Switch to dev
git checkout feature/6.18-lts  # Switch to 6.18 feature
```

**Create new feature branch:**
```bash
git checkout -b feature/your-feature-name
git push -u origin feature/your-feature-name
```

**Delete local branch:**
```bash
git branch -d feature/branch-name
```

**Delete remote branch:**
```bash
git push origin --delete feature/branch-name
```

---

## Documentation Structure

- **docs/INDEX.md** - Overview of all documentation
- **docs/6.18-build-plan.md** - Detailed 6.18 LTS upgrade plan
- **docs/future-build-ideas.md** - All planned feature branches
- **configs/** - Kernel config files (.config) per branch
- **patches/** - Custom patches applied

