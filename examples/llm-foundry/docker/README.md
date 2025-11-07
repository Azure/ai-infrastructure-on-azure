# LLM Foundry Container Image

## Table of Contents

1. [Overview](#1-overview)
2. [Container Image](#2-container-image)
3. [Manual Build (Optional)](#3-manual-build-optional)

## 1. Overview

This directory contains the Dockerfile for building a custom LLM Foundry container image with additional optimizations for Azure infrastructure, including DOCA/OFED drivers for InfiniBand connectivity and topology files for ND-series VMs.

## 2. Container Image

The container image is automatically built and published to GitHub Container Registry via GitHub Actions whenever changes are made to the Dockerfile or workflow.

Published image: `ghcr.io/azure/ai-infrastructure-on-azure/llm-foundry:latest`

### What's Included

The container image is based on `mosaicml/llm-foundry:2.6.0_cu124-latest` and includes:

- **LLM Foundry v0.18.0**: The complete MosaicML LLM training framework
- **DOCA and Mellanox Tools**: For InfiniBand networking optimizations
- **Azure NDv5 Topology**: Optimized topology file for Azure ND-series VMs
- **Python Dependencies**: All required packages for GPU training

## 3. Manual Build (Optional)

If you need to build a custom version with modifications, follow these instructions:

```bash
cd examples/llm-foundry/docker/
az acr login -n $ACR_NAME  # Optional: for pushing to Azure Container Registry
docker build -t llm-foundry:dev .
```

#### Pushing to Azure Container Registry

To push to your Azure Container Registry:

```bash
docker tag llm-foundry:dev $ACR_NAME.azurecr.io/llm-foundry:dev
docker push $ACR_NAME.azurecr.io/llm-foundry:dev
```
