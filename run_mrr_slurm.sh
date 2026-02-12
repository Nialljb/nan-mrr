#!/bin/bash
#SBATCH --job-name=mrr_processing
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=03:00:00
#SBATCH --output=mrr_%j.out
#SBATCH --error=mrr_%j.err
#
# Example SLURM submission script for MRR processing
#
# Usage: sbatch run_mrr_slurm.sh
#
# Make sure to modify the paths and parameters below for your specific use case
#

# Load Singularity module (adjust for your HPC environment)
module load singularity

# Define paths - MODIFY THESE FOR YOUR ENVIRONMENT
MRR_IMAGE="/home/${USER}/images/mrr.sif"
INPUT_DIR="/data/bids_dataset"
OUTPUT_DIR="/results/mrr_output"
WORK_DIR="/tmp/mrr_work_${SLURM_JOB_ID}"

# Subject and session information - MODIFY FOR YOUR DATA
SUBJECT="01"
SESSION="01"

# Input file path (adjust pattern as needed)
INPUT_FILE="${INPUT_DIR}/sub-${SUBJECT}/ses-${SESSION}/anat/sub-${SUBJECT}_ses-${SESSION}_T2w.nii.gz"

# Create output directory
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${WORK_DIR}"

echo "Starting MRR processing..."
echo "Job ID: ${SLURM_JOB_ID}"
echo "Subject: ${SUBJECT}"
echo "Session: ${SESSION}"
echo "Input: ${INPUT_FILE}"
echo "Output: ${OUTPUT_DIR}"
echo "Work directory: ${WORK_DIR}"

# Check if input file exists
if [[ ! -f "${INPUT_FILE}" ]]; then
    echo "Error: Input file not found: ${INPUT_FILE}"
    exit 1
fi

# Run MRR processing
singularity exec \
    --bind "${INPUT_DIR}:/input:ro" \
    --bind "${OUTPUT_DIR}:/output:rw" \
    --bind "${WORK_DIR}:/tmp/mrr_work:rw" \
    "${MRR_IMAGE}" \
    python /app/run_mrr.py \
        --input "${INPUT_FILE}" \
        --output /output \
        --work-dir /tmp/mrr_work \
        --subject "${SUBJECT}" \
        --session "${SESSION}" \
        --debug

# Check if processing was successful
if [[ $? -eq 0 ]]; then
    echo "MRR processing completed successfully!"
    echo "Output files:"
    ls -la "${OUTPUT_DIR}/"
else
    echo "Error: MRR processing failed"
    exit 1
fi

# Clean up work directory
rm -rf "${WORK_DIR}"

echo "Job completed!"