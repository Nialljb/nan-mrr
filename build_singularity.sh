#!/bin/bash
#
# Build script for MRR Singularity image
#

set -e

IMAGE_NAME="mrr.sif"
DEF_FILE="mrr.def"

echo "Building MRR Singularity image..."
echo "Definition file: $DEF_FILE"
echo "Output image: $IMAGE_NAME"

# Check if Singularity is available
if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed or not in PATH"
    exit 1
fi

# Check if definition file exists
if [[ ! -f "$DEF_FILE" ]]; then
    echo "Error: Definition file '$DEF_FILE' not found"
    exit 1
fi

# Remove existing image if it exists
if [[ -f "$IMAGE_NAME" ]]; then
    echo "Removing existing image: $IMAGE_NAME"
    rm "$IMAGE_NAME"
fi

# Build the image
echo "Building Singularity image (this may take a while)..."
# Try with fakeroot first, fall back to sudo if needed
if ! singularity build --fakeroot --ignore-fakeroot-command "$IMAGE_NAME" "$DEF_FILE"; then
    echo "Fakeroot build failed, trying with sudo..."
    sudo singularity build "$IMAGE_NAME" "$DEF_FILE"
fi

if [[ $? -eq 0 ]]; then
    echo "Successfully built: $IMAGE_NAME"
    echo "Image size: $(du -h "$IMAGE_NAME" | cut -f1)"
    
    echo "Testing the image..."
    singularity test "$IMAGE_NAME"
    
    if [[ $? -eq 0 ]]; then
        echo "Image test passed!"
        echo ""
        echo "You can now use the image with:"
        echo "  singularity exec $IMAGE_NAME python /app/run_mrr.py --help"
    else
        echo "Warning: Image test failed"
    fi
else
    echo "Error: Failed to build Singularity image"
    exit 1
fi