#!/bin/bash
# nvidia-pm-debug-patch.sh - Add debug printk to NVIDIA PM callbacks
# to identify exact hang point during S3 suspend on BobZKernel
#
# Usage:
#   sudo ./nvidia-pm-debug-patch.sh apply    # Apply debug patch
#   sudo ./nvidia-pm-debug-patch.sh revert   # Revert to original
#   sudo ./nvidia-pm-debug-patch.sh rebuild  # Rebuild DKMS after patching

set -euo pipefail

# Auto-detect the installed NVIDIA DKMS source directory. Accept an explicit
# version as $2 (e.g. ./nvidia-pm-debug-patch.sh apply 595.71.05). Fall back
# to the highest-versioned /usr/src/nvidia-* otherwise.
NVIDIA_VERSION="${2:-}"
if [ -z "$NVIDIA_VERSION" ]; then
    NVIDIA_VERSION=$(ls -d /usr/src/nvidia-* 2>/dev/null \
                     | sed 's|.*/nvidia-||' \
                     | sort -V | tail -1)
fi
if [ -z "$NVIDIA_VERSION" ] || [ ! -d "/usr/src/nvidia-$NVIDIA_VERSION" ]; then
    echo "Error: could not find /usr/src/nvidia-* — install the NVIDIA driver via DKMS first" >&2
    exit 1
fi
NVIDIA_SRC="/usr/src/nvidia-$NVIDIA_VERSION"
echo "Using NVIDIA source: $NVIDIA_SRC"

NV_C="$NVIDIA_SRC/kernel-open/nvidia/nv.c"
NV_DRM_DRV="$NVIDIA_SRC/kernel-open/nvidia-drm/nvidia-drm-drv.c"
NV_MODESET="$NVIDIA_SRC/kernel-open/nvidia/nv-modeset-interface.c"
DYN_POWER="$NVIDIA_SRC/src/nvidia/arch/nvalloc/unix/src/dynamic-power.c"
KERNEL_VER=$(uname -r)

backup() {
    for f in "$NV_C" "$NV_DRM_DRV" "$NV_MODESET" "$DYN_POWER"; do
        if [ -f "$f" ] && [ ! -f "$f.orig" ]; then
            cp "$f" "$f.orig"
            echo "Backed up: $f"
        fi
    done
}

apply_patch() {
    backup

    echo "=== Patching nv.c: nv_pm_notifier ==="
    # Add debug to nv_pm_notifier
    sed -i '/^static int nv_pm_notifier(struct notifier_block \*nb, unsigned long event, void \*unused)$/,/^}$/ {
        /switch (event) {/i\    pr_info("BOBZDBG: nv_pm_notifier ENTER event=%lu\\n", event);
        /return NOTIFY_OK;/i\    pr_info("BOBZDBG: nv_pm_notifier OK, returning NOTIFY_OK\\n");
        /return NOTIFY_BAD;/i\    pr_info("BOBZDBG: nv_pm_notifier FAILED status=0x%x, returning NOTIFY_BAD\\n", status);
        /return NOTIFY_DONE;/i\        pr_info("BOBZDBG: nv_pm_notifier unknown event, returning NOTIFY_DONE\\n");
    }' "$NV_C"

    echo "=== Patching nv.c: nv_set_system_power_state ==="
    # Use python for more complex patches
    python3 - "$NV_C" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

# Patch nv_set_system_power_state
old = '''nv_set_system_power_state(
    nv_power_state_t power_state,
    nv_pm_action_depth_t pm_action_depth
)
{
    NV_STATUS status;
    nv_pm_action_t pm_action;'''
new = '''nv_set_system_power_state(
    nv_power_state_t power_state,
    nv_pm_action_depth_t pm_action_depth
)
{
    NV_STATUS status;
    nv_pm_action_t pm_action;
    pr_info("BOBZDBG: nv_set_system_power_state ENTER power_state=%d depth=%d\\n", power_state, pm_action_depth);'''
content = content.replace(old, new, 1)

# Patch nv_suspend_devices entry
old = '''nv_suspend_devices(
    nv_pm_action_t pm_action,
    nv_pm_action_depth_t pm_action_depth
)
{
    nv_linux_state_t *nvl;
    NvBool resume_devices = NV_FALSE;
    NV_STATUS status = NV_OK;

    nvidia_modeset_suspend(0);'''
new = '''nv_suspend_devices(
    nv_pm_action_t pm_action,
    nv_pm_action_depth_t pm_action_depth
)
{
    nv_linux_state_t *nvl;
    NvBool resume_devices = NV_FALSE;
    NV_STATUS status = NV_OK;

    pr_info("BOBZDBG: nv_suspend_devices ENTER pm_action=%d depth=%d\\n", pm_action, pm_action_depth);
    pr_info("BOBZDBG: nv_suspend_devices calling nvidia_modeset_suspend(0)\\n");
    nvidia_modeset_suspend(0);
    pr_info("BOBZDBG: nv_suspend_devices nvidia_modeset_suspend(0) DONE\\n");'''
content = content.replace(old, new, 1)

# Patch nv_suspend_devices - after nv_uvm_suspend
old = '''    if (status == NV_OK)
    {
        status = nv_uvm_suspend();
        WARN_ON(status != NV_OK);
    }
    if (status != NV_OK)
    {
        goto done;
    }'''
new = '''    if (status == NV_OK)
    {
        pr_info("BOBZDBG: nv_suspend_devices calling nv_uvm_suspend()\\n");
        status = nv_uvm_suspend();
        pr_info("BOBZDBG: nv_suspend_devices nv_uvm_suspend() returned 0x%x\\n", status);
        WARN_ON(status != NV_OK);
    }
    if (status != NV_OK)
    {
        goto done;
    }'''
content = content.replace(old, new, 1)

# Patch nv_pmops_suspend
old = '''int nv_pmops_suspend(
    struct device *dev
)
{
    NV_STATUS status;

    status = nvidia_suspend(dev, NV_PM_ACTION_STANDBY, NV_FALSE);'''
new = '''int nv_pmops_suspend(
    struct device *dev
)
{
    NV_STATUS status;

    pr_info("BOBZDBG: nv_pmops_suspend ENTER dev=%s\\n", dev_name(dev));
    status = nvidia_suspend(dev, NV_PM_ACTION_STANDBY, NV_FALSE);
    pr_info("BOBZDBG: nv_pmops_suspend nvidia_suspend returned 0x%x\\n", status);'''
content = content.replace(old, new, 1)

# Patch nvidia_suspend - add debug to key points
old = '''    if (nv->is_pm_unsupported)
    {
        status = NV_ERR_NOT_SUPPORTED;
        goto done;
    }

    if ((nv->flags & NV_FLAG_SUSPENDED) != 0)
    {
        nvl->suspend_count++;
        goto pci_pm;
    }'''
new = '''    if (nv->is_pm_unsupported)
    {
        pr_info("BOBZDBG: nvidia_suspend PM unsupported for this device\\n");
        status = NV_ERR_NOT_SUPPORTED;
        goto done;
    }

    if ((nv->flags & NV_FLAG_SUSPENDED) != 0)
    {
        pr_info("BOBZDBG: nvidia_suspend already suspended, count++\\n");
        nvl->suspend_count++;
        goto pci_pm;
    }'''
content = content.replace(old, new, 1)

# Patch nvidia_suspend - modeset and power management calls
old = '''    nvidia_modeset_suspend(nv->gpu_id);

    status = nv_power_management(nv, pm_action);

    nv->flags |= NV_FLAG_SUSPENDED;'''
new = '''    pr_info("BOBZDBG: nvidia_suspend calling nvidia_modeset_suspend(gpu_id=%u) is_procfs=%d\\n", nv->gpu_id, is_procfs_suspend);
    nvidia_modeset_suspend(nv->gpu_id);
    pr_info("BOBZDBG: nvidia_suspend nvidia_modeset_suspend DONE\\n");

    pr_info("BOBZDBG: nvidia_suspend calling nv_power_management pm_action=%d\\n", pm_action);
    status = nv_power_management(nv, pm_action);
    pr_info("BOBZDBG: nvidia_suspend nv_power_management returned 0x%x\\n", status);

    nv->flags |= NV_FLAG_SUSPENDED;'''
content = content.replace(old, new, 1)

# Patch nv_power_management - entry, rm_power_management, exit
old = '''    status = nv_check_gpu_state(nv);
    if (status == NV_ERR_GPU_IS_LOST)
    {
        NV_DEV_PRINTF(NV_DBG_INFO, nv, "GPU is lost, skipping PM event\\n");
        goto failure;
    }

    switch (pm_action)
    {
        case NV_PM_ACTION_STANDBY:
            /* fall through */
        case NV_PM_ACTION_HIBERNATE:
        {'''
new = '''    pr_info("BOBZDBG: nv_power_management ENTER pm_action=%d\\n", pm_action);
    status = nv_check_gpu_state(nv);
    if (status == NV_ERR_GPU_IS_LOST)
    {
        NV_DEV_PRINTF(NV_DBG_INFO, nv, "GPU is lost, skipping PM event\\n");
        pr_info("BOBZDBG: nv_power_management GPU LOST\\n");
        goto failure;
    }

    switch (pm_action)
    {
        case NV_PM_ACTION_STANDBY:
            /* fall through */
        case NV_PM_ACTION_HIBERNATE:
        {'''
content = content.replace(old, new, 1)

# Patch rm_power_management call inside nv_power_management (standby/hibernate path)
old = '''            nv_kthread_q_flush(&nvl->open_q);

            status = rm_power_management(sp, nv, pm_action);

            nv_kthread_q_stop(&nvl->bottom_half_q);

            nv_disable_pat_support();'''
new = '''            nv_kthread_q_flush(&nvl->open_q);

            pr_info("BOBZDBG: nv_power_management calling rm_power_management (suspend)\\n");
            status = rm_power_management(sp, nv, pm_action);
            pr_info("BOBZDBG: nv_power_management rm_power_management returned 0x%x\\n", status);

            nv_kthread_q_stop(&nvl->bottom_half_q);

            nv_disable_pat_support();'''
content = content.replace(old, new, 1)

# Also instrument the down_write/up_write in nv_set_system_power_state
old = '''        down_write(&nv_system_pm_lock);
        status = nv_suspend_devices(pm_action, nv_system_pm_action_depth);'''
new = '''        pr_info("BOBZDBG: nv_set_system_power_state acquiring nv_system_pm_lock write\\n");
        down_write(&nv_system_pm_lock);
        pr_info("BOBZDBG: nv_set_system_power_state nv_system_pm_lock acquired, calling nv_suspend_devices\\n");
        status = nv_suspend_devices(pm_action, nv_system_pm_action_depth);
        pr_info("BOBZDBG: nv_set_system_power_state nv_suspend_devices returned 0x%x\\n", status);'''
content = content.replace(old, new, 1)

# Instrument ldata_lock in nvidia_suspend
old = '''    down(&nvl->ldata_lock);

    if (((nv->flags & NV_FLAG_INITIALIZED) == 0) &&
        ((nv->flags & NV_FLAG_PERSISTENT_SW_STATE) == 0))
    {
        goto done;
    }'''
new = '''    pr_info("BOBZDBG: nvidia_suspend acquiring ldata_lock\\n");
    down(&nvl->ldata_lock);
    pr_info("BOBZDBG: nvidia_suspend ldata_lock acquired, flags=0x%x\\n", nv->flags);

    if (((nv->flags & NV_FLAG_INITIALIZED) == 0) &&
        ((nv->flags & NV_FLAG_PERSISTENT_SW_STATE) == 0))
    {
        pr_info("BOBZDBG: nvidia_suspend device not initialized, skipping\\n");
        goto done;
    }'''
content = content.replace(old, new, 1)

with open(f, 'w') as fh:
    fh.write(content)
print(f"Patched {f}")
PYEOF

    echo "=== Patching nvidia-drm-drv.c: nv_drm_suspend_resume ==="
    python3 - "$NV_DRM_DRV" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

old = '''void nv_drm_suspend_resume(NvBool suspend)
{
    static NvU32 nv_drm_suspend_count = 0;
    struct nv_drm_device *nv_dev;

    mutex_lock(&dev_list_mutex);'''
new = '''void nv_drm_suspend_resume(NvBool suspend)
{
    static NvU32 nv_drm_suspend_count = 0;
    struct nv_drm_device *nv_dev;

    pr_info("BOBZDBG: nv_drm_suspend_resume ENTER suspend=%d\\n", suspend);
    pr_info("BOBZDBG: nv_drm_suspend_resume acquiring dev_list_mutex\\n");
    mutex_lock(&dev_list_mutex);
    pr_info("BOBZDBG: nv_drm_suspend_resume dev_list_mutex acquired, count=%u\\n", nv_drm_suspend_count);'''
content = content.replace(old, new, 1)

# After drm_kms_helper_poll_disable
old = '''        if (suspend) {
            drm_kms_helper_poll_disable(dev);
#if defined(NV_DRM_FBDEV_AVAILABLE)
            drm_fb_helper_set_suspend_unlocked(dev->fb_helper, 1);
#endif
            drm_mode_config_reset(dev);'''
new = '''        if (suspend) {
            pr_info("BOBZDBG: nv_drm_suspend calling drm_kms_helper_poll_disable\\n");
            drm_kms_helper_poll_disable(dev);
            pr_info("BOBZDBG: nv_drm_suspend drm_kms_helper_poll_disable DONE\\n");
#if defined(NV_DRM_FBDEV_AVAILABLE)
            pr_info("BOBZDBG: nv_drm_suspend calling drm_fb_helper_set_suspend_unlocked\\n");
            drm_fb_helper_set_suspend_unlocked(dev->fb_helper, 1);
            pr_info("BOBZDBG: nv_drm_suspend drm_fb_helper_set_suspend_unlocked DONE\\n");
#endif
            pr_info("BOBZDBG: nv_drm_suspend calling drm_mode_config_reset\\n");
            drm_mode_config_reset(dev);
            pr_info("BOBZDBG: nv_drm_suspend drm_mode_config_reset DONE\\n");'''
content = content.replace(old, new, 1)

old = '''done:
    mutex_unlock(&dev_list_mutex);
}

#endif /* NV_DRM_AVAILABLE */'''
new = '''done:
    pr_info("BOBZDBG: nv_drm_suspend_resume releasing dev_list_mutex\\n");
    mutex_unlock(&dev_list_mutex);
    pr_info("BOBZDBG: nv_drm_suspend_resume EXIT\\n");
}

#endif /* NV_DRM_AVAILABLE */'''
content = content.replace(old, new, 1)

with open(f, 'w') as fh:
    fh.write(content)
print(f"Patched {f}")
PYEOF

    echo "=== Patching nv-modeset-interface.c: nvidia_modeset_suspend ==="
    python3 - "$NV_MODESET" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

old = '''void nvidia_modeset_suspend(NvU32 gpuId)
{
    if (nv_modeset_callbacks)
    {
        nv_modeset_callbacks->suspend(gpuId);
    }
}'''
new = '''void nvidia_modeset_suspend(NvU32 gpuId)
{
    pr_info("BOBZDBG: nvidia_modeset_suspend ENTER gpuId=%u callbacks=%p\\n", gpuId, nv_modeset_callbacks);
    if (nv_modeset_callbacks)
    {
        pr_info("BOBZDBG: nvidia_modeset_suspend calling callback->suspend(%u)\\n", gpuId);
        nv_modeset_callbacks->suspend(gpuId);
        pr_info("BOBZDBG: nvidia_modeset_suspend callback->suspend DONE\\n");
    }
    pr_info("BOBZDBG: nvidia_modeset_suspend EXIT\\n");
}'''
content = content.replace(old, new, 1)

with open(f, 'w') as fh:
    fh.write(content)
print(f"Patched {f}")
PYEOF

    echo "=== Patching dynamic-power.c: rm_power_management ==="
    python3 - "$DYN_POWER" << 'PYEOF'
import sys
f = sys.argv[1]
with open(f, 'r') as fh:
    content = fh.read()

old = '''NV_STATUS NV_API_CALL rm_power_management(
    nvidia_stack_t *sp,
    nv_state_t *pNv,
    nv_pm_action_t pmAction
)
{
    THREAD_STATE_NODE threadState;
    NV_STATUS rmStatus = NV_OK;
    void *fp;
    NvBool bTryAgain = NV_FALSE;

    NV_ENTER_RM_RUNTIME(sp,fp);
    threadStateInit(&threadState, THREAD_STATE_FLAGS_DEVICE_INIT);'''
new = '''NV_STATUS NV_API_CALL rm_power_management(
    nvidia_stack_t *sp,
    nv_state_t *pNv,
    nv_pm_action_t pmAction
)
{
    THREAD_STATE_NODE threadState;
    NV_STATUS rmStatus = NV_OK;
    void *fp;
    NvBool bTryAgain = NV_FALSE;

    pr_info("BOBZDBG: rm_power_management ENTER pmAction=%d\\n", pmAction);
    NV_ENTER_RM_RUNTIME(sp,fp);
    threadStateInit(&threadState, THREAD_STATE_FLAGS_DEVICE_INIT);'''
content = content.replace(old, new, 1)

# After rmapiLockAcquire
old = '''    // LOCK: acquire API lock
    if ((rmStatus = rmapiLockAcquire(API_LOCK_FLAGS_NONE, RM_LOCK_MODULES_DYN_POWER)) == NV_OK)
    {
        OBJGPU *pGpu = NV_GET_NV_PRIV_PGPU(pNv);'''
new = '''    // LOCK: acquire API lock
    pr_info("BOBZDBG: rm_power_management acquiring API lock\\n");
    if ((rmStatus = rmapiLockAcquire(API_LOCK_FLAGS_NONE, RM_LOCK_MODULES_DYN_POWER)) == NV_OK)
    {
        OBJGPU *pGpu = NV_GET_NV_PRIV_PGPU(pNv);
        pr_info("BOBZDBG: rm_power_management API lock acquired, pGpu=%p\\n", pGpu);'''
content = content.replace(old, new, 1)

# Before rmGpuLocksAcquire
old = '''                // LOCK: acquire GPUs lock
                if ((rmStatus = rmGpuLocksAcquire(GPUS_LOCK_FLAGS_NONE, RM_LOCK_MODULES_DYN_POWER)) == NV_OK)
                {'''
new = '''                // LOCK: acquire GPUs lock
                pr_info("BOBZDBG: rm_power_management acquiring GPU lock\\n");
                if ((rmStatus = rmGpuLocksAcquire(GPUS_LOCK_FLAGS_NONE, RM_LOCK_MODULES_DYN_POWER)) == NV_OK)
                {
                    pr_info("BOBZDBG: rm_power_management GPU lock acquired\\n");'''
content = content.replace(old, new, 1)

# Before RmPowerManagement call
old = '''                        rmStatus = RmPowerManagement(pGpu, pmAction);'''
new = '''                        pr_info("BOBZDBG: rm_power_management calling RmPowerManagement action=%d\\n", pmAction);
                        rmStatus = RmPowerManagement(pGpu, pmAction);
                        pr_info("BOBZDBG: rm_power_management RmPowerManagement returned 0x%x\\n", rmStatus);'''
content = content.replace(old, new, 1)

# Before RmGcxPowerManagement
old = '''                            rmStatus = RmGcxPowerManagement(pGpu,
                                            pmAction == NV_PM_ACTION_STANDBY,
                                            NV_FALSE, &bTryAgain);'''
new = '''                            pr_info("BOBZDBG: rm_power_management calling RmGcxPowerManagement (S0ix path)\\n");
                            rmStatus = RmGcxPowerManagement(pGpu,
                                            pmAction == NV_PM_ACTION_STANDBY,
                                            NV_FALSE, &bTryAgain);
                            pr_info("BOBZDBG: rm_power_management RmGcxPowerManagement returned 0x%x\\n", rmStatus);'''
content = content.replace(old, new, 1)

with open(f, 'w') as fh:
    fh.write(content)
print(f"Patched {f}")
PYEOF

    echo ""
    echo "=== All patches applied! ==="
    echo "Run: sudo $0 rebuild"
}

revert_patch() {
    for f in "$NV_C" "$NV_DRM_DRV" "$NV_MODESET" "$DYN_POWER"; do
        if [ -f "$f.orig" ]; then
            cp "$f.orig" "$f"
            rm "$f.orig"
            echo "Reverted: $f"
        fi
    done
    echo "=== All patches reverted ==="
}

rebuild_dkms() {
    echo "=== Removing old DKMS build for $KERNEL_VER ==="
    dkms remove nvidia/595.45.04 -k "$KERNEL_VER" 2>/dev/null || true

    echo "=== Building nvidia DKMS for $KERNEL_VER ==="
    dkms build nvidia/595.45.04 -k "$KERNEL_VER"

    echo "=== Installing nvidia DKMS for $KERNEL_VER ==="
    dkms install nvidia/595.45.04 -k "$KERNEL_VER"

    echo ""
    echo "=== DKMS rebuild complete ==="
    echo "To test: sudo rtcwake -m mem -s 10 -v"
    echo "To check: sudo dmesg | grep BOBZDBG"
}

case "${1:-}" in
    apply)
        apply_patch
        ;;
    revert)
        revert_patch
        ;;
    rebuild)
        rebuild_dkms
        ;;
    all)
        apply_patch
        rebuild_dkms
        ;;
    *)
        echo "Usage: $0 {apply|revert|rebuild|all}"
        echo "  apply   - Apply debug printk patches to nvidia source"
        echo "  revert  - Revert patches (restore original files)"
        echo "  rebuild - Rebuild DKMS modules"
        echo "  all     - Apply patches and rebuild"
        exit 1
        ;;
esac
