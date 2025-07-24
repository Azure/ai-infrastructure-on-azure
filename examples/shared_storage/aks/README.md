# Shared Storage Helm Charts for AKS

This directory contains Helm charts for deploying ReadWriteMany storage options on Azure Kubernetes Service (AKS).

## Available Storage Options

* **Blob Shared Storage** (`blob-shared-storage`) - Cost-effective storage using Azure Blob with BlobFuse
* **AMLFS Shared Storage** (`amlfs-shared-storage`) - High-performance storage using Azure Managed Lustre File System

## Blob Shared Storage

Provides shared storage using Azure Blob Storage mounted with BlobFuse. This option offers cost-effective storage with good performance for most workloads.

For detailed configuration options, see the [Azure Storage Fuse documentation](https://github.com/Azure/azure-storage-fuse). For optimal performance tuning, refer to the [configuration guide](https://github.com/Azure/azure-storage-fuse?tab=readme-ov-file#config-guide).

### Deployment Example

```bash
helm install shared-storage ./blob-shared-storage \
  --set pvc.name="shared-storage-pvc"
```

With optimized mount options for multiple clients writing large, independent files:

```bash
helm install shared-storage ./blob-shared-storage \
  --set pvc.name="shared-storage-pvc" \
  --set-json 'storage.mountOptions=["-o allow_other","--use-attr-cache=true","--cancel-list-on-mount-seconds=10","-o attr_timeout=120","-o entry_timeout=120","-o negative_timeout=120","--log-level=LOG_WARNING","--file-cache-timeout-in-seconds=120","--block-cache","--block-cache-block-size=32","--block-cache-parallelism=80"]'
```


## AMLFS Shared Storage

Provides high-throughput, low-latency shared storage using Azure Managed Lustre File System. AMLFS is optimized for large-scale, performance-critical workloads that require fast I/O operations.

### Available SKUs

AMLFS offers different performance tiers with varying throughput and storage requirements:

| SKU | Throughput per TiB | Storage Minimum | Storage Maximum | Increment |
|-----|-------------------|-----------------|-----------------|-----------|
| `AMLFS-Durable-Premium-40` | 40 MBps | 48 TiB | 1536 TiB | 48 TiB |
| `AMLFS-Durable-Premium-125` | 125 MBps | 16 TiB | 512 TiB | 16 TiB |
| `AMLFS-Durable-Premium-250` | 250 MBps | 8 TiB | 256 TiB | 8 TiB |
| `AMLFS-Durable-Premium-500` | 500 MBps | 4 TiB | 128 TiB | 4 TiB |

For detailed information about throughput configurations, see the [Azure Managed Lustre documentation](https://learn.microsoft.com/en-us/azure/azure-managed-lustre/create-file-system-portal#throughput-configurations).

### Deployment Example

This is an example of 16TiB filesystem with 2GBps total throughput:

```bash
helm install shared-storage ./amlfs-shared-storage \
  --set storage.amlfs.skuName="AMLFS-Durable-Premium-125" \
  --set storage.size=16 \
  --set pvc.name="shared-storage-pvc"
```