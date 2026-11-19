# Dockerfile for GPT-OSS Fine-tuning on H100 GPU
# Base: NVIDIA PyTorch container (includes CUDA, cuDNN, PyTorch pre-optimized)
# Using PyTorch NGC container for better performance and faster builds

FROM nvcr.io/nvidia/pytorch:25.01-py3

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Install ML dependencies for fine-tuning
RUN pip install --no-cache-dir \
    "trl>=0.20.0" \
    "peft>=0.17.0" \
    "transformers>=4.55.0" \
    "bitsandbytes>=0.41.0" \
    "accelerate>=0.20.0"

# Install Azure SDK for blob storage integration
RUN pip install --no-cache-dir \
    azure-storage-blob \
    azure-identity

# Create working directory
WORKDIR /workspace

# Copy training script from src folder
COPY src/finetune.py /workspace/

# Set entrypoint
ENTRYPOINT ["python", "finetune.py"]
