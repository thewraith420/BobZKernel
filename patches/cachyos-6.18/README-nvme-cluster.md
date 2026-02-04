# NVMe Cluster-Aware IRQ Optimization Backport

## Status: ✅ ACTIVE (Backported to 6.18.x)

Successfully backported from Linux 6.20+ to BobZKernel 6.18.x using automated Python backport script.

## What It Does

Improves NVMe performance by **10-15%** on multi-cluster CPUs by aligning IRQ affinity with CPU cluster boundaries.

**Perfect for your Intel i5-13420H (Raptor Lake)** with P-cores and E-cores grouped in clusters sharing L2 cache.

## Automatic Application

Applied automatically during `./scripts/update-and-build.sh`:
1. CachyOS patches applied
2. **→ Cluster-aware backport applied** ← Happens here
3. Kernel builds with optimization

## Manual Application

```bash
./scripts/apply-cluster-aware-backport.sh
```

## Point Update Compatibility

The backport uses **function signature matching** instead of line numbers, making it resilient to 6.18.x point updates (6.18.8, 6.18.9, etc.). If lib/group_cpus.c structure changes drastically, the script fails safely without breaking the build.

## Verification

After building:
```bash
nm vmlinux | grep cluster_cpus
```

Should show: `__try_group_cluster_cpus` and `alloc_cluster_groups` functions.

## Technical Details

**Dependencies (all present in 6.18.7):**
- ✅ `topology_cluster_cpumask()`
- ✅ `cpumask_weight_and()`
- ✅ `CONFIG_NUMA=y`

**Files modified:**
- `builds/linux-6.18/lib/group_cpus.c`

**Backport scripts:**
- `scripts/cluster-aware-backport.py` - Applies code changes
- `scripts/apply-cluster-aware-backport.sh` - Workflow integration

## Upstream Status

- **Author**: Wangyang Guo (Intel)
- **Target**: Linux 6.20+ merge window
- **Status**: Under review in mm-everything tree

## References

- [Phoronix Article](https://www.phoronix.com/news/Faster-Linux-NVMe-Cluster-Aware)
- [LKML v2 Patch](https://lkml.org/lkml/2026/1/13/140)
- [Mail Archive](http://www.mail-archive.com/linux-block@vger.kernel.org/msg44047.html)

---
**Backported for BobZKernel** - Making 6.18 LTS awesome for Raptor Lake

