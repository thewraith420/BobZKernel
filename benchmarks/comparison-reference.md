# Benchmark Comparison Reference

## Your Hardware: i5-13450HX

### Industry Standard Scores (Stock Kernel)

**Geekbench 6 Average:**
- Single-core: 2,417 points
- Multi-core: 12,684 points
- Source: https://browser.geekbench.com/processors/intel-core-i5-13450hx

**PassMark CPU Mark:**
- Overall Score: 24,859 points
- Ranking: #658 out of 5,510 CPUs (top 12%)
- Source: https://www.cpubenchmark.net/cpu.php?cpu=Intel+Core+i5-13450HX&id=5483

**Cinebench R23:**
- Multi-core: ~12,000-13,000 pts (typical)
- Single-core: ~1,700-1,800 pts (typical)

---

## Your BobZKernel Results

**Sysbench CPU (6.14.0-BobZKernel LTO Full):**
- Single-thread: 693.52 events/sec
- Multi-thread (10 cores): 5,620.57 events/sec
- Scaling efficiency: 81%

**Sysbench Memory:**
- Transfer rate: 4,328.23 MiB/sec

**Sysbench Disk I/O:**
- Sequential write: 534.52 MiB/sec

---

## Comparison Data (Other CPUs)

**Intel i5-9400F (6-core, older gen):**
- Sysbench single: 544.76 events/sec
- **Your advantage: +27%**

**Generic cloud servers:**
- Sysbench single: ~495 events/sec
- **Your advantage: +40%**

**Intel i5-13500 (14-core, desktop):**
- Geekbench 6 single: ~2,600 pts
- Geekbench 6 multi: ~15,000 pts

---

## How to Compare Your Results

### Option 1: Run Geekbench 6 (Recommended)
```bash
# Download from: https://www.geekbench.com/download/linux/
wget https://cdn.geekbench.com/Geekbench-6.3.0-Linux.tar.gz
tar xf Geekbench-6.3.0-Linux.tar.gz
cd Geekbench-6.3.0-Linux
./geekbench6
```

Then compare your score to the average 2,417 (single) / 12,684 (multi)

### Option 2: Phoronix Test Suite
```bash
sudo apt install phoronix-test-suite
phoronix-test-suite benchmark pts/build-linux-kernel
```

Submits to OpenBenchmarking.org where you can compare against other i5-13450HX results

### Option 3: 7-Zip Benchmark (Quick & Easy)
```bash
sudo apt install p7zip-full
7z b
```

Real-world compression benchmark, easy to compare

### Option 4: UnixBench
```bash
sudo apt install unixbench
unixbench
```

Classic Unix performance suite with composite score

---

## Expected Performance vs Stock Kernel

**Your optimizations should give:**
- march=native: +2-5%
- LTO Full: +5-10%
- CachyOS patches: +2-5%
- **Total: +10-20% vs stock kernel**

**If running Geekbench, expect:**
- Single-core: 2,540-2,900 pts (vs 2,417 avg)
- Multi-core: 13,350-15,200 pts (vs 12,684 avg)

---

## Sources

- [Geekbench Browser - i5-13450HX](https://browser.geekbench.com/processors/intel-core-i5-13450hx)
- [PassMark CPU Benchmark](https://www.cpubenchmark.net/cpu.php?cpu=Intel+Core+i5-13450HX&id=5483)
- [NotebookCheck Benchmarks](https://www.notebookcheck.net/Intel-Core-i5-13450HX-Processor-Benchmarks-and-Specs.677231.0.html)
- [OpenBenchmarking.org](https://openbenchmarking.org/s/Intel+Core+i5-13450HX)
- [Sysbench Usage Guide](https://www.simplified.guide/linux/cpu-benchmark)
- [Evaluating Performance with Sysbench](https://www.vpsbenchmarks.com/posts/evaluating_cloud_server_performance_with_sysbench)

---

## Quick Comparison Commands

To re-run your benchmarks for future comparison:
```bash
# CPU single-thread
sysbench cpu --cpu-max-prime=20000 --threads=1 run

# CPU multi-thread
sysbench cpu --cpu-max-prime=20000 --threads=10 run

# Memory
sysbench memory --memory-total-size=10G --threads=4 run

# Disk I/O
sysbench fileio --file-total-size=2G --file-test-mode=seqwr --threads=4 prepare
sysbench fileio --file-total-size=2G --file-test-mode=seqwr --threads=4 run
sysbench fileio --file-total-size=2G cleanup
```
