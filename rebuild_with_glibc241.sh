#!/bin/bash

echo "Rebuilding kernel with glibc 2.41 compatibility..."
echo ""

cd /home/bob/buildstuff/BobZKernel/builds/linux-6.18

# Set environment to prefer dynamic linking
export LDFLAGS="-lzstd -lz"
export LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export CFLAGS="-march=native -O2"

# Clean previous build
make clean 2>&1 | tail -3

echo ""
echo "Starting kernel build..."
echo "This will take a while..."
echo ""

# Run the build
make -j$(nproc) 2>&1 | tee /home/bob/buildstuff/BobZKernel/build_glibc2.41_retry.log

