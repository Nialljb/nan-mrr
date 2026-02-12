#!/usr/bin/env python3
"""
MRR (Multi-Resolution Registration) main script for Singularity/SLURM execution.

This script replaces the Flywheel-specific run.py with command-line argument parsing
suitable for HPC environments.
"""

import argparse
import logging
import os
import sys
from pathlib import Path
import subprocess
import shutil
import re

log = logging.getLogger(__name__)

def setup_logging(debug=False):
    """Setup logging configuration."""
    level = logging.DEBUG if debug else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

def detect_modality_from_filename(filename):
    """
    Detect modality (T1/T2) from filename.
    
    Args:
        filename (str): Input filename
        
    Returns:
        str: Modality ('T1' or 'T2')
    """
    filename_upper = filename.upper()
    if 'T1' in filename_upper:
        return 'T1'
    elif 'T2' in filename_upper:
        return 'T2'
    else:
        raise ValueError(f"Cannot detect modality from filename: {filename}")

def find_input_files(input_file, input_dir=None):
    """
    Find and organize input files based on the configuration.
    
    For MRR, we expect T2w files with specific naming patterns.
    If input_file is a directory, look for files matching the pattern.
    
    Args:
        input_file (str): Input file or directory path
        input_dir (str): Base input directory (for BIDS-like structures)
        
    Returns:
        tuple: (modality, file_paths dict)
    """
    input_files = {}
    
    if os.path.isfile(input_file):
        # Single file provided
        modality = detect_modality_from_filename(os.path.basename(input_file))
        input_files['axi'] = input_file
        
        # Look for corresponding orientations in same directory
        base_dir = os.path.dirname(input_file)
        base_name = os.path.basename(input_file)
        
        # Try to find coronal and sagittal variants
        for orientation in ['cor', 'sag']:
            orientation_pattern = base_name.replace('axi', orientation, 1)
            if orientation_pattern == base_name:
                # If no 'axi' in filename, try other patterns
                for pattern in ['_AXI_', '_COR_', '_SAG_']:
                    if pattern in base_name.upper():
                        orientation_pattern = base_name.upper().replace(
                            pattern, f'_{orientation.upper()}_', 1
                        )
                        break
            
            orientation_file = os.path.join(base_dir, orientation_pattern)
            if os.path.exists(orientation_file):
                input_files[orientation] = orientation_file
                
    elif os.path.isdir(input_file):
        # Directory provided, look for files
        if input_dir and os.path.exists(input_dir):
            search_dir = os.path.join(input_dir, 'anat')
        else:
            search_dir = input_file
            
        # Look for T2w files matching the pattern
        pattern = r".*_T2w\.nii\.gz$"
        
        for root, dirs, files in os.walk(search_dir):
            for file in files:
                if re.match(pattern, file):
                    file_path = os.path.join(root, file)
                    file_upper = file.upper()
                    
                    if 'AXI' in file_upper or 'AXIAL' in file_upper:
                        input_files['axi'] = file_path
                        modality = detect_modality_from_filename(file)
                    elif 'COR' in file_upper or 'CORONAL' in file_upper:
                        input_files['cor'] = file_path
                    elif 'SAG' in file_upper or 'SAGITTAL' in file_upper:
                        input_files['sag'] = file_path
    else:
        raise FileNotFoundError(f"Input file/directory not found: {input_file}")
    
    if 'axi' not in input_files:
        raise ValueError("No axial input file found")
        
    return modality, input_files

def setup_work_directory(work_dir, input_files, modality):
    """
    Setup working directory and copy input files.
    
    Args:
        work_dir (str): Working directory path
        input_files (dict): Dictionary of input file paths
        modality (str): Detected modality
    """
    os.makedirs(work_dir, exist_ok=True)
    
    # Copy files to working directory with standard names
    for orientation, file_path in input_files.items():
        if file_path and os.path.exists(file_path):
            dest_name = f"{modality}w_{orientation.upper()}.nii.gz"
            dest_path = os.path.join(work_dir, dest_name)
            shutil.copy2(file_path, dest_path)
            log.info(f"Copied {orientation} file: {file_path} -> {dest_path}")

def extract_subject_session_from_path(input_path):
    """
    Extract subject and session identifiers from BIDS-like path structure.
    
    Args:
        input_path (str): Input file or directory path
        
    Returns:
        tuple: (subject_id, session_id)
    """
    # Default values
    subject_id = "unknown"
    session_id = "unknown"
    
    # Try to extract from BIDS-like structure
    path_parts = Path(input_path).parts
    
    for part in path_parts:
        if part.startswith('sub-'):
            subject_id = part[4:]  # Remove 'sub-' prefix
        elif part.startswith('ses-'):
            session_id = part[4:]  # Remove 'ses-' prefix
            
    return subject_id, session_id

def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description="MRR: Multi-Resolution Registration using ANTs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process single T2w file
  python /app/run_mrr.py --input /data/sub-01/ses-01/anat/sub-01_ses-01_T2w.nii.gz --output /output
  
  # Process BIDS dataset
  python /app/run_mrr.py --input /data/sub-01/ses-01 --output /output
        """
    )
    
    parser.add_argument(
        '--input', 
        required=True,
        help='Input file or directory containing T2w images'
    )
    parser.add_argument(
        '--output', 
        required=True,
        help='Output directory for results'
    )
    parser.add_argument(
        '--work-dir',
        default='/tmp/mrr_work',
        help='Working directory (default: /tmp/mrr_work)'
    )
    parser.add_argument(
        '--subject',
        help='Subject identifier (auto-detected from path if not provided)'
    )
    parser.add_argument(
        '--session',
        help='Session identifier (auto-detected from path if not provided)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug logging'
    )
    
    # MRR-specific parameters (these match the original gear config)
    parser.add_argument(
        '--image-dimension',
        type=int,
        default=3,
        choices=[2, 3, 4],
        help='Image dimension (default: 3)'
    )
    parser.add_argument(
        '--iterations',
        type=int,
        default=4,
        help='Number of template construction iterations (default: 4)'
    )
    parser.add_argument(
        '--transformation-model',
        default='SyN',
        choices=['BSplineSyN', 'SyN', 'TimeVaryingBSplineVelocityField', 'TimeVaryingVelocityField'],
        help='Transformation model (default: SyN)'
    )
    parser.add_argument(
        '--similarity-metric',
        default='MI',
        choices=['CC', 'MI', 'MSQ'],
        help='Similarity metric (default: MI)'
    )
    parser.add_argument(
        '--target-template',
        default='None',
        help='Target template file (default: None for self-reference)'
    )
    parser.add_argument(
        '--prefix',
        default='mrr',
        help='Output prefix (default: mrr)'
    )
    parser.add_argument(
        '--phantom',
        action='store_true',
        help='Input is phantom data'
    )
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(args.debug)
    
    log.info("Starting MRR processing...")
    log.info(f"Input: {args.input}")
    log.info(f"Output: {args.output}")
    
    try:
        # Find and organize input files
        modality, input_files = find_input_files(args.input)
        log.info(f"Detected modality: {modality}")
        log.info(f"Input files: {input_files}")
        
        # Extract subject/session if not provided
        subject_id = args.subject or extract_subject_session_from_path(args.input)[0]
        session_id = args.session or extract_subject_session_from_path(args.input)[1]
        
        log.info(f"Subject: {subject_id}, Session: {session_id}")
        
        # Setup working directory
        setup_work_directory(args.work_dir, input_files, modality)
        
        # Create output directory
        os.makedirs(args.output, exist_ok=True)
        
        # Set environment variables for the shell script
        env = os.environ.copy()
        env.update({
            'MRR_WORK_DIR': args.work_dir,
            'MRR_OUTPUT_DIR': args.output,
            'MRR_IMAGE_DIMENSION': str(args.image_dimension),
            'MRR_ITERATIONS': str(args.iterations),
            'MRR_TRANSFORMATION_MODEL': args.transformation_model,
            'MRR_SIMILARITY_METRIC': args.similarity_metric,
            'MRR_TARGET_TEMPLATE': args.target_template,
            'MRR_PREFIX': args.prefix,
            'MRR_PHANTOM': 'true' if args.phantom else 'false',
            'MRR_MODALITY': modality,
            'MRR_SUBJECT': subject_id,
            'MRR_SESSION': session_id
        })
        
        # Run the main processing script
        script_path = '/app/ciso-gear.sh'
        if not os.path.exists(script_path):
            script_path = os.path.join(os.path.dirname(__file__), 'app', 'ciso-gear.sh')
            
        command = [script_path, subject_id, session_id, modality]
        
        log.info(f"Executing: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            env=env,
            capture_output=False,
            text=True
        )
        
        if result.returncode != 0:
            log.error(f"Processing failed with return code: {result.returncode}")
            sys.exit(result.returncode)
        else:
            log.info("Processing completed successfully!")
            
    except Exception as e:
        log.error(f"Error during processing: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()