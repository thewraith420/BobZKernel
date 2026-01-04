#!/bin/bash
# ZRAM Setup Script for BobZKernel
# Creates compressed swap in RAM for fast everyday use

set -e

# Configuration
ZRAM_SIZE="4G"        # 4GB compressed ZRAM (will compress to ~1-2GB actual RAM)
ZRAM_PRIORITY=100     # Higher priority than disk swap (use ZRAM first)
ZRAM_ALGORITHM="zstd" # Fast compression

# Load zram module
modprobe zram

# Configure ZRAM device
echo $ZRAM_ALGORITHM > /sys/block/zram0/comp_algorithm
echo $ZRAM_SIZE > /sys/block/zram0/disksize

# Format as swap
mkswap /dev/zram0

# Enable with high priority (so it's used before disk swap)
swapon -p $ZRAM_PRIORITY /dev/zram0

echo "ZRAM enabled: ${ZRAM_SIZE} compressed swap at priority ${ZRAM_PRIORITY}"
