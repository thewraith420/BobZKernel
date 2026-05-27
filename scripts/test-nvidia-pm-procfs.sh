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

echo ""
echo "[$(date)] Checking debug messages..."
dmesg | grep BOBZDBG

echo ""
echo "[$(date)] Writing 'resume' to /proc/driver/nvidia/suspend..."
echo "resume" > /proc/driver/nvidia/suspend
status=$?
echo "[$(date)] Resume returned status: $status"

echo ""
echo "[$(date)] Full debug trace:"
dmesg | grep BOBZDBG

echo ""
echo "=== Done ==="
