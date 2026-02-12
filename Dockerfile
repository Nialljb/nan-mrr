FROM nialljb/njb-ants-fsl-base:0.0.2 as base

ENV HOME=/root/
ENV APPDIR="/app"
WORKDIR $APPDIR
RUN mkdir -p $APPDIR/templates

# Installing the current project (most likely to change, above layer can be cached)
COPY ./ $APPDIR/

# Install system dependencies and Python packages
RUN apt-get update && \
    apt-get clean && \
    pip install --no-cache-dir -r requirements.txt && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set up FSL environment
ENV PATH="/opt/conda/bin:${PATH}"
ENV FSLDIR="/opt/conda"
ENV MRR_TEMPLATES_DIR="/app/templates"

# Configure permissions
RUN chmod +rx $APPDIR/run_mrr.py && \
    chmod +wrx $APPDIR/app/ciso-gear.sh && \
    chmod +wrx $APPDIR/app/mrr-singularity.sh

# Set the entry point to the new MRR script
ENTRYPOINT ["python3", "/app/run_mrr.py"]