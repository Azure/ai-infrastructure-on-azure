FROM nvcr.io/nvidia/pytorch:25.03-py3

ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables and versions
ENV LAUNCHER_VERSION=24.12
ENV NEMO_VERSION=24.05
ENV MEGATRON_LM_VERSION=878d65f

# Clone and install Megatron-LM
RUN git clone https://github.com/NVIDIA/Megatron-LM.git /megatron-lm && \
    cd /megatron-lm && \
    git checkout ${MEGATRON_LM_VERSION} && \
    pip install -e .

# Install additional Python packages for data preprocessing
RUN pip install -U pip && \
    pip install datasets transformers tokenizers huggingface_hub ninja

# Download NDv5 topology
RUN wget -O /etc/ndv5-topo.xml https://raw.githubusercontent.com/Azure/azhpc-images/refs/heads/master/topology/ndv5-topo.xml

# Set working directory
WORKDIR /megatron-lm

# Set a default command and healthcheck
CMD ["python", "-c", "import torch; print(f'PyTorch version: {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA device count: {torch.cuda.device_count()}')"]
HEALTHCHECK CMD ["python3", "-c", "import torch; assert torch.cuda.is_available()"]
