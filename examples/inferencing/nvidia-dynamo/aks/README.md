# NVIDIA Dynamo LLM Inference on AKS

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites and AKS Environment Setup](#2-prerequisites-and-aks-environment-setup)
3. [Deployment Steps](#3-deployment-steps)

   3.1. [Shared Storage Configuration](#31-shared-storage-configuration)

   3.2. [Model Download](#32-model-download)

   3.3. [Deploy Inference Service](#33-deploy-inference-service)

4. [Accessing the Service](#4-accessing-the-service)

## 1. Introduction

This example demonstrates how to deploy Large Language Model (LLM) inference services using NVIDIA Dynamo on Azure Kubernetes Service (AKS). The solution utilizes Helm charts to orchestrate containerized inference workloads with optimized GPU utilization.

The implementation leverages:

- **[NVIDIA Dynamo](https://developer.nvidia.com/dynamo)** - NVIDIA's framework for deploying optimized LLM inference services with automatic profiling and scaling
- **[vLLM](https://github.com/vllm-project/vllm)** - High-throughput, low-latency LLM serving engine
- **DynamoGraphDeploymentRequest** - Kubernetes Custom Resource for declarative inference deployment

NVIDIA Dynamo automatically profiles the model on your specific hardware and deploys an optimized inference service with appropriate batching, memory management, and scaling configurations.

## 2. Prerequisites and AKS Environment Setup

Before deploying the inference service, ensure your AKS cluster meets the following requirements:

- **NVIDIA Dynamo Operator** installed for managing DynamoGraphDeploymentRequest resources
- **GPU Operator** with GPU-enabled node pools (e.g., Standard_NC24ads_A100_v4, Standard_ND96isr_H100_v5)
- **Blob Storage CSI Driver** or Azure Files for model storage
- **Sufficient GPU memory** for the model being deployed

Follow the [infrastructure reference documentation](../../../../infrastructure_references/aks/README.md) for detailed AKS cluster setup and configuration.

## 3. Deployment Steps

### 3.1. Shared Storage Configuration

Deploy shared storage infrastructure to store and serve model weights. The shared storage Helm charts are located in `storage_references/aks/shared_storage/helm`.

For inference workloads, Azure Files provides a good balance of performance and ease of use on a small-medium number of nodes for shared model loading:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/azurefiles-shared-storage \
  --set storage.pvcName="shared-azurefiles-storage" \
  --set storage.size="1Ti"
```

Alternatively, use Azure Blob Storage for larger scale scenarios:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set storage.pvcName="shared-blob-storage"
```

For detailed configuration options, see the [shared storage README](../../../../storage_references/aks/shared_storage/README.md).

### 3.2. Model Download

Download the model weights to the shared storage. This example uses a sample GPT model:

```bash
# Create a pod to download the model
kubectl run model-downloader --rm -it \
  --image=python:3.10-slim \
  --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "model-downloader",
        "image": "python:3.10-slim",
        "command": ["bash", "-c", "pip install huggingface_hub && hf download openai/gpt-oss-120b --local-dir /models/gpt-oss-120b"],
        "volumeMounts": [{
          "name": "model-storage",
          "mountPath": "/models"
        }]
      }],
      "volumes": [{
        "name": "model-storage",
        "persistentVolumeClaim": {
          "claimName": "shared-azurefiles-storage"
        }
      }]
    }
  }'
```

### 3.3. Deploy Inference Service

Deploy the NVIDIA Dynamo inference service using the provided Helm chart:

```bash
helm install gpt-inference examples/inferencing/nvidia-dynamo/aks/helm/dynamo-deployment \
  --set model.name="openai/gpt-oss-120b" \
  --set model.backend="vllm" \
  --set modelCache.pvcName="shared-azurefiles-storage" \
  --set modelCache.pvcModelPath="gpt-oss-120b"
```

#### Configuration Options

| Parameter                 | Description                                | Default                                    |
| ------------------------- | ------------------------------------------ | ------------------------------------------ |
| `model.name`              | HuggingFace model identifier or path       | `openai/gpt-oss-120b`                      |
| `model.backend`           | Inference backend (`vllm`, `tensorrt-llm`) | `vllm`                                     |
| `image.repository`        | Container image repository                 | `nvcr.io/nvidia/ai-dynamo/dynamo-frontend` |
| `image.tag`               | Container image tag                        | `1.0.1`                                    |
| `modelCache.pvcName`      | PVC name for model storage                 | `shared-azurefiles-storage`                |
| `modelCache.pvcModelPath` | Path within PVC to model weights           | `gpt-oss-120b`                             |

#### Verify Deployment

```bash
# Check DynamoGraphDeploymentRequest status
kubectl get dynamographdeploymentrequests

# View deployment details
kubectl describe dynamographdeploymentrequest gpt-inference

# Check running pods
kubectl get pods -l app.kubernetes.io/managed-by=dynamo
```

## 4. Accessing the Service

Once deployed, NVIDIA Dynamo creates a Kubernetes Service for the inference endpoint.

### Get Service Endpoint

```bash
# List all services to find the inference endpoint
kubectl get svc

# Port forward to the inference service for local testing
kubectl port-forward svc/<inference endpoint> 8000:8000
```

### Test the API

The service exposes an OpenAI-compatible API:

```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-120b",
    "prompt": "Hello, world!",
    "max_tokens": 100
  }'
```

### Chat Completions

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-120b",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ]
  }'
```
