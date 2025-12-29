# Phase 1 Verification Checklist

Run these commands after rebooting to verify all Phase 1 optimizations are working.

---

## 1. Basic System Check

```bash
# Verify kernel version
uname -r
# Should show: 6.14.0-BobZKernel

# Check if system booted successfully
uptime
```

---

## 2. Network Optimizations

### BBR TCP Congestion Control
```bash
sysctl net.ipv4.tcp_congestion_control
# Expected: net.ipv4.tcp_congestion_control = bbr

sysctl net.ipv4.tcp_available_congestion_control
# Should include: bbr
```

### CAKE QoS Scheduler
```bash
# Check if CAKE module is available
lsmod | grep -i cake || modprobe sch_cake && echo "CAKE loaded"

# Or check if built-in
zcat /proc/config.gz 2>/dev/null | grep CONFIG_NET_SCH_CAKE || \
cat /boot/config-$(uname -r) | grep CONFIG_NET_SCH_CAKE
# Expected: CONFIG_NET_SCH_CAKE=y
```

---

## 3. Memory Management

### ZSWAP
```bash
# Check if ZSWAP is enabled
cat /sys/module/zswap/parameters/enabled
# Expected: Y

# Check ZSWAP compressor
cat /sys/module/zswap/parameters/compressor
# Expected: zstd

# Check ZSWAP allocator
cat /sys/module/zswap/parameters/zpool
# Expected: zsmalloc

# Check ZSWAP stats (after some uptime)
grep -r . /sys/kernel/debug/zswap/ 2>/dev/null | head -10
```

### ZRAM (needs to be set up)
```bash
# Check if ZRAM is available
lsmod | grep zram || echo "ZRAM built-in"

# ZRAM won't be active until we configure it
# (We'll do this in next step)
```

---

## 4. I/O Schedulers

### Check available schedulers
```bash
# For NVMe
cat /sys/block/nvme0n1/queue/scheduler
# Should show: [none] mq-deadline kyber bfq

# BFQ should be available in the list
```

---

## 5. Gaming/QoL Features

### FUTEX2
```bash
# Check kernel config
zcat /proc/config.gz 2>/dev/null | grep CONFIG_FUTEX || \
cat /boot/config-$(uname -r) | grep CONFIG_FUTEX
# Expected: CONFIG_FUTEX=y and CONFIG_FUTEX2=y
```

### PSI (Pressure Stall Information)
```bash
# Check if PSI is available
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io
# Should show pressure statistics (not errors)
```

---

## 6. Quick Performance Test

### Network test (optional)
```bash
# Test download speed to see BBR in action
# You can use speedtest-cli or just notice if downloads feel faster
```

### Memory test
```bash
# Check current memory usage
free -h

# Check swap usage
swapon --show
```

---

## Issues to Watch For

- [ ] System boots successfully
- [ ] NVIDIA drivers loaded (nvidia-smi works)
- [ ] Network connectivity works
- [ ] BBR is active
- [ ] ZSWAP is enabled
- [ ] No kernel panics or errors in dmesg

### Check for errors:
```bash
dmesg | grep -i error | tail -20
dmesg | grep -i fail | tail -20
```

---

## Next Steps After Verification

1. **If everything works:** Set up ZRAM and continue to Phase 2
2. **If there are issues:** Reboot to old kernel and troubleshoot

---

**Quick Check Script:**
```bash
#!/bin/bash
echo "=== Phase 1 Verification ==="
echo ""
echo "Kernel: $(uname -r)"
echo "TCP Congestion: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "ZSWAP Enabled: $(cat /sys/module/zswap/parameters/enabled)"
echo "ZSWAP Compressor: $(cat /sys/module/zswap/parameters/compressor)"
echo "PSI Available: $([ -f /proc/pressure/cpu ] && echo 'Yes' || echo 'No')"
echo "NVMe Scheduler: $(cat /sys/block/nvme0n1/queue/scheduler)"
echo ""
echo "=== Memory Status ==="
free -h
echo ""
echo "=== Swap Status ==="
swapon --show
```

Save this as `verify-phase1.sh` and run it after reboot!
