#!/bin/bash
# ESO RSEQ Time Slice Extension Wrapper
# Enables RSEQ slice extension for better frame timing
#
# Usage in Steam:
#   Set launch options to: /path/to/eso-rseq-wrapper.sh %command%

# Enable RSEQ slice extension for this process
# This uses a small helper that calls prctl() before exec'ing the game

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/rseq-enable"

# Build helper if needed
if [[ ! -x "$HELPER" ]]; then
    echo "[RSEQ] Building helper..."
    gcc -o "$HELPER" -x c - << 'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/prctl.h>

#define PR_RSEQ_SLICE_EXTENSION 79
#define PR_RSEQ_SLICE_EXTENSION_SET 2
#define PR_RSEQ_SLICE_EXT_ENABLE 0x01

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    // Enable RSEQ slice extension
    if (prctl(PR_RSEQ_SLICE_EXTENSION, PR_RSEQ_SLICE_EXTENSION_SET,
              PR_RSEQ_SLICE_EXT_ENABLE, 0, 0) == 0) {
        fprintf(stderr, "[RSEQ] Time slice extension enabled\n");
    } else {
        fprintf(stderr, "[RSEQ] Warning: Could not enable slice extension\n");
    }

    // Execute the command
    execvp(argv[1], &argv[1]);
    perror("execvp failed");
    return 1;
}
EOF
    if [[ $? -ne 0 ]]; then
        echo "[RSEQ] Failed to build helper, running without RSEQ"
        exec "$@"
    fi
fi

# Run the game with RSEQ enabled
exec "$HELPER" "$@"
