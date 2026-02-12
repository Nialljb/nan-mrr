#!/bin/bash
#
# Alternative Docker build script (can be converted to Singularity later)
#

set -e

IMAGE_NAME="mrr"
IMAGE_TAG="1.0.0"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building MRR Docker image..."
echo "Image: $FULL_IMAGE_NAME"

# Build the Docker image
docker build -t "$FULL_IMAGE_NAME" .

if [[ $? -eq 0 ]]; then
    echo "Successfully built Docker image: $FULL_IMAGE_NAME"
    echo "Converting to Singularity..."
    
    # Convert to Singularity
    singularity build mrr_from_docker.sif "docker-daemon://${FULL_IMAGE_NAME}"
    
    if [[ $? -eq 0 ]]; then
        echo "Successfully converted to Singularity: mrr_from_docker.sif"
    else
        echo "Error: Failed to convert to Singularity"
    fi
else
    echo "Error: Failed to build Docker image"
    exit 1
fi