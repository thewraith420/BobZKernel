#!/bin/bash
# Analyze what's causing RSEQ revocations
# Correlates RSEQ stats with interrupt activity

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}RSEQ Revocation Analysis${NC}"
echo
echo -e "${YELLOW}Capturing baseline...${NC}"

# Get initial stats
INITIAL_REVOKE=$(sudo cat /sys/kernel/debug/rseq/stats | grep "srevok:" | awk '{print $2}')
INITIAL_GPU_IRQ=$(cat /proc/interrupts | grep -i nvidia | awk '{sum=0; for(i=2;i<=NF-3;i++) sum+=$i; print sum}')
INITIAL_TIMER_IRQ=$(cat /proc/interrupts | grep "Local timer" | awk '{sum=0; for(i=2;i<=NF-3;i++) sum+=$i; print sum}')

echo "Initial revocations: $INITIAL_REVOKE"
echo "Initial GPU interrupts: $INITIAL_GPU_IRQ"
echo "Initial timer interrupts: $INITIAL_TIMER_IRQ"
echo
echo -e "${GREEN}Now play ESO for 60 seconds...${NC}"
sleep 60

# Get final stats
FINAL_REVOKE=$(sudo cat /sys/kernel/debug/rseq/stats | grep "srevok:" | awk '{print $2}')
FINAL_GPU_IRQ=$(cat /proc/interrupts | grep -i nvidia | awk '{sum=0; for(i=2;i<=NF-3;i++) sum+=$i; print sum}')
FINAL_TIMER_IRQ=$(cat /proc/interrupts | grep "Local timer" | awk '{sum=0; for(i=2;i<=NF-3;i++) sum+=$i; print sum}')

# Calculate deltas
DELTA_REVOKE=$((FINAL_REVOKE - INITIAL_REVOKE))
DELTA_GPU=$((FINAL_GPU_IRQ - INITIAL_GPU_IRQ))
DELTA_TIMER=$((FINAL_TIMER_IRQ - INITIAL_TIMER_IRQ))

echo
echo -e "${BLUE}Results (60 second sample):${NC}"
echo "  RSEQ revocations: $DELTA_REVOKE"
echo "  GPU interrupts: $DELTA_GPU"
echo "  Timer interrupts: $DELTA_TIMER"
echo

# Rough correlation
if [ $DELTA_GPU -gt 0 ] && [ $DELTA_REVOKE -gt 0 ]; then
    RATIO=$((DELTA_REVOKE * 100 / DELTA_GPU))
    echo -e "${YELLOW}Revocations per 100 GPU interrupts: $RATIO${NC}"

    if [ $RATIO -gt 50 ]; then
        echo -e "${RED}High correlation - GPU driver may be main cause${NC}"
    else
        echo -e "${GREEN}Low correlation - revocations are from multiple sources${NC}"
    fi
fi
