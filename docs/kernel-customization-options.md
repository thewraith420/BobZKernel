# Kernel Customization Options for BobZKernel

Advanced kernel features and optimizations you can add to your custom kernel.

---

## 🚀 Performance Enhancements

### 1. **CPU Schedulers - Replace Default EEVDF**

**Current:** EEVDF (Earliest Eligible Virtual Deadline First) - Default in 6.14
**Options:**

#### a) **BORE (Burst-Oriented Response Enhancer)**
- Improves desktop responsiveness
- Better handling of bursty workloads
- Popular among Arch/Gentoo users
- Requires patch: https://github.com/firelzrd/bore-scheduler

**Pros:** Noticeably better desktop feel, faster app launches
**Cons:** Requires patching kernel source
**Use case:** Desktop/laptop users who want snappier response

#### b) **BMQ/PDS (BitMap Queue / Priority and Deadline based Scheduler)**
- Alternative scheduler by Alfred Chen
- Lower overhead than CFS
- Better for low-core-count systems
- Requires patch: https://gitlab.com/alfredchen/linux-prjc

**Pros:** Lower latency, simpler code
**Cons:** May not scale as well on high-core-count systems
**Use case:** 4-12 core systems (perfect for your 12-core i5-13450HX)

---

### 2. **Compiler Optimizations**

**Current:** `-O2` optimization, no LTO

#### a) **Enable LTO (Link Time Optimization)**
```
CONFIG_LTO_CLANG_FULL=y  # or CONFIG_LTO_CLANG_THIN=y
```
**Pros:** 5-10% performance gain, smaller kernel
**Cons:** Significantly longer compile time (30-50% more), requires Clang
**Benefit:** Worth it for production kernel

#### b) **-O3 Optimization**
```
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3=y
```
**Pros:** Potentially faster code
**Cons:** Larger kernel, may introduce instability
**Benefit:** Marginal gains, not recommended

#### c) **CPU-Specific Optimization (March=native)**
- Compile with `-march=native` to use all CPU features
- Requires kernel patch or manual Makefile edit
**Pros:** Uses AVX2, AVX-512, all Intel extensions
**Cons:** Kernel only works on similar CPUs (not portable)
**Benefit:** 2-5% performance boost

---

### 3. **Kernel Timer Frequency (HZ)**

**Current:** `CONFIG_HZ=1000` (1ms tick)
**Options:**
- `CONFIG_HZ=300` - Balanced (desktop default)
- `CONFIG_HZ=500` - Good middle ground
- `CONFIG_HZ=1000` - **Your current setting** - Best for low latency
- `CONFIG_HZ=2000` - Extreme low latency (gaming, audio production)

**Recommendation:** Keep at 1000 for desktop, or try 500 for better battery

---

### 4. **Preemption Model**

**Current:** `CONFIG_PREEMPT_DYNAMIC` (good!)

You're already using the best option - allows runtime switching between preemption modes via kernel parameter `preempt=`.

**Alternative:** `CONFIG_PREEMPT=y` (Full preemption)
- Lowest latency
- Best for desktop/audio work
- Slight throughput penalty

**Current setting is optimal** - dynamic gives you flexibility

---

### 5. **TCP Congestion Control**

**Current:** `CONFIG_TCP_CONG_CUBIC` (default)
**Better Options:**

#### a) **BBR (Bottleneck Bandwidth and RTT)**
```
CONFIG_TCP_CONG_BBR=y
```
**Pros:** Much better performance on high-latency networks (WiFi, cellular)
**Cons:** None really
**Benefit:** 2-4x faster downloads on congested networks

#### b) **BBRv3** (Latest version)
- Requires out-of-tree patch
- Google uses this for YouTube
**Benefit:** Best-in-class TCP performance

---

### 6. **I/O Schedulers**

**Current:** Default (mq-deadline for SATA, none for NVMe)
**Options:**

#### a) **BFQ (Budget Fair Queueing)** - Already available
```
CONFIG_BFQ_GROUP_IOSCHED=y
```
**Use:** Better for interactive systems, prevents I/O starvation
**Enable with:** `echo bfq | sudo tee /sys/block/sda/queue/scheduler`

#### b) **Kyber** - Already available
**Use:** Low-latency I/O scheduling
**Better for:** NVMe drives under heavy random I/O

---

## 🔋 Battery Life Improvements

### 7. **ZRAM with ZSTD Compression**

**Current:** `CONFIG_ZRAM=m` (module), default compression: lzo-rle
**Improvement:**

Enable and configure ZRAM for compressed swap in RAM:
```
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_ZSTD=y
```

**Setup:**
```bash
# Create ZRAM swap (add to systemd service)
modprobe zram
echo zstd > /sys/block/zram0/comp_algorithm
echo 4G > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 10 /dev/zram0
```

**Benefit:** Effectively increases RAM, reduces SSD writes, improves battery

---

### 8. **ZSWAP with ZSTD**

**Current:** `CONFIG_ZSWAP=y` but disabled by default, uses LZO
**Improvement:**

```
CONFIG_ZSWAP_DEFAULT_ON=y
CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD=y
CONFIG_ZSWAP_ZPOOL_DEFAULT_ZSMALLOC=y
```

Add to GRUB: `zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold`

**Benefit:** Compressed swap cache, reduces swapping, better battery

---

### 9. **Intel P-State Enhancements**

**Current:** Using intel_pstate driver

Enable additional tuning:
```
CONFIG_X86_INTEL_PSTATE=y
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y  # or PERFORMANCE
```

Add to GRUB: `intel_pstate=active`

**Benefit:** Better CPU frequency management, faster response

---

## 🎮 Gaming & Low Latency

### 10. **Fsync/Futex2 (Wine/Proton Performance)**

**Current:** Should be enabled in 6.14

Verify:
```
CONFIG_FUTEX=y
CONFIG_FUTEX2=y
```

**Benefit:** Much better Windows game performance via Proton/Wine

---

### 11. **Kernel Boot Optimization**

Already done with:
- Built-in NVMe drivers ✅
- Minimal initramfs ✅
- Silent boot ✅

**Additional:**

Enable kernel compression for faster loading:
```
CONFIG_KERNEL_ZSTD=y  # Already enabled ✅
```

Consider: Early KMS for instant graphical boot
```
# Already in GRUB:
i915.modeset=1  # or add to initramfs
```

---

### 12. **Advanced Networking**

#### a) **Cake (Common Applications Kept Enhanced) QoS**
```
CONFIG_NET_SCH_CAKE=y
```
**Use:** Smart queue management for bufferbloat
**Benefit:** Lower latency during uploads/downloads

#### b) **XDP (eXpress Data Path)**
```
CONFIG_XDP_SOCKETS=y
CONFIG_BPF_JIT_ALWAYS_ON=y
```
**Benefit:** Ultra-low latency networking for gaming

---

## 🔧 Quality of Life

### 13. **Kernel Same-Page Merging (KSM)**

**Current:** Likely enabled
```
CONFIG_KSM=y
```

Enable with:
```bash
echo 1 | sudo tee /sys/kernel/mm/ksm/run
```

**Benefit:** Deduplicates identical memory pages, saves RAM

---

### 14. **Transparent Huge Pages (THP)**

**Current:** Probably enabled
```
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y
```

**Benefit:** Better memory performance for large applications

---

### 15. **Audio: Low Latency Timer**

```
CONFIG_SND_HRTIMER=y
```

**Benefit:** Better audio timing for music production

---

### 16. **Custom Kernel Local Version**

Currently: `CONFIG_LOCALVERSION=""`

Set to: `CONFIG_LOCALVERSION="-BobZKernel"`

Shows as: `6.14.0-BobZKernel` everywhere (already using via LOCALVERSION env var)

Make it permanent in config file!

---

### 17. **Kernel Module Signing**

```
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_ALL=y
```

**Pros:** Enhanced security
**Cons:** More complex build process
**Use case:** Secure boot environments

---

### 18. **Pressure Stall Information (PSI)**

**Current:** Probably enabled
```
CONFIG_PSI=y
```

**Benefit:** Allows monitoring system pressure (CPU, memory, I/O)
**Use with:** `systemd-oomd` for better OOM handling

---

## 🌟 Exotic/Experimental

### 19. **CachyOS Optimizations**

CachyOS maintains a comprehensive patch set:
- BORE scheduler
- BBRv3
- Auto CPU optimization
- Many performance patches

**Source:** https://github.com/CachyOS/linux-cachyos

**Benefit:** Best-of-breed performance patches

---

### 20. **Kernel Live Patching**

```
CONFIG_LIVEPATCH=y
```

**Benefit:** Apply security patches without rebooting
**Use case:** Servers, but cool for desktop too

---

### 21. **Real-Time Kernel (PREEMPT_RT)**

```
CONFIG_PREEMPT_RT=y
```

**Requires:** RT patch from kernel.org
**Benefit:** Guaranteed low latency for audio production, robotics
**Cons:** Lower overall throughput

---

## 📊 Recommended Changes for Your System

### Quick Wins (Low Risk, High Reward):

1. **Enable BBR TCP congestion control** - Better network performance
2. **Setup ZRAM with ZSTD** - Effectively more RAM, less swap
3. **Enable ZSWAP with ZSTD** - Better memory management
4. **BFQ I/O scheduler** - Smoother multitasking
5. **CAKE qdisc** - Lower network latency

### Medium Effort (Moderate Complexity):

6. **LTO with Clang** - Faster kernel, longer compile
7. **CPU-specific optimization** - march=native
8. **BORE scheduler patch** - Better desktop responsiveness

### Advanced (For Enthusiasts):

9. **CachyOS patch set** - All-in-one performance
10. **BBRv3 TCP** - Best network performance
11. **Real-time kernel** - If doing audio production

---

## 🎯 My Recommendations for You

Based on your Lenovo LOQ 15IRH8 (i5-13450HX, 8GB RAM, gaming laptop):

### Priority 1 - Memory Management:
- **Enable ZRAM** - You only have 8GB, this will help a lot
- **Enable ZSWAP with ZSTD** - Better than traditional swap
- **Enable KSM** - Saves RAM

### Priority 2 - Networking:
- **BBR TCP congestion control** - Faster downloads/gaming
- **CAKE qdisc** - Lower latency

### Priority 3 - Responsiveness:
- **BORE scheduler** - Snappier desktop
- **BFQ I/O scheduler** - Smoother under load

### Priority 4 - Advanced:
- **LTO compilation** - Performance boost
- **march=native** - Use all your CPU features

Would you like me to help implement any of these?
