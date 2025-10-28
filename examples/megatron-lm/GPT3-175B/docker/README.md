# Megatron-LM Docker Image

## Table of Contents

1. [Overview](#1-overview)
2. [Contents](#2-contents)
3. [Included Components](#3-included-components)
4. [Build Process](#4-build-process)
5. [Image Capabilities](#5-image-capabilities)
6. [Health Checks](#6-health-checks)
7. [Usage Examples](#7-usage-examples)
8. [Environment Variables](#8-environment-variables)
9. [Working Directory](#9-working-directory)
10. [Security](#10-security)

## 1. Overview

This directory contains the Dockerfile for building a Megatron-LM container image optimized for distributed training on Azure Kubernetes Service (AKS).

## 2. Contents

- **Dockerfile**: Multi-stage build for Megatron-LM with all dependencies
- Built on NVIDIA PyTorch NGC image (25.03-py3)
- Includes NeMo Framework Launcher for advanced training configurations
- Pre-configured with Mellanox DOCA and networking tools
- Optimized for RDMA and InfiniBand networking

## 3. Included Components

### Base Image
- **NVIDIA PyTorch**: 25.03-py3 with CUDA 12.4+ support
- **Python**: 3.10+ with optimized PyTorch installation

### Training Frameworks
- **Megatron-LM**: Latest stable version with GPT training support
- **NeMo Framework Launcher**: 24.12 for advanced model configurations
- **Transformer Engine**: For optimized attention mechanisms

### Networking & Performance
- **Mellanox DOCA**: 2.9.1 for InfiniBand optimization
- **SHARP**: Scalable Hierarchical Aggregation and Reduction Protocol
- **UCX**: Unified Communication X for high-performance networking
- **NCCL**: Optimized collective communications

### System Tools
- **Build tools**: GCC, Make, Autotools for compilation
- **Compression**: zstd for dataset decompression
- **Topology files**: NDv5 InfiniBand topology for Azure HPC VMs

## 4. Build Process

The image is automatically built and published via GitHub Actions when changes are made to the Dockerfile. The workflow file is located at:

```
.github/workflows/build_megatron_image.yaml
```

### Manual Build

To build the image manually:

```bash
docker build -t megatron-lm:latest .
```

### Published Image

The image is automatically published to:

```
ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest
```

## 5. Image Capabilities

### Supported Training
- **GPT models**: 125M to 175B+ parameters
- **Distributed training**: Tensor and pipeline parallelism
- **Mixed precision**: FP16 and BF16 training
- **Gradient checkpointing**: Memory optimization
- **ZeRO optimization**: Distributed optimizer states

### Dataset Support
- **SlimPajama**: 627B token cleaned dataset
- **Custom datasets**: JSON Lines format support
- **Data preprocessing**: Tokenization and binary format conversion
- **Streaming**: Efficient data loading from remote storage

### Hardware Optimization
- **Multi-GPU**: Up to 8 GPUs per node
- **Multi-node**: Unlimited node scaling
- **RDMA networking**: InfiniBand optimization
- **CPU optimization**: Optimized for ND-series Azure VMs

## 6. Health Checks

The image includes health checks to verify:
- CUDA availability and GPU detection
- PyTorch installation and GPU access
- Basic import functionality for all frameworks

## 7. Usage Examples

### Basic Training
```bash
docker run --gpus all ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest \
  python /megatron-lm/pretrain_gpt.py --help
```

### Environment Check
```bash
docker run --gpus all ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest \
  python -c "import torch; print(f'GPUs: {torch.cuda.device_count()}')"
```

### Interactive Session
```bash
docker run -it --gpus all ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest bash
```

## 8. Environment Variables

The following environment variables are pre-configured:

- **LAUNCHER_VERSION**: 24.12
- **NEMO_VERSION**: 24.05  
- **MEGATRON_LM_VERSION**: 878d65f

## 9. Working Directory

The container's working directory is set to `/megatron-lm` for easy access to training scripts.

## 10. Security

The image is configured for secure operation in Kubernetes environments:
- Non-root user capability (when not requiring privileged access)
- Minimal attack surface with only required packages
- Regular security updates via automated builds
