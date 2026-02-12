#!/bin/bash
#
# Run script for MRR (Multi-Resolution Registration) Singularity container.
# Refactored from flywheel/ciso Gear for HPC/SLURM usage.
#
# Authorship: Niall Bourke
#
# https://wiki.mouseimaging.ca/display/MICePub/Image+registration+and+ANTs+tools
##############################################################################

# Source FSL configuration
if [[ -f "$FSLDIR/etc/fslconf/fsl.sh" ]]; then
    source $FSLDIR/etc/fslconf/fsl.sh
else
    echo "Warning: FSL configuration not found at $FSLDIR/etc/fslconf/fsl.sh"
fi

# Define directory names and containers using environment variables
CONTAINER='[mrr-singularity]'
work="${MRR_WORK_DIR:-/tmp/mrr_work}"
output_dir="${MRR_OUTPUT_DIR:-/output}"
templates_dir="${MRR_TEMPLATES_DIR:-/app/templates}"

# Ensure directories exist
mkdir -p "${work}"
mkdir -p "${output_dir}"

# Get parameters from command line arguments (backward compatibility)
sub=${1:-$MRR_SUBJECT}
ses=${2:-$MRR_SESSION}
mod=${3:-$MRR_MODALITY}

echo "Subject is: $sub"
echo "Session is: $ses"
echo "Modality is: $mod"

##############################################################################

# Get configuration from environment variables (set by run_mrr.py)
imageDimension="${MRR_IMAGE_DIMENSION:-3}"
Iteration="${MRR_ITERATIONS:-4}"
transformationModel="${MRR_TRANSFORMATION_MODEL:-SyN}"
similarityMetric="${MRR_SIMILARITY_METRIC:-MI}"
target_template="${MRR_TARGET_TEMPLATE:-None}"
prefix="${MRR_PREFIX:-mrr}"
phantom="${MRR_PHANTOM:-false}"

prefix=${prefix}_${mod}

echo "prefix is: $prefix"
echo "Configuration:"
echo "  Image dimension: $imageDimension"
echo "  Iterations: $Iteration"
echo "  Transformation model: $transformationModel"
echo "  Similarity metric: $similarityMetric"
echo "  Target template: $target_template"
echo "  Phantom mode: $phantom"

##############################################################################
# Handle INPUT files - they should already be in the work directory

# Check for input files in work directory
axi_input_file="${work}/${mod}w_AXI.nii.gz"
cor_input_file="${work}/${mod}w_COR.nii.gz"
sag_input_file="${work}/${mod}w_SAG.nii.gz"

# Check if files contain FAST in the name
if [[ "${axi_input_file^^}" == *"FAST"* ]]; then
    echo "Fast detected in axi_input_file"
    prefix=${prefix}_fast
    echo "prefix is now: $prefix"
fi

# Check that input files exist
if [[ -e $axi_input_file ]] && [[ -e $cor_input_file ]] && [[ -e $sag_input_file ]]; then
    echo "${CONTAINER} All three input files found:"
    echo "  Axial: ${axi_input_file}"
    echo "  Coronal: ${cor_input_file}"
    echo "  Sagittal: ${sag_input_file}"
else
    echo "** ${CONTAINER} Missing one or more Nifti inputs within work directory $work **"
    prefix=${prefix}-AXI
    
    if [[ -e $axi_input_file ]]; then
        echo "${CONTAINER} Axial input file found: ${axi_input_file}"
    else
        echo "${CONTAINER} Missing axial input file"
    fi
    
    if [[ -e $cor_input_file ]]; then
        echo "${CONTAINER} Coronal input file found: ${cor_input_file}"
        prefix=${prefix}-COR
    else
        echo "${CONTAINER} Missing coronal input file"
    fi
    
    if [[ -e $sag_input_file ]]; then
        echo "${CONTAINER} Sagittal input file found: ${sag_input_file}"
        prefix=${prefix}-SAG
    else
        echo "${CONTAINER} Missing sagittal input file"
    fi
fi

echo "Work directory contents:"
echo "$(ls -l $work)"

##############################################################################
# Run MRR algorithm
echo "${CONTAINER} Running MRR (Multi-Resolution Registration) algorithm"

if [[ $phantom == "true" ]]; then
    echo "Phantom data detected, running phantom protocol..."

    # Create an isotropic image from the 3 T2 images
    echo "Running antsMultivariateTemplateConstruction2.sh with rigid registration to axial image..."
    antsMultivariateTemplateConstruction2.sh \
        -d ${imageDimension} \
        -i ${Iteration} \
        -z ${axi_input_file} \
        -r 1 \
        -t ${transformationModel} \
        -m ${similarityMetric} \
        -o ${work}/tmp_${prefix}_ \
        ${axi_input_file} ${cor_input_file} ${sag_input_file}

    echo "Resampling intermediate template to isotropic 1.5mm..."
    ResampleImageBySpacing 3 ${work}/tmp_${prefix}_template0.nii.gz ${work}/resampledTemplate.nii.gz 1.5 1.5 1.5

    echo "Pre-registering all acquisitions to resampled reference..."
    for acq in $(ls ${work}/${mod}w_*.nii.gz 2>/dev/null); do
        if [[ -e "$acq" ]]; then
            echo "Registering ${acq} to reference"
            outname=$(basename ${acq} .nii.gz)
            antsRegistrationSyN.sh \
                -d ${imageDimension} \
                -f ${work}/resampledTemplate.nii.gz \
                -m ${acq} \
                -t r \
                -o ${work}/reg_${outname}_
        fi
    done

    # Collect output from registration
    triplane_input=$(ls ${work}/reg_*_Warped.nii.gz 2>/dev/null)
    echo "Files for reconstruction: "
    echo ${triplane_input}

    if [[ -n "$triplane_input" ]]; then
        echo "Running antsMultivariateTemplateConstruction2.sh with non-linear registration to resampled template..."
        antsMultivariateTemplateConstruction2.sh \
            -d ${imageDimension} \
            -i ${Iteration} \
            -z ${work}/resampledTemplate.nii.gz \
            -t ${transformationModel} \
            -m ${similarityMetric} \
            -o ${work}/${prefix} \
            ${triplane_input}
    else
        echo "${CONTAINER} No registered files found for template construction"
        exit 1
    fi

else
    # If not phantom then check if target template is specified and run in-vivo protocol
    echo "Processing in-vivo data..."
    
    if [[ $target_template == "None" ]]; then
        echo "***"
        echo "No target template specified, trying self-reference..."
        echo "Check output for quality control!"
        echo "***"

        # Create a template from the 3 T2 images
        echo "Running antsMultivariateTemplateConstruction2.sh with rigid registration to axial image..."
        antsMultivariateTemplateConstruction2.sh \
            -d ${imageDimension} \
            -i ${Iteration} \
            -z ${axi_input_file} \
            -r 1 \
            -t ${transformationModel} \
            -m ${similarityMetric} \
            -o ${work}/tmp_${prefix}_ \
            ${axi_input_file} ${cor_input_file} ${sag_input_file}

        echo "Resampling intermediate template to isotropic 1.5mm..."
        ResampleImageBySpacing 3 ${work}/tmp_${prefix}_template0.nii.gz ${work}/resampledTemplate.nii.gz 1.5 1.5 1.5

        echo "Pre-registering all acquisitions to resampled reference..."
        for acq in $(ls ${work}/${mod}w_*.nii.gz 2>/dev/null); do
            if [[ -e "$acq" ]]; then
                echo "Registering ${acq} to reference"
                outname=$(basename ${acq} .nii.gz)
                antsRegistrationSyN.sh \
                    -d ${imageDimension} \
                    -f ${work}/resampledTemplate.nii.gz \
                    -m ${acq} \
                    -t r \
                    -o ${work}/reg_${outname}_
            fi
        done

        # Collect output from registration
        triplane_input=$(ls ${work}/reg_*_Warped.nii.gz 2>/dev/null)
        echo "Files for reconstruction: "
        echo ${triplane_input}

        if [[ -n "$triplane_input" ]]; then
            echo "Running antsMultivariateTemplateConstruction2.sh with non-linear registration to resampled template..."
            antsMultivariateTemplateConstruction2.sh \
                -d ${imageDimension} \
                -i ${Iteration} \
                -t ${transformationModel} \
                -m ${similarityMetric} \
                -o ${work}/${prefix} \
                ${triplane_input}
        else
            echo "${CONTAINER} No registered files found for template construction"
            exit 1
        fi

    else
        echo "Target template specified: ${target_template}"
        
        # Check if template file exists
        template_path="${templates_dir}/${target_template}"
        if [[ ! -e "$template_path" ]]; then
            echo "${CONTAINER} Error: Target template not found: $template_path"
            echo "Available templates in ${templates_dir}:"
            ls -la "${templates_dir}/" || echo "Template directory not found"
            exit 1
        fi
        
        echo "Resampling template to match input resolution 1.5mm"
        ResampleImageBySpacing 3 "$template_path" "${work}/resampled_${target_template}" 1.5 1.5 1.5

        # Pre-registration
        echo "Pre-registering acquisitions to template..."
        for acq in $(ls ${work}/${mod}w_*.nii.gz 2>/dev/null); do
            if [[ -e "$acq" ]]; then
                echo "Registering ${acq} to ${target_template}"
                outname=$(basename ${acq} .nii.gz)
                antsRegistrationSyN.sh \
                    -d ${imageDimension} \
                    -f "$template_path" \
                    -m ${acq} \
                    -t r \
                    -o ${work}/reg_${outname}_
            fi
        done

        # Collect output from registration
        triplane_input=$(ls ${work}/reg_*_Warped.nii.gz 2>/dev/null)
        echo "Files for reconstruction: "
        echo ${triplane_input}

        # Check for registered files and process them
        if [[ -n "$triplane_input" ]]; then
            echo "Running antsMultivariateTemplateConstruction2.sh"
            antsMultivariateTemplateConstruction2.sh \
                -d ${imageDimension} \
                -i ${Iteration} \
                -t ${transformationModel} \
                -m ${similarityMetric} \
                -o ${work}/${prefix} \
                ${triplane_input}
        else
            echo "${CONTAINER} No registered files found for template construction"
            exit 1
        fi
    fi
fi

# Check if template construction completed & move outputs
if [[ -e ${work}/${prefix}template0.nii.gz ]]; then
    echo "Isotropic image generated from orthogonal acquisitions"
    ls -l ${work}/${prefix}template0.nii.gz
    
    # Clean up session date (remove time if present)
    ses_clean=$(echo "$ses" | cut -d' ' -f1)
    
    # Create output filename
    output_filename="sub-${sub}_ses-${ses_clean}_rec-${prefix}.nii.gz"
    
    echo "Moving results to output directory..."
    mv ${work}/${prefix}template0.nii.gz ${output_dir}/${output_filename} || {
        echo "Failed to move main output file"
        exit 1
    }
    
    # Move registered intermediate files if they exist
    if ls ${work}/reg_*_Warped.nii.gz 1> /dev/null 2>&1; then
        mv ${work}/reg_*_Warped.nii.gz ${output_dir}/ || {
            echo "Warning: Failed to move some intermediate files"
        }
    fi
    
    echo "${CONTAINER} Processing completed successfully!"
    echo "Output file: ${output_dir}/${output_filename}"
    echo "Output directory contents:"
    ls -la ${output_dir}/
    
else
    echo "${CONTAINER} Template not generated!"
    echo "Work directory contents:"
    ls -la ${work}/
    echo "${CONTAINER} Exiting with error..."
    exit 1
fi