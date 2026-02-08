#!/bin/bash
# TCMalloc + RSEQ Test Script
# Use this to test if TCMalloc with RSEQ slice extension improves game performance

set -e

TCMALLOC_LIB="/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4"

echo "=== TCMalloc + RSEQ Slice Extension Test ==="
echo

# Check if TCMalloc is installed
if [ ! -f "$TCMALLOC_LIB" ]; then
    echo "ERROR: TCMalloc not found at $TCMALLOC_LIB"
    echo "Install with: sudo apt install libtcmalloc-minimal4t64"
    exit 1
fi

# Check RSEQ sysctl
if [ ! -f /proc/sys/kernel/rseq_slice_extension_nsec ]; then
    echo "WARNING: RSEQ slice extension sysctl not found"
    echo "Make sure you're running BobZKernel 6.18.9+"
else
    RSEQ_VALUE=$(cat /proc/sys/kernel/rseq_slice_extension_nsec)
    echo "✓ RSEQ slice extension enabled: ${RSEQ_VALUE}ns"
fi

echo "✓ TCMalloc found: $TCMALLOC_LIB"
echo

cat << 'EOF'
=== How to Use with Steam Games ===

1. In Steam, right-click a game → Properties → General
2. In "Launch Options", add ONE of these:

   For 64-bit games (most modern games):
   LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 %command%

   For 32-bit games (older games):
   LD_PRELOAD=/usr/lib/i386-linux-gnu/libtcmalloc_minimal.so.4 %command%

3. Launch the game normally through Steam

=== What This Does ===

- Replaces the game's default memory allocator with TCMalloc
- TCMalloc automatically uses RSEQ slice extension for per-CPU caches
- Should reduce memory allocation overhead and improve frame pacing
- Most beneficial for games with many small allocations

=== Testing Tips ===

1. Test WITHOUT TCMalloc first - note FPS, frame times, stuttering
2. Add the launch option and test WITH TCMalloc
3. Compare results - look for:
   - Higher/more stable FPS
   - Better frame pacing (less stuttering)
   - Reduced CPU usage during gameplay

4. If no improvement or game crashes, remove the launch option

=== Monitoring RSEQ Usage ===

While playing, open another terminal and run:
  watch -n 1 'cat /proc/sys/kernel/rseq_slice_extension_nsec'

You can adjust the extension time:
  echo 50000 | sudo tee /proc/sys/kernel/rseq_slice_extension_nsec

Higher = more CPU time for critical sections (may help or hurt depending on game)
Default = 30000ns (30 microseconds)

=== Recommended Test Games ===

Best candidates:
- CPU-bound games (strategy, simulation)
- Games with many NPCs/objects
- Games known for stuttering issues

Not recommended:
- GPU-bound games (limited benefit)
- Games with anti-cheat (may conflict)

EOF

echo
echo "=== Current RSEQ Configuration ==="
if [ -f /proc/sys/kernel/rseq_slice_extension_nsec ]; then
    echo "Extension time: $(cat /proc/sys/kernel/rseq_slice_extension_nsec)ns"
else
    echo "RSEQ not available (check kernel version)"
fi

echo
echo "Ready to test! Add the launch option to your Steam game and give it a try."
