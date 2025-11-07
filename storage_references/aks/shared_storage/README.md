# Shared Storage Helm Charts for AKS

## Table of Contents

1. [Overview](#1-overview)
2. [Available Storage Options](#2-available-storage-options)
3. [Blob Shared Storage](#3-blob-shared-storage)
4. [AMLFS Shared Storage](#4-amlfs-shared-storage)

## 1. Overview

This directory contains Helm charts for deploying ReadWriteMany storage options on Azure Kubernetes Service (AKS).

## 2. Available Storage Options

- **Blob Shared Storage** (`blob-shared-storage`) - Cost-effective storage using Azure Blob with BlobFuse
- **AMLFS Shared Storage** (`amlfs-shared-storage`) - High-performance storage using Azure Managed Lustre File System

## 3. Blob Shared Storage

Provides shared storage using Azure Blob Storage mounted with BlobFuse. This option offers cost-effective storage with good performance for most workloads.

For detailed configuration options, see the [Azure Storage Fuse documentation](https://github.com/Azure/azure-storage-fuse). For optimal performance tuning, refer to the [configuration guide](https://github.com/Azure/azure-storage-fuse?tab=readme-ov-file#config-guide).

### Deployment Example

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set pvc.name="shared-storage-pvc"
```

With optimized mount options for multiple clients writing large, independent files:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set pvc.name="shared-storage-pvc" \
  --set-json 'storage.mountOptions=["-o allow_other","--use-attr-cache=true","--cancel-list-on-mount-seconds=10","-o attr_timeout=120","-o entry_timeout=120","-o negative_timeout=120","--log-level=LOG_WARNING","--file-cache-timeout-in-seconds=120","--block-cache","--block-cache-block-size=32","--block-cache-parallelism=80"]'
```

### Performance Testing

You can test blobfuse performance using the FIO testing tool. See the [FIO testing documentation](../../infrastructure_validations/aks/fio/README.md) for detailed examples.

#### Block Cache Sequential Write Test

Test large block sequential writes using blobfuse block cache:

```bash
helm install fio-test infrastructure_validations/aks/fio/helm/fio -f - <<EOF
storage:
  type: "blobfuse"
  size: "10Gi"
  blobfuse:
    skuName: "Standard_LRS"
    mountOptions:
      - "-o allow_other"
      - "--use-attr-cache=true"
      - "--cancel-list-on-mount-seconds=10"
      - "-o attr_timeout=120"
      - "-o entry_timeout=120"
      - "-o negative_timeout=120"
      - "--log-level=LOG_WARNING"
      - "--block-cache"
      - "--block-cache-block-size=32"

fio:
  testName: "sequential-write-test"
  filename: "/mnt/test/testfile.img"
  size: "10G"
  blockSize: "4M"
  readWrite: "write"
  ioEngine: "libaio"
  direct: 1
  numJobs: 1
  runtime: 0
  timeBased: false
  additionalOptions: "--group_reporting"

resources:
  limits:
    cpu: "2"
    memory: "8Gi"
  requests:
    cpu: "1"
    memory: "4Gi"
EOF
```

#### File Cache Sequential Write Test

Test large block sequential writes using blobfuse file cache:

```bash
helm install fio-test infrastructure_validations/aks/fio/helm/fio -f - <<EOF
storage:
  type: "blobfuse"
  size: "10Gi"
  blobfuse:
    skuName: "Standard_LRS"
    mountOptions:
      - "-o allow_other"
      - "--use-attr-cache=true"
      - "--cancel-list-on-mount-seconds=10"
      - "-o attr_timeout=120"
      - "-o entry_timeout=120"
      - "-o negative_timeout=120"
      - "--log-level=LOG_WARNING"
      - "--file-cache-timeout=600"
      - "--tmp-path=/tmp/blobfuse"
      - "--lazy-write"

fio:
  testName: "sequential-write-test"
  filename: "/mnt/test/testfile.img"
  size: "10G"
  blockSize: "4M"
  readWrite: "write"
  ioEngine: "libaio"
  direct: 1
  numJobs: 1
  runtime: 0
  timeBased: false
  additionalOptions: "--group_reporting"

resources:
  limits:
    cpu: "2"
    memory: "8Gi"
  requests:
    cpu: "1"
    memory: "4Gi"
EOF
```

## 4. AMLFS Shared Storage

Provides high-throughput, low-latency shared storage using Azure Managed Lustre File System. AMLFS is optimized for large-scale, performance-critical workloads that require fast I/O operations.

### Available SKUs

AMLFS offers different performance tiers with varying throughput and storage requirements:

| SKU                         | Throughput per TiB | Storage Minimum | Storage Maximum | Increment |
| --------------------------- | ------------------ | --------------- | --------------- | --------- |
| `AMLFS-Durable-Premium-40`  | 40 MB/s            | 48 TiB          | 12.5 PiB        | 48 TiB    |
| `AMLFS-Durable-Premium-125` | 125 MB/s           | 16 TiB          | 4 PiB           | 16 TiB    |
| `AMLFS-Durable-Premium-250` | 250 MB/s           | 8 TiB           | 2 PiB           | 8 TiB     |
| `AMLFS-Durable-Premium-500` | 500 MB/s           | 4 TiB           | 1 PiB           | 4 TiB     |

For detailed information about throughput configurations, see the [Azure Managed Lustre documentation](https://learn.microsoft.com/en-us/azure/azure-managed-lustre/create-file-system-portal#throughput-configurations).

### Deployment Example

This is an example of 16TiB filesystem with 2GB/s total throughput:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/amlfs-shared-storage \
  --set storage.amlfs.skuName="AMLFS-Durable-Premium-125" \
  --set storage.size=16Ti \
  --set pvc.name="shared-storage-pvc"
```
