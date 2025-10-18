# LLM Foundry MPT Training on AKS

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites and AKS Environment Setup](#2-prerequisites-and-aks-environment-setup)
3. [Deployment Steps](#3-deployment-steps)
   
   3.1. [Shared Storage Configuration](#31-shared-storage-configuration)
   
   3.2. [Dataset Preparation](#32-dataset-preparation)
   
   3.3. [Model Training](#33-model-training)

## 1. Introduction

This example demonstrates how to train Mosaic Pretrained Transformer (MPT) models using Azure Kubernetes Service (AKS). The solution utilizes Helm charts to orchestrate containerized training workloads with distributed computing capabilities across GPU-enabled AKS nodes.

The implementation leverages several key technologies:

- **[LLM-Foundry](https://github.com/mosaicml/llm-foundry)** - MosaicML's framework for training, fine-tuning, and deploying large language models efficiently
- **[LLM-Foundry Training Walkthrough](https://github.com/mosaicml/llm-foundry/tree/main/scripts/train)** - Comprehensive training scripts and examples
- **[C4 (Colossal, Cleaned, Common Crawl) Dataset](https://huggingface.co/datasets/allenai/c4)** - High-quality training dataset for language models
- **PyTorch Operator** - Kubernetes-native distributed PyTorch training orchestration

## 2. Prerequisites and AKS Environment Setup

Before proceeding with the training deployment, ensure your AKS cluster meets the following requirements:

- **PyTorch Operator** installed for distributed training coordination
- **Blob Storage CSI Driver** enabled for data storage integration  
- **GPU-enabled node pools** with appropriate VM SKUs (e.g., Standard_NC24ads_A100_v4)
- **RDMA networking** configured for high-performance inter-node communication

Follow the [infrastructure reference documentation](../../../infrastructure_references/aks/README.md) for detailed AKS cluster setup and configuration.

## 3. Deployment Steps

### 3.1. Shared Storage Configuration

Deploy shared storage infrastructure to provide persistent, scalable storage accessible across all training pods. The shared storage Helm charts are located in `storage_references/aks/shared_storage/helm` and offer two storage options. For detailed configuration options and setup instructions, see the [shared storage README](../../../storage_references/aks/shared_storage/README.md).

#### Option 1: Azure Managed Lustre File System (AMLFS)

AMLFS delivers high-throughput, low-latency storage optimized for large-scale training workloads. 

AMLFS offers different performance tiers with bandwidth scaling per Ti
B of storage. The tier and size can be tuned for your cluster requirements. This example uses the 125 MB/s/TiB tier with 16TiB total storage capacity.

```bash
helm install shared-storage ../../../storage_references/aks/shared_storage/helm/amlfs-shared-storage \
  --set storage.amlfs.skuName="AMLFS-Durable-Premium-125" \
  --set storage.size="16Ti" \
  --set storage.pvc.name="shared-storage-pvc"
```

#### Option 2: Azure Blob Storage with BlobFuse

Blob storage provides cost-effective storage with excellent performance for most training scenarios.

LLM Foundry can minimize data reading latencies through local/remote data sources, where data is staged locally from remote storage asynchronously. Sharded checkpoints enable each process to write its own file. Following the [BlobFuse configuration guide](https://github.com/Azure/azure-storage-fuse?tab=readme-ov-file#config-guide), block cache provides optimal performance.

Example deployment:

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

Prepare and preprocess the training dataset using the C4 corpus. This step downloads the raw data, tokenizes it, and converts it to the format required by LLM Foundry.

To download the full data:

```bash
helm install dataset-prep helm/dataset-download \
  --set storage.pvcName="shared-storage-pvc" \
  --set dataset.outputPath="my-copy-c4"
```

Download the small data set for testing:

```bash
helm install dataset-prep helm/dataset-download \
  --set storage.pvcName="shared-storage-pvc" \
  --set dataset.outputPath="my-copy-c4" \
  --set dataset.splits="{train_small,val_small}"
```

### 3.3. Model Training

Execute distributed model training using the PyTorch Operator. The training process supports data streaming from blob storage to local node storage for optimal I/O performance.

#### Storage Strategy:

The training implementation uses a dual-storage approach:
- **Remote storage** (`data_remote`): Blob storage containing the complete dataset
- **Local storage** (`data_local`): Fast local disk (typically `/tmp` on ephemeral OS disk) for caching

This design enables asynchronous data streaming to local node storage, minimizing I/O latency and maximizing GPU utilization. For enhanced performance, consider:
- **Local NVMe provisioner** for dedicated high-speed local storage
- **Azure Container Storage** (when available) to aggregate multiple NVMe disks across nodes

#### Training Configuration Options:

- **`model.config`**: Pre-defined model architecture (e.g., `mpt-125m`, `mpt-13b`, `mpt-30b`)
- **`training.nodes`**: Number of worker nodes for distributed training (default: `2`)
- **`training.gpusPerNode`**: GPU count per node (default: `8`)
- **`resources.rdmaResource`**: RDMA network resource type (default: `rdma/ib`)
- **`resources.shmSize`**: Shared memory allocation for containers (default: `64Gi`)
- **`yamlUpdates`**: Dynamic configuration overrides for training parameters

#### Checkpointing Configuration:

- **`save_folder`**: Checkpoint storage location in shared storage
- **`save_interval`**: Checkpoint frequency (e.g., `500ba` = every 500 batches)
- **`save_num_checkpoints_to_keep`**: Checkpoint retention policy
- **`fsdp_config.state_dict_type`**: Checkpoint format (`sharded` for parallel I/O, `full` for single-file checkpoints)

#### Quick Test with MPT-125M

Execute a lightweight training run using the MPT-125M model and the small dataset for validation and testing:

```bash
helm install llm-training helm/llm-training \
  --set image.tag=latest \
  --set model.config="mpt-125m" \
  --set storage.pvcName="shared-storage-pvc" \
  --set "yamlUpdates.train_loader\.dataset\.split=train_small" \
  --set "yamlUpdates.eval_loader\.dataset\.split=val_small" \
  --set "yamlUpdates.variables\.data_remote=/data/my-copy-c4" \
  --set "yamlUpdates.variables\.data_local=/tmp/my-copy-c4"
```

#### Large Training with MPT-30B

Deploy a MPT 30B training configuration with checkpointing enabled and the full dataset:

```bash
helm install llm-training helm/llm-training \
  --set image.tag=latest \
  --set model.config="mpt-30b" \
  --set training.nodes=16 \
  --set storage.pvcName="shared-storage-pvc" \
  --set "yamlUpdates.variables\.data_remote=/data/my-copy-c4" \
  --set "yamlUpdates.variables\.data_local=/tmp/my-copy-c4" \
  --set "yamlUpdates.save_folder=/data/checkpoints" \
  --set "yamlUpdates.save_interval=1000ba" \
  --set "yamlUpdates.save_num_checkpoints_to_keep=10" \
  --set "yamlUpdates.fsdp_config\.state_dict_type=sharded"
```


