#!/bin/bash
# BobZKernel Benchmark Script
# Run identical benchmarks for kernel comparison

KERNEL=$(uname -r)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
OUTPUT_FILE="$HOME/buildstuff/BobzKernel/benchmarks/${KERNEL}-results.txt"

echo "=========================================="
echo "BobZKernel Benchmark Suite"
echo "=========================================="
echo "Kernel: $KERNEL"
echo "Date: $TIMESTAMP"
echo "Hardware: Lenovo LOQ 15IRH8 (i5-13450HX)"
echo ""
echo "Running benchmarks, please wait..."
echo ""

# Start output file
cat > "$OUTPUT_FILE" << EOF
BobZKernel Benchmark Results
============================
Kernel: $KERNEL
Date: $TIMESTAMP
Hardware: Lenovo LOQ 15IRH8 (i5-13450HX, 8GB RAM, NVMe SSD)
Compiler: $(cat /proc/version | grep -oP '(?<=\()\S+(?=\s)')

EOF

echo "=== CPU Benchmark - Single Thread ===" | tee -a "$OUTPUT_FILE"
sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>&1 | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "=== CPU Benchmark - Multi Thread (10 cores) ===" | tee -a "$OUTPUT_FILE"
sysbench cpu --cpu-max-prime=20000 --threads=10 run 2>&1 | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "=== Memory Benchmark ===" | tee -a "$OUTPUT_FILE"
sysbench memory --memory-total-size=10G --threads=4 run 2>&1 | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "=== Disk I/O Benchmark ===" | tee -a "$OUTPUT_FILE"
echo "Preparing test files..." | tee -a "$OUTPUT_FILE"
sysbench fileio --file-total-size=2G --file-test-mode=seqwr --threads=4 prepare > /dev/null 2>&1
echo "Running sequential write test..." | tee -a "$OUTPUT_FILE"
sysbench fileio --file-total-size=2G --file-test-mode=seqwr --threads=4 run 2>&1 | tee -a "$OUTPUT_FILE"
echo "Cleaning up..." | tee -a "$OUTPUT_FILE"
sysbench fileio --file-total-size=2G cleanup > /dev/null 2>&1
echo "" | tee -a "$OUTPUT_FILE"

# Extract key metrics
echo "=========================================="
echo "Summary of Key Metrics"
echo "=========================================="
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "Quick Stats:"
grep "events per second" "$OUTPUT_FILE" | head -2
grep "transferred" "$OUTPUT_FILE" | grep "MiB/sec" | head -1
grep "written" "$OUTPUT_FILE" | grep "MiB/s"
echo ""
echo "Benchmark complete!"
