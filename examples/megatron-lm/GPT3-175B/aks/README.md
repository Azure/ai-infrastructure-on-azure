# Megatron-LM Distributed Training - GPT3 - AKS

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites and AKS Environment Setup](#2-prerequisites-and-aks-environment-setup)
3. [Deployment Steps](#3-deployment-steps)
   
   3.1. [Shared Storage Configuration](#31-shared-storage-configuration)
   
   3.2. [Dataset Preparation](#32-dataset-preparation)
   
   3.3. [Model Training](#33-model-training)

## 1. Introduction

This example demonstrates how to train GPT models using Megatron-LM on Azure Kubernetes Service (AKS). The solution utilizes Helm charts to orchestrate containerized training workloads with distributed computing capabilities across GPU-enabled AKS nodes.

The implementation leverages several key technologies:

- **[Megatron-LM](https://github.com/NVIDIA/Megatron-LM)** - NVIDIA's framework for large-scale language model training
- **[SlimPajama 627B Dataset](https://huggingface.co/datasets/cerebras/SlimPajama-627B)** - Cleaned and de-duplicated open source version of Together's RedPajama dataset
- **PyTorch Operator** - Kubernetes-native distributed PyTorch training orchestration
- **NeMo Framework Launcher** - NVIDIA's toolkit for scaling language model training

## 2. Prerequisites and AKS Environment Setup

Before proceeding with the training deployment, ensure your AKS cluster meets the following requirements:

- **PyTorch Operator** installed for distributed training coordination
- **Blob Storage CSI Driver** or **Azure Managed Lustre CSI Driver** enabled for data storage integration  
- **GPU-enabled node pools** with appropriate VM SKUs (e.g., Standard_ND96isr_H100_v5, Standard_ND96isr_H200_v5)
- **RDMA networking** configured for high-performance inter-node communication
- **Sufficient storage** - The 175B model checkpoints require approximately 2.3 TiB of storage

Follow the [infrastructure reference documentation](../../../../infrastructure_references/aks/README.md) for detailed AKS cluster setup and configuration.

## 3. Deployment Steps

### 3.1. Shared Storage Configuration

Deploy shared storage infrastructure to provide persistent, scalable storage accessible across all training pods. The shared storage Helm charts are located in `storage_references/aks/shared_storage/helm` and offer two storage options. For detailed configuration options and setup instructions, see the [shared storage README](../../../storage_references/aks/shared_storage/README.md).

#### Option 1: Azure Managed Lustre File System (AMLFS)

AMLFS delivers high-throughput, low-latency storage optimized for large-scale training workloads. Consider the bandwidth requirements for checkpoint writing:

| Tier      | Size [TiB] | Bandwidth [GB/s] | Theoretical checkpoint write time (min) |
| --------- | ---------- | ---------------- | --------------------------------------- |
| AMLFS 40  | 480        | 19.2             | 2.04                                    |
| AMLFS 125 | 512        | 64               | 0.61                                    |
| AMLFS 250 | 512        | 128              | 0.31                                    |
| AMLFS 500 | 512        | 256              | 0.15                                    |

Example deployment for AMLFS:

```bash
helm install shared-storage ../../../storage_references/aks/shared_storage/helm/amlfs-shared-storage \
  --set amlfs.skuName="AMLFS-Durable-Premium-125" \
  --set amlfs.storageCapacityTiB=16 \
  --set pvc.name="shared-storage-pvc"
```

#### Option 2: Azure Blob Storage with BlobFuse

Blob storage provides cost-effective storage with good performance for most training scenarios.

```bash
helm install shared-storage ../../../storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set pvc.name="shared-storage-pvc" \
  --set-json 'storage.mountOptions=["-o allow_other","--use-attr-cache=true","--cancel-list-on-mount-seconds=10","-o attr_timeout=120","-o entry_timeout=120","-o negative_timeout=120","--log-level=LOG_WARNING","--file-cache-timeout-in-seconds=120","--block-cache","--block-cache-block-size=32","--block-cache-parallelism=80"]'
```

#### Verify Deployment

```bash
# Check PVC status
kubectl get pvc shared-storage-pvc

# Verify storage class and capacity
kubectl describe pvc shared-storage-pvc
``` 

### 3.2. Dataset Preparation

Prepare and preprocess the [SlimPajama 627B dataset](https://huggingface.co/datasets/cerebras/SlimPajama-627B) for Megatron-LM training. The dataset preparation uses a unified Helm chart that orchestrates four sequential stages: download, extract, concatenate, and preprocess. The pipeline uses filesystem markers to track stage completion and allows customization of parallelism and resources for each step.

The preparation pipeline is based on modified scripts from the [NVIDIA DGX Cloud documentation](https://docs.nvidia.com/dgx-cloud/run-ai/latest/nemo-e2e-example.html).

#### Quick Test with Sample Dataset

For initial testing and validation, run the pipeline with a limited dataset:

```bash
helm install prepare-data helm/prepare-data \
  --set pipeline.fullDataset=false \
  --set pipeline.sampleFiles=100 \
  --set pvc.name=shared-storage-pvc
```

This creates a smaller dataset suitable for testing, with typical file sizes:

**Sample Dataset File Sizes (Reference)**

| Directory | Files | Size | Description |
|-----------|-------|------|-------------|
| `slimpajama/downloaded` | 100 | 1.5G | Original compressed .zst files |
| `slimpajama/extracted` | 100 | 4.2G | Extracted .jsonl files |
| `slimpajama/concatenated` | 1 | 4.2G | Combined training file |
| `slimpajama/bpe` | 2 | 1.4M | Byte-pair encoding files |
| `slimpajama/preprocessed` | 1 | 2.0G | Final Megatron binary format |

#### Full Dataset Preparation

To prepare the complete SlimPajama 627B dataset (approximately 900 GiB compressed):

```bash
helm install prepare-data helm/prepare-data \
  --set pipeline.fullDataset=true \
  --set pvc.name=shared-storage-pvc
```

**Note**: The full dataset preparation will take several hours. Consider using a Hugging Face Pro account to avoid throttling when downloading large datasets.

#### Pipeline Stages

The data preparation pipeline executes four sequential stages:

1. **Download**: Retrieves compressed `.zst` files from Hugging Face
2. **Extract**: Converts from `.zst` format to `.jsonl` format
3. **Concatenate**: Combines individual files into training chunks
4. **Preprocess**: Converts to Megatron's binary format (`.bin`/`.idx` files)

Each stage uses filesystem markers to track completion.

#### Monitor Pipeline Progress

```bash
# Check overall pipeline status
kubectl get job prepare-data

# Follow pipeline logs
kubectl logs -f job/prepare-data

# Check stage-specific progress
kubectl exec -it job/prepare-data -- ls -la /data/slimpajama/

# Monitor current stage marker files
kubectl exec -it job/prepare-data -- find /data/slimpajama/ -name "*.marker" -ls
```

#### Verify Dataset Preparation

```bash
# Check final preprocessed files
kubectl run verify-dataset --rm -i --tty --image=ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest -- \
  bash -c "ls /data/slimpajama/preprocessed/*.bin | wc -l && du -sh /data/slimpajama/preprocessed"

# Verify all pipeline stages completed
kubectl run verify-stages --rm -i --tty --image=ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest -- \
  bash -c "for stage in downloaded extracted concatenated preprocessed; do echo -n \"\$stage: \"; [ -f /data/slimpajama/\$stage.marker ] && echo 'COMPLETE' || echo 'PENDING'; done"
```

### 3.3. Model Training

Execute distributed model training using the PyTorch Operator. The training process supports various model sizes and configurations.

#### Model Size Options

The chart supports several predefined model configurations:

- **175b**: 96 layers, 12288 hidden size, 96 attention heads (full GPT-3 175B)
- **30b**: 48 layers, 7168 hidden size, 56 attention heads  
- **13b**: 40 layers, 5120 hidden size, 40 attention heads
- **1.3b**: 24 layers, 2048 hidden size, 16 attention heads
- **857m**: 24 layers, 1024 hidden size, 16 attention heads
- **375m**: 12 layers, 512 hidden size, 8 attention heads (good for testing)
- **125m**: 12 layers, 768 hidden size, 12 attention heads

#### Quick Test with 375M Model

Execute a lightweight training run for validation and testing:

```bash
helm install megatron-training helm/megatron-training \
  --set image.tag=latest \
  --set model.size="375m" \
  --set training.nodes=2 \
  --set training.gpusPerNode=8 \
  --set training.iterations=100 \
  --set training.globalBatchSize=32 \
  --set storage.pvcName="shared-storage-pvc" \
  --set storage.datasetPath="slimpajama/preprocessed"
```

#### Large Scale Training with 175B Model

Deploy a full-scale GPT-3 175B training configuration:

```bash
helm install megatron-training helm/megatron-training \
  --set image.tag=latest \
  --set model.size="175b" \
  --set training.nodes=64 \
  --set training.gpusPerNode=8 \
  --set training.iterations=10000 \
  --set training.globalBatchSize=8192 \
  --set training.saveInterval=1000 \
  --set training.evalInterval=1000 \
  --set storage.pvcName="shared-storage-pvc" \
  --set storage.datasetPath="slimpajama/preprocessed" \
  --set storage.checkpointPath="checkpoints/gpt175b" \
  --set storage.logsPath="logs/gpt175b"
```

#### Custom Model Configuration

For custom model architectures, override the model parameters directly:

```bash
helm install megatron-training helm/megatron-training \
  --set image.tag=latest \
  --set model.size="custom" \
  --set model.custom.numLayers=24 \
  --set model.custom.hiddenSize=1024 \
  --set model.custom.numAttentionHeads=16 \
  --set model.custom.seqLength=2048 \
  --set model.custom.tensorModelParallelSize=1 \
  --set model.custom.pipelineModelParallelSize=1 \
  --set training.nodes=4 \
  --set storage.pvcName="shared-storage-pvc"
```

#### Enable SHARP Acceleration

For clusters with Mellanox InfiniBand and SHARP support:

```bash
helm install megatron-training helm/megatron-training \
  --set model.size="175b" \
  --set training.useSharp=1 \
  --set training.nodes=32 \
  --set storage.pvcName="shared-storage-pvc"
```

#### Monitor Training Progress

```bash
# Check PyTorchJob status
kubectl get pytorchjob megatron-training

# Follow master node logs
kubectl logs -f megatron-training-master-0

# Check all worker logs
kubectl logs -l job-name=megatron-training

# Monitor resource usage
kubectl top pods -l job-name=megatron-training
```

#### Access TensorBoard

```bash
# Port-forward to access TensorBoard
kubectl port-forward service/tensorboard 6006:6006

# Open http://localhost:6006 in your browser
```

#### Checkpoint Management

```bash
# Check checkpoint files
kubectl run check-checkpoints --rm -i --tty --image=ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest -- \
  bash -c "ls -la /data/checkpoints/"

# Monitor checkpoint sizes
kubectl run check-checkpoint-size --rm -i --tty --image=ghcr.io/azure/ai-infrastructure-on-azure/megatron-lm:latest -- \
  bash -c "du -sh /data/checkpoints/*"
```

## Key Configuration Parameters

- **`training.nodes`**: Number of worker nodes for distributed training
- **`training.gpusPerNode`**: GPU count per node (typically 8 for ND-series VMs)
- **`training.globalBatchSize`**: Global batch size across all GPUs (should scale with GPU count)
- **`training.iterations`**: Total number of training iterations
- **`training.saveInterval`**: Checkpoint frequency (iterations between saves)
- **`training.evalInterval`**: Evaluation frequency (iterations between evaluations)
- **`training.useSharp`**: Enable SHARP acceleration (0 or 1)
- **`model.size`**: Predefined model size or "custom" for manual configuration
- **`storage.pvcName`**: Name of the persistent volume claim for shared storage

## Performance Considerations

- **Batch Size Scaling**: Approximately 16 × number of GPUs for optimal throughput
- **Checkpoint Frequency**: Balance between training progress preservation and I/O overhead
- **Storage Performance**: AMLFS provides better checkpoint write performance than Blob storage
- **Network Optimization**: RDMA and SHARP provide significant performance improvements for large-scale training
- **Memory Requirements**: Ensure sufficient CPU memory allocation (typically 64-128GB per GPU)
