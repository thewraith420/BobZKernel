# BORE Scheduler Patch Porting Guide

This guide documents how to manually port the CachyOS BORE scheduler patch when it conflicts with newer kernel versions.

## Background

The BORE (Burst-Oriented Response Enhancer) scheduler patch from CachyOS modifies 13 files in the Linux kernel. When a new kernel version is released before CachyOS updates their patches, the main conflict typically occurs in `kernel/sched/fair.c`.

## When This Guide Is Needed

- New kernel version released (e.g., 6.18.4)
- CachyOS patches not yet updated for the new version
- BORE patch fails to apply with conflicts in `kernel/sched/fair.c`

## Successfully Ported Versions

- ✅ 6.18.3 → 6.18.4 (January 8, 2026)

## Porting Process

### Step 1: Identify the Conflict

The BORE patch will fail during patch application with an error like:
```
error: patch failed: kernel/sched/fair.c:67
error: kernel/sched/fair.c: patch does not apply
```

### Step 2: Apply Non-Conflicting Parts

Apply all parts of the BORE patch EXCEPT fair.c:
```bash
cd builds/linux-6.18
git apply /path/to/0001-bore-cachy.patch --exclude="kernel/sched/fair.c"
```

This creates:
- `include/linux/sched/bore.h` (BORE header)
- `kernel/sched/bore.c` (BORE implementation)
- Modifications to init/Kconfig, kernel/Kconfig.hz, kernel/fork.c, etc.

### Step 3: Manually Fix fair.c

The BORE patch makes modifications to `kernel/sched/fair.c` in these locations:

#### 3.1: Add BORE Header Include (after line ~59)
```c
#include "sched.h"
#include "stats.h"
#include "autogroup.h"

#ifdef CONFIG_SCHED_BORE
#include <linux/sched/bore.h>
#endif /* CONFIG_SCHED_BORE */
```

#### 3.2: Fix CONFIG_CACHY Conflicts (around line ~70-100)

**CONFLICT**: The BORE patch expects to replace CONFIG_CACHY blocks with CONFIG_SCHED_BORE blocks.

**Original (6.18.4 with CachyOS patches):**
```c
unsigned int sysctl_sched_tunable_scaling = SCHED_TUNABLESCALING_LOG;

#ifdef CONFIG_CACHY
unsigned int sysctl_sched_base_slice = 350000ULL;
static unsigned int normalized_sysctl_sched_base_slice = 350000ULL;
#else
unsigned int sysctl_sched_base_slice = 700000ULL;
static unsigned int normalized_sysctl_sched_base_slice = 700000ULL;
#endif

#ifdef CONFIG_CACHY
__read_mostly unsigned int sysctl_sched_migration_cost = 300000UL;
#else
__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;
#endif
```

**Replace with BORE version:**
```c
#ifdef CONFIG_SCHED_BORE
unsigned int sysctl_sched_tunable_scaling = SCHED_TUNABLESCALING_NONE;
#else /* !CONFIG_SCHED_BORE */
unsigned int sysctl_sched_tunable_scaling = SCHED_TUNABLESCALING_LOG;
#endif /* CONFIG_SCHED_BORE */

#ifdef CONFIG_SCHED_BORE
static const unsigned int nsecs_per_tick = 1000000000ULL / HZ;
unsigned int sysctl_sched_min_base_slice = CONFIG_MIN_BASE_SLICE_NS;
__read_mostly uint sysctl_sched_base_slice = nsecs_per_tick;
#else /* !CONFIG_SCHED_BORE */
unsigned int sysctl_sched_base_slice = 700000ULL;
static unsigned int normalized_sysctl_sched_base_slice = 700000ULL;
#endif /* CONFIG_SCHED_BORE */

__read_mostly unsigned int sysctl_sched_migration_cost = 500000UL;
```

Also remove the CONFIG_CACHY cfs_bandwidth_slice block (around line 135):
```c
// Remove this block:
#ifdef CONFIG_CACHY
static unsigned int sysctl_sched_cfs_bandwidth_slice = 3000UL;
#else
static unsigned int sysctl_sched_cfs_bandwidth_slice = 5000UL;
#endif

// Replace with:
static unsigned int sysctl_sched_cfs_bandwidth_slice = 5000UL;
```

#### 3.3: update_sysctl Function (around line ~206)

Wrap the existing update_sysctl implementation with CONFIG_SCHED_BORE:

**Find:**
```c
static unsigned int get_update_sysctl_factor(void)
{
    // ... function body ...
}

static void update_sysctl(void)
{
    // ... function body ...
}
```

**Replace with:**
```c
#ifdef CONFIG_SCHED_BORE
static void update_sysctl(void) {
    sysctl_sched_base_slice = nsecs_per_tick *
        max(1UL, DIV_ROUND_UP(sysctl_sched_min_base_slice, nsecs_per_tick));
}
void sched_update_min_base_slice(void) { update_sysctl(); }
#else /* !CONFIG_SCHED_BORE */
static unsigned int get_update_sysctl_factor(void)
{
    // ... original function body ...
}

static void update_sysctl(void)
{
    // ... original function body ...
}
#endif /* CONFIG_SCHED_BORE */
```

#### 3.4: update_entity_lag (around line ~725)

Add BORE limit modification:
```c
vlag = avg_vruntime(cfs_rq) - se->vruntime;
limit = calc_delta_fair(max_t(u64, 2*se->slice, TICK_NSEC), se);
#ifdef CONFIG_SCHED_BORE
limit >>= !!sched_bore;
#endif /* CONFIG_SCHED_BORE */

se->vlag = clamp(vlag, -limit, limit);
```

#### 3.5: set_protect_slice (around line ~894)

Modify to use BORE run_to_parity logic:
```c
static inline void set_protect_slice(struct cfs_rq *cfs_rq, struct sched_entity *se)
{
#ifdef CONFIG_SCHED_BORE
    u64 slice = sysctl_sched_base_slice;
    bool run_to_parity = likely(sched_bore) ?
        sched_feat(RUN_TO_PARITY_BORE) : sched_feat(RUN_TO_PARITY);
#else /* CONFIG_SCHED_BORE */
    u64 slice = normalized_sysctl_sched_base_slice;
    bool run_to_parity = sched_feat(RUN_TO_PARITY);
#endif /* CONFIG_SCHED_BORE */
    u64 vprot = se->deadline;

    if (run_to_parity)
        slice = cfs_rq_min_slice(cfs_rq);

    // ... rest of function ...
}
```

#### 3.6: __pick_eevdf (around line ~970)

Add futex_waiting check:
```c
if (curr && protect && protect_slice(curr))
#ifdef CONFIG_SCHED_BORE
    if (!entity_is_task(curr) ||
        !task_of(curr)->bore.futex_waiting ||
        unlikely(!sched_bore))
#endif /* CONFIG_SCHED_BORE */
    return curr;
```

#### 3.7: sched_update_scaling (around line ~1037)

Wrap with ifndef CONFIG_SCHED_BORE:
```c
#if !defined(CONFIG_SCHED_BORE)
int sched_update_scaling(void)
{
    // ... function body ...
}
#endif /* CONFIG_SCHED_BORE */
```

#### 3.8: update_curr (around line ~1246)

Add BORE update hook:
```c
if (entity_is_task(curr)) {
#ifdef CONFIG_SCHED_BORE
    struct task_struct *p = task_of(curr);
    update_curr_bore(p, delta_exec);
#endif /* CONFIG_SCHED_BORE */

    /*
     * If the fair_server is active...
```

#### 3.9: reweight_entity (around line ~3790)

Change from static to non-static:
```c
// Change:
static void reweight_entity(struct cfs_rq *cfs_rq, struct sched_entity *se,
                           unsigned long weight)

// To:
void reweight_entity(struct cfs_rq *cfs_rq, struct sched_entity *se,
                    unsigned long weight)
```

#### 3.10: place_entity (around line ~5139)

Major modifications to vslice calculation:

**Change initialization:**
```c
// From:
u64 vslice, vruntime = avg_vruntime(cfs_rq);
// To:
u64 vslice = 0, vruntime = avg_vruntime(cfs_rq);
```

**Remove early vslice calculation:**
```c
if (!se->custom_slice)
    se->slice = sysctl_sched_base_slice;
// Remove this line:
// vslice = calc_delta_fair(se->slice, se);
```

**Add BORE logic before deadline calculation:**
```c
if (se->rel_deadline) {
    se->deadline += se->vruntime;
    se->rel_deadline = 0;
    return;
}
#ifdef CONFIG_SCHED_BORE
if (entity_is_task(se) &&
        likely(sched_bore) &&
        task_of(se)->bore.futex_waiting)
    goto vslice_found;
#endif /* !CONFIG_SCHED_BORE */
vslice = calc_delta_fair(se->slice, se);
#ifdef CONFIG_SCHED_BORE
if (likely(sched_bore))
    vslice >>= !!(flags & (ENQUEUE_INITIAL | ENQUEUE_WAKEUP));
else
#endif /* CONFIG_SCHED_BORE */
/*
 * When joining the competition...
 */
if (sched_feat(PLACE_DEADLINE_INITIAL) && (flags & ENQUEUE_INITIAL))
    vslice /= 2;

#ifdef CONFIG_SCHED_BORE
vslice_found:
#endif /* CONFIG_SCHED_BORE */
/*
 * EEVDF: vd_i = ve_i + r_i/w_i
 */
se->deadline = se->vruntime + vslice;
```

#### 3.11: requeue_delayed_entity (around line ~5263 and ~6900)

**Update function signature (declaration and definition):**
```c
// Change:
static void requeue_delayed_entity(struct sched_entity *se)
// To:
static void requeue_delayed_entity(struct sched_entity *se, int flags)
```

**Update function body (~6900):**
```c
if (sched_feat(DELAY_ZERO)) {
#ifdef CONFIG_SCHED_BORE
    if (likely(sched_bore))
        flags |= ENQUEUE_WAKEUP;
    else {
#endif /* CONFIG_SCHED_BORE */
    flags = 0;
    update_entity_lag(cfs_rq, se);
#ifdef CONFIG_SCHED_BORE
    }
#endif /* CONFIG_SCHED_BORE */
    if (se->vlag > 0) {
        // ...
        place_entity(cfs_rq, se, flags);  // Pass flags parameter
        // ...
    }
}
```

**Update all call sites:**
```c
// Change all instances of:
requeue_delayed_entity(se);
// To:
requeue_delayed_entity(se, flags);
```

#### 3.12: dequeue_entity (around line ~5420)

Add BORE update_entity_lag call:
```c
if (sched_feat(DELAY_DEQUEUE) && delay &&
    !entity_eligible(cfs_rq, se)) {
    update_load_avg(cfs_rq, se, 0);
#ifdef CONFIG_SCHED_BORE
    if (sched_feat(DELAY_ZERO) && likely(sched_bore))
        update_entity_lag(cfs_rq, se);
#endif /* CONFIG_SCHED_BORE */
    set_delayed(se);
    return false;
}
```

#### 3.13: dequeue_task_fair (around line ~7202)

Add restart_burst_bore call:
```c
util_est_update(&rq->cfs, p, flags & DEQUEUE_SLEEP);
#ifdef CONFIG_SCHED_BORE
struct cfs_rq *cfs_rq = &rq->cfs;
struct sched_entity *se = &p->se;
if ((flags & DEQUEUE_SLEEP) && entity_is_task(se)) {
    if (cfs_rq->curr == se)
        update_curr(cfs_rq_of(&p->se));
    restart_burst_bore(p);
}
#endif /* CONFIG_SCHED_BORE */
if (dequeue_entities(rq, &p->se, flags) < 0)
    return false;
```

#### 3.14: check_preempt_wakeup_fair (around line ~8860)

Add BORE run_to_parity check:
```c
if (__pick_eevdf(cfs_rq, !do_preempt_short) == pse)
    goto preempt;

#ifdef CONFIG_SCHED_BORE
bool run_to_parity = likely(sched_bore) ?
    sched_feat(RUN_TO_PARITY_BORE) : sched_feat(RUN_TO_PARITY);
if (run_to_parity && do_preempt_short)
#else /* CONFIG_SCHED_BORE */
if (sched_feat(RUN_TO_PARITY) && do_preempt_short)
#endif /* CONFIG_SCHED_BORE */
    update_protect_slice(cfs_rq, se);
```

#### 3.15: yield_task_fair (around line ~9046)

Reorder operations for BORE:
```c
static void yield_task_fair(struct rq *rq)
{
    struct task_struct *curr = rq->donor;
    struct cfs_rq *cfs_rq = task_cfs_rq(curr);
    struct sched_entity *se = &curr->se;

#if !defined(CONFIG_SCHED_BORE)
    if (unlikely(rq->nr_running == 1))
        return;

    clear_buddies(cfs_rq, se);
#endif /* CONFIG_SCHED_BORE */

    update_rq_clock(rq);
    update_curr(cfs_rq);
#ifdef CONFIG_SCHED_BORE
    restart_burst_rescale_deadline_bore(curr);
    if (unlikely(rq->nr_running == 1))
        return;

    clear_buddies(cfs_rq, se);
#endif /* CONFIG_SCHED_BORE */
    // ... rest of function
}
```

#### 3.16: switched_to_fair (around line ~13474)

Add reset_task_bore call:
```c
static void switched_to_fair(struct rq *rq, struct task_struct *p)
{
    WARN_ON_ONCE(p->se.sched_delayed);

    attach_task_cfs_rq(p);
#ifdef CONFIG_SCHED_BORE
    reset_task_bore(p);
#endif /* CONFIG_SCHED_BORE */

    set_task_max_allowed_capacity(p);
    // ... rest of function
}
```

### Step 4: Test Compilation

Verify fair.c compiles:
```bash
cd builds/linux-6.18
make LLVM=1 -j1 kernel/sched/fair.o
```

Should see only one warning about `reweight_entity` missing prototype (expected, since it's now non-static for BORE to use).

### Step 5: Build Full Kernel

```bash
cd /home/bob/buildstuff/BobZKernel
scripts/update-and-build.sh --skip-update
```

**Note**: If the build script tries to apply patches again, it may create conflict markers. If you see:
```
error: version control conflict marker in file
```

Search for and remove conflict markers in fair.c:
```bash
grep -n "<<<<<<< \|=======" kernel/sched/fair.c
```

Remove the markers and keep the BORE version.

### Step 6: Verify BORE is Compiled

After successful build:
```bash
grep CONFIG_SCHED_BORE /boot/config-6.18.4-BobZKernel
# Should show: CONFIG_SCHED_BORE=y

ls -lh builds/linux-6.18/kernel/sched/bore.o
# Should exist with ~33KB size
```

### Step 7: Install and Test

Install the kernel:
```bash
sudo ./scripts/install-kernel.sh 6.18
```

After reboot, verify BORE is active:
```bash
uname -r
# Should show: 6.18.4-BobZKernel

dmesg | grep -i bore
# Should show: BORE CPU Scheduler modification 6.5.9 by Masahito Suzuki

sysctl kernel.sched_bore
# Should show: kernel.sched_bore = 1
```

## Common Issues

### Conflict Markers After Build Script
If you see `<<<<<<< ours` in fair.c after running the build script, it means the script tried to apply patches again. Remove the markers manually.

### Missing BORE Functions
If compilation fails with undefined references to BORE functions, ensure `bore.c` and `bore.h` were created in Step 2.

### Wrong Line Numbers
Line numbers may vary slightly between kernel versions. Use the context and function names to find the correct locations.

## Alternative: Wait for CachyOS

If this process seems too involved, simply wait 1-2 days after a kernel release for CachyOS to update their patches. Their updated patches will apply cleanly without manual intervention.

## Preservation

The kernel source (builds/linux-6.18/) is gitignored and these changes are not preserved. You'll need to repeat this process for each new kernel version that has BORE conflicts.

Consider creating a separate patch file if you need to rebuild the same version multiple times.

## Credits

- BORE Scheduler: Masahito Suzuki
- CachyOS Patches: CachyOS Team
- Manual porting for 6.18.4: Documented January 8, 2026
