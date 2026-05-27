#!/bin/bash
# Test nvidia PM suspend path via procfs WITHOUT actually suspending the system.
# This triggers nv_set_system_power_state() which is the same path the PM notifier uses.
# We can watch dmesg in real-time from another terminal.
#
# Usage: sudo ./test-nvidia-pm-procfs.sh
#
# In another terminal, run: sudo dmesg -w | grep BOBZDBG

set -euo pipefail

echo "=== Testing nvidia PM callbacks via /proc/driver/nvidia/suspend ==="
echo ""
echo "This writes 'suspend' then 'resume' to /proc/driver/nvidia/suspend"
echo "It exercises the same PM code path as system suspend."
echo ""
echo "In another terminal, run:"
echo "  sudo dmesg -w | grep BOBZDBG"
echo ""
echo "Press Enter to proceed (or Ctrl-C to abort)..."
read -r

echo "[$(date)] Writing 'suspend' to /proc/driver/nvidia/suspend..."
echo "suspend" > /proc/driver/nvidia/suspend
status=$?
echo "[$(date)] Write returned status: $status"

# Always resume on exit so we never leave the GPU stuck in a suspended state.
resume_gpu() {
    echo ""
    echo "[$(date)] Writing 'resume' to /proc/driver/nvidia/suspend..."
    echo "resume" > /proc/driver/nvidia/suspend || true
}
trap resume_gpu EXIT

echo ""
echo "[$(date)] Checking debug messages..."
# Non-fatal — `set -euo pipefail` + a grep with no matches would otherwise
# abort here, before the resume write runs.
dmesg | grep BOBZDBG || echo "  (no BOBZDBG messages yet)"

# Explicitly resume (trap also covers the early-exit case)
resume_gpu
trap - EXIT
status=$?
echo "[$(date)] Resume returned status: $status"

echo ""
echo "[$(date)] Full debug trace:"
dmesg | grep BOBZDBG || echo "  (no BOBZDBG messages)"

echo ""
echo "=== Done ==="
