#!/bin/bash

echo "Building RSEQ Mutex Wrapper..."
echo ""

# Build the shared library
gcc -shared -fPIC -O2 -DRSEQ_SIG=0x53053053 \
    -o librseq_mutex_wrapper.so \
    rseq_mutex_wrapper.c \
    -ldl -lpthread

if [ $? -eq 0 ]; then
    echo "✓ librseq_mutex_wrapper.so built successfully"
else
    echo "✗ Build failed"
    exit 1
fi

# Build the test program
gcc -O2 -pthread -o test_mutex_contention test_mutex_contention.c

if [ $? -eq 0 ]; then
    echo "✓ test_mutex_contention built successfully"
else
    echo "✗ Build failed"
    exit 1
fi

echo ""
echo "Build complete!"
echo ""
echo "To test:"
echo "  # Without wrapper (baseline):"
echo "  ./test_mutex_contention"
echo ""
echo "  # With RSEQ wrapper (should show grants!):"
echo "  LD_PRELOAD=./librseq_mutex_wrapper.so ./test_mutex_contention"
