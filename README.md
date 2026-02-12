# MRR: Multi-Resolution Registration

## Overview

MRR (Multi-Resolution Registration) is a Singularity container that constructs isotropic images from tri-plane orthogonal acquisitions using ANTs-based registration algorithms.

Originally developed as a Flywheel gear, this tool has been refactored for use on HPC systems with SLURM scheduling.

### Summary

Takes three orthogonally acquired images (axial, coronal, sagittal) and combines them into a single 1.5mm isotropic image using ANTs multivariate template construction.

**Inputs:**
- Axial T2w acquisition (required)
- Coronal T2w acquisition (optional)
- Sagittal T2w acquisition (optional)
- Target template (optional - age-matched)

**Outputs:**
- Isotropic reconstructed volume
- Intermediate registration files

If no template is provided, the algorithm creates an initial template by rigid registration of all images to the axial plane, then uses this as reference for isotropic reconstruction.

### Citation

**License:** MIT

**URL:** https://github.com/ANTsX/ANTs

**Cite:** A reproducible evaluation of ANTs similarity metric performance in brain image registration: Avants BB, Tustison NJ, Song G, Cook PA, Klein A, Gee JC. Neuroimage, 2011. http://www.ncbi.nlm.nih.gov/pubmed/20851191

---

## Installation and Setup

### What is Singularity?

Singularity (now commonly distributed as Apptainer) is a container runtime designed for HPC environments. Unlike typical Docker workflows, it runs containers in a way that is more compatible with shared clusters and schedulers (e.g., SLURM), while packaging software and dependencies into a single `.sif` image file.

### Building the Singularity Image

This repository provides two build paths. In both cases, the final output is a `.sif` image you can run with `singularity exec`.

#### Requirements

- Linux host with `singularity`/Apptainer available on `PATH`
- `mrr.def` present in the repository root
- For definition-file builds: either
    - fakeroot support enabled (`singularity build --fakeroot ...`), or
    - `sudo` access for root build fallback
- For Docker conversion builds (optional path): working Docker daemon and permission to run `docker build`

Quick checks:

```bash
singularity --version
test -f mrr.def && echo "mrr.def found"
```

#### Option 1: Build from Singularity definition file (recommended)

```bash
# Build the image
./build_singularity.sh

# Output: mrr.sif in the repository root
```

What this script does:

- Verifies `singularity` and `mrr.def` are available
- Builds with fakeroot first, then falls back to `sudo singularity build` if needed
- Runs `singularity test mrr.sif` after build

#### Option 2: Build from Docker then convert

```bash
# Build Docker image first, then convert to Singularity
./build_docker_to_singularity.sh

# Output: mrr_from_docker.sif
```

Use this path when you prefer building from `Dockerfile` first or your environment handles Docker builds more reliably than direct definition-file builds.

### Prerequisites

- Singularity/Apptainer installed on your system
- Network access to pull base container image(s) during build
- Sufficient local disk space for build temp files and final image
- ANTs and FSL tools are included inside the built image (no separate host install required)

### Verify the built image

```bash
singularity test mrr.sif
singularity exec mrr.sif python /app/run_mrr.py --help
```

---

## Usage

### Command Line Interface

The main entry point is `run_mrr.py`, which accepts the following arguments:

```bash
singularity exec mrr.sif python /app/run_mrr.py --help
```

### Basic Usage

```bash
# Process a single T2w file
singularity exec mrr.sif python /app/run_mrr.py \
    --input /data/sub-01/ses-01/anat/sub-01_ses-01_T2w.nii.gz \
    --output /results

# Process BIDS dataset directory
singularity exec mrr.sif python /app/run_mrr.py \
    --input /data/sub-01/ses-01 \
    --output /results \
    --subject 01 \
    --session 01
```

### Advanced Options

```bash
singularity exec mrr.sif python /app/run_mrr.py \
    --input /data/input.nii.gz \
    --output /results \
    --work-dir /tmp/work \
    --iterations 6 \
    --transformation-model SyN \
    --similarity-metric MI \
    --target-template nihpd_asym_04.5-08.5_t2w.nii \
    --phantom \
    --debug
```

### Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--input` | **required** | Input file or directory |
| `--output` | **required** | Output directory |
| `--work-dir` | `/tmp/mrr_work` | Working directory |
| `--subject` | auto-detect | Subject identifier |
| `--session` | auto-detect | Session identifier |
| `--image-dimension` | 3 | Image dimension (2, 3, or 4) |
| `--iterations` | 4 | Template construction iterations |
| `--transformation-model` | SyN | Transformation model |
| `--similarity-metric` | MI | Similarity metric (CC, MI, MSQ) |
| `--target-template` | None | Target template file |
| `--prefix` | mrr | Output file prefix |
| `--phantom` | false | Process as phantom data |
| `--debug` | false | Enable debug logging |

---

## HPC/SLURM Usage

### SLURM Job Submission

Use the provided SLURM submission script as a template:

```bash
# Edit the script for your environment
cp run_mrr_slurm.sh my_mrr_job.sh
# Modify paths and parameters in my_mrr_job.sh

# Submit the job
sbatch my_mrr_job.sh
```

### HPC Configuration

The tool matches the SLURM configuration format specified:

```json
{
    "MRR": {
        "image_path": "/home/{hpc_username}/images/mrr.sif",
        "command_template": "python /app/run_mrr.py --input {input_file} --output {output_dir}",
        "input_type": "acquisition",
        "input_pattern": ".*_T2w\\.nii\\.gz$",
        "input_subdir": "anat",
        "requires_derivative": null,
        "output_name": "mrr",
        "default_cpus": 4,
        "default_mem": "24G",
        "default_gpus": 0,
        "default_time": "03:00:00",
        "description": "MRI reconstruction and registration"
    }
}
```

### File Organization

The container expects and produces files in BIDS-compatible format:

**Input structure:**
```
/data/
├── sub-01/
│   └── ses-01/
│       └── anat/
│           ├── sub-01_ses-01_T2w.nii.gz      # Axial
│           ├── sub-01_ses-01_acq-cor_T2w.nii.gz   # Coronal (optional)
│           └── sub-01_ses-01_acq-sag_T2w.nii.gz   # Sagittal (optional)
```

**Output structure:**
```
/results/
├── sub-01_ses-01_rec-mrr_T2.nii.gz    # Main reconstructed volume
└── reg_*_Warped.nii.gz                # Intermediate registered files
```

---

## Templates

The container includes age-matched templates for pediatric and adult data:

- `nihpd_asym_00-02_t2w.nii` - 0-2 months
- `nihpd_asym_02-05_t2w.nii` - 2-5 months  
- `nihpd_asym_05-08_t2w.nii` - 5-8 months
- ... (see app/templates/ directory for full list)
- `mni_icbm152_t2_tal_nlin_asym_55_ext.nii` - Adult template

---

## Troubleshooting

### Common Issues

1. **"Template not found" error**
   - Check that the template name matches exactly (case-sensitive)
   - Use `--target-template None` for self-reference

2. **"No axial input file found" error**
   - Ensure input files contain 'T2' in filename
   - Check file naming follows BIDS conventions

3. **Memory errors**
   - Increase memory allocation in SLURM script
   - Use smaller iteration counts for initial testing

4. **Permission errors**
   - Ensure bind mount paths have appropriate permissions
   - Check Singularity user namespace configuration

### Debug Mode

Enable debug logging for detailed output:

```bash
singularity exec mrr.sif python /app/run_mrr.py \
    --input /data/input.nii.gz \
    --output /results \
    --debug
```

---

## Development and Contributing

### File Structure

```
├── run_mrr.py                 # Main entry point
├── app/
│   ├── mrr-singularity.sh     # Core processing script
│   ├── ciso-gear.sh           # Legacy wrapper
│   └── templates/             # Age-matched templates
├── mrr.def                    # Singularity definition
├── Dockerfile                 # Docker build file
├── requirements.txt           # Python dependencies
├── mrr_config.json           # Configuration metadata
├── build_singularity.sh      # Build script
├── run_mrr_slurm.sh          # SLURM submission template
└── backup_flywheel/          # Original Flywheel files
```

### Original Flywheel Implementation

The original Flywheel gear files are preserved in `backup_flywheel/` directory for reference.

### Testing

Test the container installation:

```bash
singularity test mrr.sif
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with the provided test scripts
5. Submit a pull request

---

## Migration from Flywheel

This tool was migrated from a Flywheel gear to a Singularity container. Key changes:

- Removed Flywheel SDK dependencies
- Added command-line argument parsing
- Updated paths for standard filesystem layout
- Added SLURM integration
- Maintained core ANTs processing pipeline

Original Flywheel gear functionality is preserved in the `backup_flywheel/` directory.