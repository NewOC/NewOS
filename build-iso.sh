#!/bin/bash
set -e

# Ensure base image exists
if [ ! -f NewOS.img ]; then
    echo "NewOS.img not found. Running './build-img.sh'..."
    ./build-img.sh
fi

# Build Tool
echo "Building ISO Tool..."
if [ ! -f tools/mkiso ]; then
    zig build-exe tools/mkiso.zig -femit-bin=tools/mkiso
fi

# Run Tool
echo "Creating NewOS.iso..."
./tools/mkiso NewOS.img NewOS.iso

echo "Success! Created NewOS.iso"
