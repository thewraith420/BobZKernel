#!/bin/bash
# Diagnose and configure NVIDIA suspend/resume integration.

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

MODE="check"
ISSUES_FOUND=0

usage() {
    cat <<'EOF'
Usage: configure-nvidia-suspend.sh [--check | --apply | --auto]

  --check  Inspect NVIDIA suspend-related settings and report issues.
  --apply  Enable the recommended NVIDIA suspend settings.
  --auto   Apply fixes only if NVIDIA appears to be installed.

Environment overrides:
    BOBZKERNEL_NVIDIA_SLEEP_SERVICES=auto|enable|disable
        auto    (default) enables services except on known-problematic open-module + 6.19 setups
        enable  always enable nvidia-suspend/resume/hibernate services
        disable always disable nvidia-suspend/resume/hibernate services
EOF
}

info() {
    echo -e "${BLUE}$1${NC}"
}

ok() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}" >&2
}

have_runtime_nvidia() {
    [ -d /proc/driver/nvidia ] || lsmod | grep -q '^nvidia'
}

have_nvidia_units() {
    [ -f /usr/lib/systemd/system/nvidia-suspend.service ] || \
    [ -f /lib/systemd/system/nvidia-suspend.service ] || \
    [ -f /etc/systemd/system/nvidia-suspend.service ]
}

have_nvidia_stack() {
    have_runtime_nvidia || have_nvidia_units || grep -Rqs 'nvidia' /etc/modprobe.d /lib/modprobe.d 2>/dev/null
}

service_installed() {
    local service="$1"

    [ -f "/usr/lib/systemd/system/$service" ] || \
    [ -f "/lib/systemd/system/$service" ] || \
    [ -f "/etc/systemd/system/$service" ]
}

service_enabled_state() {
    local service="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "unknown"
        return 0
    fi

    systemctl is-enabled "$service" 2>/dev/null || true
}

is_hybrid_gpu() {
    # On hybrid (Optimus) laptops, i915 drives the display and NVIDIA is
    # render-only.  Detect this by checking if any i915/amdgpu connector is
    # the active eDP/LVDS display.
    local drm_dir conn status driver
    for drm_dir in /sys/class/drm/card*; do
        [ -d "$drm_dir" ] || continue
        driver="$(basename "$(readlink -f "$drm_dir/device/driver")" 2>/dev/null)"
        [ "$driver" = "i915" ] || [ "$driver" = "amdgpu" ] || continue
        for conn in "$drm_dir"-*; do
            [ -f "$conn/status" ] || continue
            status="$(cat "$conn/status" 2>/dev/null)"
            if [ "$status" = "connected" ]; then
                return 0
            fi
        done
    done
    return 1
}

should_enable_nvidia_sleep_services() {
    local policy
    policy="${BOBZKERNEL_NVIDIA_SLEEP_SERVICES:-auto}"

    case "$policy" in
        enable)  return 0 ;;
        disable) return 1 ;;
        auto)
            # On hybrid laptops (i915/amdgpu drives the display, NVIDIA is
            # render-only), the nvidia-sleep.sh procfs path is unnecessary
            # and crashes on open 595 modules.  Kernel PCI PM handles it.
            if is_hybrid_gpu; then
                return 1
            fi
            return 0
            ;;
        *)
            warn "Unknown BOBZKERNEL_NVIDIA_SLEEP_SERVICES=$policy; using auto"
            return 0
            ;;
    esac
}

show_sleep_mode() {
    if [ -r /sys/power/mem_sleep ]; then
        echo "$(cat /sys/power/mem_sleep)"
    else
        echo "unknown"
    fi
}

runtime_param() {
    local name="$1"

    if [ ! -r /proc/driver/nvidia/params ]; then
        return 1
    fi

    awk -F': *' -v key="$name" '$1 == key { print $2 }' /proc/driver/nvidia/params
}

report_issue() {
    warn "$1"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
}

check_state() {
    local preserve_runtime
    local temp_runtime
    local sleep_mode
    local service
    local enabled_state

    info "Checking NVIDIA suspend configuration..."

    if have_runtime_nvidia; then
        ok "NVIDIA driver is loaded"
    else
        warn "NVIDIA driver is not currently loaded"
    fi

    sleep_mode="$(show_sleep_mode)"
    info "mem_sleep: $sleep_mode"
    if printf '%s' "$sleep_mode" | grep -q '\[s2idle\].*deep'; then
        warn "System currently defaults to s2idle while deep is available"
        warn "If resume is still unstable after the NVIDIA fix, try mem_sleep_default=deep"
    fi

    if grep -Rqs 'nvidia-drm.*modeset=0' /etc/modprobe.d /lib/modprobe.d /etc/default/grub /etc/kernel/cmdline 2>/dev/null; then
        warn "nvidia-drm modeset is forced to 0 on this system"
        warn "That can contribute to poor resume behavior on some desktops"
    fi

    if is_hybrid_gpu; then
        ok "Hybrid GPU detected (iGPU drives display, NVIDIA is render-only)"
        info "NVIDIA sleep services should be DISABLED (kernel PCI PM handles dGPU)"
        info "PreserveVideoMemoryAllocations should be 0 (no NVIDIA framebuffer to save)"
    else
        info "Dedicated NVIDIA GPU setup (NVIDIA drives the display)"
    fi

    if have_nvidia_units; then
        for service in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
            enabled_state="$(service_enabled_state "$service")"
            if is_hybrid_gpu; then
                # On hybrid, these services should be disabled
                if [ "$enabled_state" = "enabled" ]; then
                    report_issue "$service is enabled but should be disabled on hybrid GPU"
                else
                    ok "$service is $enabled_state"
                fi
            else
                if [ "$enabled_state" = "enabled" ] || [ "$enabled_state" = "static" ] || [ "$enabled_state" = "generated" ]; then
                    ok "$service is $enabled_state"
                else
                    report_issue "$service is $enabled_state"
                fi
            fi
        done
    else
        warn "NVIDIA suspend services are not installed"
    fi

    if grep -RInE 'NVreg_PreserveVideoMemoryAllocations|NVreg_TemporaryFilePath' /etc/modprobe.d /lib/modprobe.d 2>/dev/null; then
        :
    else
        report_issue "No NVIDIA power-management module options were found in modprobe configuration"
    fi

    if preserve_runtime="$(runtime_param PreserveVideoMemoryAllocations 2>/dev/null)"; then
        info "Runtime PreserveVideoMemoryAllocations: $preserve_runtime"
        if is_hybrid_gpu; then
            if [ "$preserve_runtime" != "0" ]; then
                report_issue "PreserveVideoMemoryAllocations should be 0 on hybrid GPU (triggers procfs bug)"
            fi
        else
            if [ "$preserve_runtime" != "1" ]; then
                report_issue "PreserveVideoMemoryAllocations is not enabled at runtime"
            fi
        fi
    fi

    local s0ix_runtime
    if s0ix_runtime="$(runtime_param EnableS0ixPowerManagement 2>/dev/null)"; then
        info "Runtime EnableS0ixPowerManagement: $s0ix_runtime"
        if [ "$s0ix_runtime" != "1" ]; then
            report_issue "EnableS0ixPowerManagement is not enabled at runtime (required for s2idle)"
        fi
    fi

    if temp_runtime="$(runtime_param TemporaryFilePath 2>/dev/null)"; then
        info "Runtime TemporaryFilePath: $temp_runtime"
    fi

    # Detect rogue PCI-remove workaround services that yank the GPU off the bus
    # before suspend. These are incompatible with the NVIDIA driver's own sleep hooks.
    for rogue_svc in nvidia-suspend-workaround.service; do
        if service_installed "$rogue_svc"; then
            local rogue_state
            rogue_state="$(service_enabled_state "$rogue_svc")"
            if [ "$rogue_state" = "enabled" ]; then
                report_issue "$rogue_svc is enabled — this service removes the GPU from PCI before suspend, causing oops on resume"
            else
                ok "$rogue_svc is present but $rogue_state (not active)"
            fi
        fi
    done

    if [ "$ISSUES_FOUND" -eq 0 ]; then
        ok "No obvious NVIDIA suspend configuration problems found"
    fi
}

apply_state() {
    local service

    if [ "$EUID" -ne 0 ]; then
        error "--apply requires root"
        exit 1
    fi

    info "Applying recommended NVIDIA suspend settings..."

    # Disable any rogue PCI-remove workaround services that yank the GPU off the
    # bus before suspend.  These are fundamentally incompatible with the NVIDIA
    # driver's own sleep hooks and cause kernel oops on resume.
    if command -v systemctl >/dev/null 2>&1; then
        for rogue_svc in nvidia-suspend-workaround.service; do
            if service_installed "$rogue_svc"; then
                local rogue_state
                rogue_state="$(service_enabled_state "$rogue_svc")"
                if [ "$rogue_state" = "enabled" ]; then
                    systemctl disable "$rogue_svc" >/dev/null 2>&1 || true
                    systemctl stop "$rogue_svc" >/dev/null 2>&1 || true
                    warn "Disabled $rogue_svc (PCI-remove workaround is incompatible with NVIDIA sleep hooks)"
                fi
            fi
        done
    fi

    install -d /etc/modprobe.d
        # Remove the old incorrectly-named file if present (it sorted before nvidia.conf and lost).
        rm -f /etc/modprobe.d/nvidia-bobzkernel-suspend.conf

    # Use zz- prefix so this file sorts AFTER nvidia.conf and any other nvidia*.conf.
    if is_hybrid_gpu; then
        # Hybrid GPU: NVIDIA is render-only, i915/amdgpu drives the display.
        # PreserveVideoMemoryAllocations=0: no NVIDIA framebuffer to save.
        # Enabling it triggers a bug in the open 595 module's procfs path.
        cat > /etc/modprobe.d/zz-nvidia-bobzkernel-suspend.conf <<'EOF'
# BobZKernel NVIDIA suspend settings (hybrid/Optimus laptop).
# NVIDIA GPU is render-only — no framebuffer to preserve.
# Kernel PCI PM handles dGPU suspend; nvidia-sleep.sh services are disabled.
options nvidia NVreg_PreserveVideoMemoryAllocations=0
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_EnableS0ixPowerManagement=1
EOF
    else
        # Dedicated GPU: NVIDIA drives the display, VRAM must be preserved.
        cat > /etc/modprobe.d/zz-nvidia-bobzkernel-suspend.conf <<'EOF'
# BobZKernel NVIDIA suspend settings (dedicated GPU).
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_EnableS0ixPowerManagement=1
EOF
    fi
    ok "Wrote /etc/modprobe.d/zz-nvidia-bobzkernel-suspend.conf"

    if command -v systemctl >/dev/null 2>&1; then
        if should_enable_nvidia_sleep_services; then
            for service in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
                if service_installed "$service"; then
                    systemctl enable "$service" >/dev/null
                    ok "Enabled $service"
                fi
            done
        else
            warn "Disabling NVIDIA sleep services due to known open-module + 6.19 resume instability"
            for service in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
                if service_installed "$service"; then
                    systemctl disable "$service" >/dev/null || true
                    ok "Disabled $service"
                fi
            done
            warn "Override with BOBZKERNEL_NVIDIA_SLEEP_SERVICES=enable if you want to force the NVIDIA sleep hook path"
        fi
    else
        warn "systemctl not found; skipping NVIDIA suspend service enablement"
    fi

    if grep -Rqs 'nvidia-drm.*modeset=0' /etc/modprobe.d /lib/modprobe.d /etc/default/grub /etc/kernel/cmdline 2>/dev/null; then
        warn "nvidia-drm modeset is still forced to 0"
        warn "If resume problems continue, consider testing nvidia-drm.modeset=1"
    fi

    if [ -r /sys/power/mem_sleep ] && grep -q '\[s2idle\].*deep' /sys/power/mem_sleep; then
        warn "System still defaults to s2idle"
        warn "If resume problems continue, consider testing mem_sleep_default=deep"
    fi

    ok "NVIDIA suspend configuration updated"
    info "Rebuild initramfs if your install flow does not do it automatically, then reboot"
}

for arg in "$@"; do
    case "$arg" in
        --check)
            MODE="check"
            ;;
        --apply)
            MODE="apply"
            ;;
        --auto)
            MODE="auto"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $arg"
            usage
            exit 1
            ;;
    esac
done

case "$MODE" in
    check)
        check_state
        ;;
    apply)
        check_state
        apply_state
        ;;
    auto)
        if have_nvidia_stack; then
            check_state
            apply_state
        else
            info "NVIDIA stack not detected; skipping suspend configuration"
        fi
        ;;
esac