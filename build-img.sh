#!/bin/bash
set -e

if [ ! -f build/os-image.bin ]; then
    echo "Error: build/os-image.bin not found!"
    echo "Please run './build.sh' first."
    exit 1
fi

echo "Creating NewOS.img..."
cp build/os-image.bin NewOS.img

echo "Success! Created NewOS.img"
