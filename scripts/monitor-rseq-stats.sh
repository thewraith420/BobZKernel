#!/bin/bash
# RSEQ Statistics Monitor
# Logs RSEQ stats over time to analyze performance during gameplay

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DURATION=${1:-300}  # Default 5 minutes (300 seconds)
INTERVAL=${2:-5}    # Sample every 5 seconds
LOG_FILE="/tmp/rseq-stats-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         RSEQ Statistics Monitor                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Duration: ${DURATION}s ($(($DURATION / 60)) minutes)${NC}"
echo -e "${GREEN}Sample interval: ${INTERVAL}s${NC}"
echo -e "${GREEN}Log file: $LOG_FILE${NC}"
echo
echo -e "${YELLOW}Start your gameplay now! Monitoring begins in 3 seconds...${NC}"
sleep 3

# Get initial stats
echo "timestamp,sgrant,srevok,syield,sexpir,sabort,yield_rate,revoke_rate,expire_rate" > "$LOG_FILE"

get_stat() {
    sudo cat /sys/kernel/debug/rseq/stats | grep "^$1:" | awk '{print $2}'
}

# Record initial values
INITIAL_GRANT=$(get_stat sgrant)
INITIAL_REVOKE=$(get_stat srevok)
INITIAL_YIELD=$(get_stat syield)
INITIAL_EXPIRE=$(get_stat sexpir)
INITIAL_ABORT=$(get_stat sabort)

echo -e "${GREEN}Initial stats captured. Monitoring...${NC}"
echo

# Monitor loop
END_TIME=$(($(date +%s) + $DURATION))
SAMPLES=0

while [ $(date +%s) -lt $END_TIME ]; do
    TIMESTAMP=$(date +%s)
    GRANT=$(get_stat sgrant)
    REVOKE=$(get_stat srevok)
    YIELD=$(get_stat syield)
    EXPIRE=$(get_stat sexpir)
    ABORT=$(get_stat sabort)

    # Calculate deltas from initial
    DELTA_GRANT=$((GRANT - INITIAL_GRANT))
    DELTA_REVOKE=$((REVOKE - INITIAL_REVOKE))
    DELTA_YIELD=$((YIELD - INITIAL_YIELD))
    DELTA_EXPIRE=$((EXPIRE - INITIAL_EXPIRE))
    DELTA_ABORT=$((ABORT - INITIAL_ABORT))

    # Calculate percentages (avoid division by zero)
    if [ $DELTA_GRANT -gt 0 ]; then
        YIELD_RATE=$((DELTA_YIELD * 100 / DELTA_GRANT))
        REVOKE_RATE=$((DELTA_REVOKE * 100 / DELTA_GRANT))
        EXPIRE_RATE=$((DELTA_EXPIRE * 100 / DELTA_GRANT))
    else
        YIELD_RATE=0
        REVOKE_RATE=0
        EXPIRE_RATE=0
    fi

    # Log to file
    echo "$TIMESTAMP,$DELTA_GRANT,$DELTA_REVOKE,$DELTA_YIELD,$DELTA_EXPIRE,$DELTA_ABORT,$YIELD_RATE,$REVOKE_RATE,$EXPIRE_RATE" >> "$LOG_FILE"

    # Display current stats
    REMAINING=$((END_TIME - TIMESTAMP))
    SAMPLES=$((SAMPLES + 1))

    echo -e "${BLUE}[Sample $SAMPLES] Time remaining: ${REMAINING}s${NC}"
    echo -e "  Grants: ${DELTA_GRANT}  Yields: ${DELTA_YIELD} (${YIELD_RATE}%)  Revokes: ${DELTA_REVOKE} (${REVOKE_RATE}%)  Expires: ${DELTA_EXPIRE} (${EXPIRE_RATE}%)"

    if [ $DELTA_YIELD -gt $DELTA_REVOKE ]; then
        echo -e "  ${GREEN}✓ Yields > Revokes - Excellent tuning!${NC}"
    elif [ $DELTA_REVOKE -gt $DELTA_YIELD ]; then
        echo -e "  ${YELLOW}⚠ Revokes > Yields - Room for improvement${NC}"
    else
        echo -e "  ${BLUE}= Balanced${NC}"
    fi
    echo

    sleep $INTERVAL
done

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Monitoring Complete!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo

# Calculate final averages
FINAL_GRANT=$(get_stat sgrant)
FINAL_REVOKE=$(get_stat srevok)
FINAL_YIELD=$(get_stat syield)
FINAL_EXPIRE=$(get_stat sexpir)
FINAL_ABORT=$(get_stat sabort)

TOTAL_GRANT=$((FINAL_GRANT - INITIAL_GRANT))
TOTAL_REVOKE=$((FINAL_REVOKE - INITIAL_REVOKE))
TOTAL_YIELD=$((FINAL_YIELD - INITIAL_YIELD))
TOTAL_EXPIRE=$((FINAL_EXPIRE - INITIAL_EXPIRE))
TOTAL_ABORT=$((FINAL_ABORT - INITIAL_ABORT))

if [ $TOTAL_GRANT -gt 0 ]; then
    AVG_YIELD=$((TOTAL_YIELD * 100 / TOTAL_GRANT))
    AVG_REVOKE=$((TOTAL_REVOKE * 100 / TOTAL_GRANT))
    AVG_EXPIRE=$((TOTAL_EXPIRE * 100 / TOTAL_GRANT))
    AVG_ABORT=$((TOTAL_ABORT * 100 / TOTAL_GRANT))
else
    AVG_YIELD=0
    AVG_REVOKE=0
    AVG_EXPIRE=0
    AVG_ABORT=0
fi

echo -e "${BLUE}Session Summary (${DURATION}s / $(($DURATION / 60)) minutes):${NC}"
echo -e "  Total Grants: ${TOTAL_GRANT}"
echo -e "  Total Yields: ${TOTAL_YIELD} (${AVG_YIELD}%)"
echo -e "  Total Revokes: ${TOTAL_REVOKE} (${AVG_REVOKE}%)"
echo -e "  Total Expires: ${TOTAL_EXPIRE} (${AVG_EXPIRE}%)"
echo -e "  Total Aborts: ${TOTAL_ABORT} (${AVG_ABORT}%)"
echo

# Performance assessment
echo -e "${BLUE}Performance Assessment:${NC}"
if [ $AVG_YIELD -gt $AVG_REVOKE ]; then
    MARGIN=$((AVG_YIELD - AVG_REVOKE))
    echo -e "${GREEN}✓ EXCELLENT: Yields exceed revokes by ${MARGIN}%${NC}"
    echo -e "${GREEN}  Your kernel is well-tuned for this workload!${NC}"
elif [ $AVG_REVOKE -gt $AVG_YIELD ]; then
    MARGIN=$((AVG_REVOKE - AVG_YIELD))
    echo -e "${YELLOW}⚠ GOOD: Revokes exceed yields by ${MARGIN}%${NC}"
    echo -e "${YELLOW}  Room for improvement - consider tuning slice duration${NC}"

    # Suggest tuning
    CURRENT_SLICE=$(cat /proc/sys/kernel/rseq_slice_extension_nsec)
    if [ $AVG_REVOKE -gt 40 ]; then
        SUGGESTED=$((CURRENT_SLICE + 5000))
        echo -e "${YELLOW}  Suggestion: Try increasing slice to ${SUGGESTED}ns${NC}"
    fi
else
    echo -e "${BLUE}= BALANCED: Yields equal revokes${NC}"
    echo -e "${BLUE}  System is in equilibrium${NC}"
fi

echo
echo -e "${GREEN}Detailed log saved to: $LOG_FILE${NC}"
echo -e "${BLUE}Analyze with: cat $LOG_FILE${NC}"
echo

# Generate quick analysis
echo -e "${BLUE}Quick Analysis:${NC}"
echo -e "  Grant rate: $((TOTAL_GRANT / (DURATION / 60))) grants/min"
if [ $TOTAL_GRANT -gt 0 ]; then
    echo -e "  Avg grants/sample: $((TOTAL_GRANT / SAMPLES))"
fi
echo
