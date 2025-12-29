#!/bin/bash
# Detached BobZKernel Build Script
# Runs the kernel build in a detached screen session

set -e

echo "=== Detached BobZKernel Build ==="
echo "Starting build in detached screen session..."

# Check if screen is available
if ! command -v screen &> /dev/null; then
    echo "Installing screen..."
    sudo apt update && sudo apt install -y screen
fi

# Create a unique session name
SESSION_NAME="kernel-build-$(date +%s)"

echo "Screen session: $SESSION_NAME"
echo "To attach: screen -r $SESSION_NAME"
echo "To detach: Ctrl+A, D"
echo ""

# Start the build in a detached screen session
screen -dmS "$SESSION_NAME" bash -c "
cd /home/bob/buildstuff/KernelDev
echo '=== Starting BobZKernel Build ==='
echo 'Session: $SESSION_NAME'
echo 'Time: $(date)'
echo ''
./scripts/build-kernel.sh
echo ''
echo '=== Build Complete ==='
echo 'Session: $SESSION_NAME'
echo 'Time: $(date)'
echo 'Press Enter to exit...'
read
"

echo "Build started in background screen session: $SESSION_NAME"
echo ""
echo "Commands:"
echo "  Attach: screen -r $SESSION_NAME"
echo "  List sessions: screen -ls"
echo "  Kill session: screen -S $SESSION_NAME -X quit"
echo ""
echo "The build will continue even if you close VS Code!"