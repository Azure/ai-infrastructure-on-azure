# Azure Container Storage for AKS

## Overview

Azure Container Storage is a cloud-based volume management, deployment, and orchestration service built natively for containers. It integrates with Kubernetes, providing persistent storage options optimized for containerized workloads.

This directory contains examples and documentation for using Azure Container Storage with AKS clusters.

## Prerequisites

- AKS cluster with Azure Container Storage enabled
- Azure CLI version that supports `--enable-azure-container-storage` flag
- kubectl configured to access your AKS cluster

## Enabling Azure Container Storage

Azure Container Storage can be enabled during AKS cluster creation using the deployment script:

### Default Configuration

Enable Azure Container Storage with default settings:

```bash
export AZURE_REGION="eastus"
export NODE_POOL_VM_SIZE="Standard_ND96isr_H100_v5"
export ENABLE_AZURE_CONTAINER_STORAGE="true"

./infrastructure_references/aks/scripts/deploy-aks.sh deploy-aks
```

### Specify Storage Pool Type

Enable Azure Container Storage with a specific storage pool type:

```bash
export AZURE_REGION="eastus"
export NODE_POOL_VM_SIZE="Standard_ND96isr_H100_v5"
export ENABLE_AZURE_CONTAINER_STORAGE="true"
export AZURE_CONTAINER_STORAGE_TYPE="ephemeralDisk"

./infrastructure_references/aks/scripts/deploy-aks.sh deploy-aks
```

## Storage Pool Types

Azure Container Storage supports multiple storage pool types:

### 1. ephemeralDisk

Uses local NVMe or temp disk on the node for high-performance, ephemeral storage.

**Best for:**
- Temporary data and scratch space
- High-performance workloads requiring low latency
- AI/ML training with NDv5 series VMs

**Characteristics:**
- Highest performance (lowest latency, highest IOPS)
- Data is ephemeral (lost when pod is deleted or node is recycled)
- No additional cost beyond the VM

**Example VM Series:**
- NDv5 series (e.g., Standard_ND96isr_H100_v5) - includes local NVMe SSDs

### 2. azureDisk

Uses Azure Managed Disks for persistent block storage.

**Best for:**
- General-purpose persistent storage
- Databases and stateful applications
- Workloads requiring data persistence

**Characteristics:**
- Persistent storage (data survives pod/node lifecycle)
- Supports snapshots and backups
- ReadWriteOnce access mode
- Additional cost for managed disks

### 3. elasticSan

Uses Azure Elastic SAN for high-performance, scalable block storage.

**Best for:**
- Large-scale mission-critical workloads
- High-performance databases
- Environments requiring massive scale and IOPS

**Characteristics:**
- Highest scale and performance tier
- Persistent storage with enterprise features
- Shared storage pools across multiple clusters
- Higher cost for premium features

## Examples

### Local NVMe with NDv5 VMs

The `examples/local-nvme-ndv5.yaml` file demonstrates using ephemeral disk storage with NDv5 series VMs:

```bash
# Deploy the example
kubectl apply -f storage_references/aks/azure_container_storage/examples/local-nvme-ndv5.yaml

# Verify the PVC is bound
kubectl get pvc ephemeraldisk-pvc

# Check the pod status
kubectl get pod fio-test-ephemeral
```

This example includes:
- A StorageClass configured for ephemeral disk storage
- A PersistentVolumeClaim requesting 100Gi
- A sample pod using the storage for testing

## Environment Variables

When using the deployment script, the following environment variables control Azure Container Storage:

- **`ENABLE_AZURE_CONTAINER_STORAGE`** - Enable Azure Container Storage (default: `false`)
  - Set to `true` to enable during cluster creation
  
- **`AZURE_CONTAINER_STORAGE_TYPE`** - Storage pool type (default: empty/default)
  - Options: `azureDisk`, `ephemeralDisk`, `elasticSan`
  - Leave empty to use Azure's default configuration

## Additional Resources

- [Azure Container Storage Documentation](https://learn.microsoft.com/en-us/azure/storage/container-storage/)
- [Install Azure Container Storage on AKS](https://learn.microsoft.com/en-us/azure/storage/container-storage/install-container-storage-aks)
- [Use Container Storage with Local Disk](https://learn.microsoft.com/en-us/azure/storage/container-storage/use-container-storage-with-local-disk)
- [NDv5 Series VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/ndv5-series)

## Performance Considerations

When using ephemeral disk storage with NDv5 VMs:

1. **Local NVMe Performance**: NDv5 VMs include multiple local NVMe SSDs providing exceptional IOPS and low latency
2. **Data Locality**: Storage is local to the node, providing best performance but no data persistence across node changes
3. **Capacity Planning**: Plan storage requests based on available local disk capacity on your VM SKU
4. **Workload Suitability**: Ideal for AI/ML training scratch space, caching layers, and temporary data processing

## Troubleshooting

### Check Azure Container Storage Status

```bash
# Check if Azure Container Storage is installed
kubectl get pods -n acstor

# View storage pools
kubectl get storagepool -n acstor

# Check available storage classes
kubectl get storageclass | grep acstor
```

### Verify Local Disk Availability

For ephemeral disk storage on NDv5 VMs:

```bash
# Check node resources
kubectl describe node <node-name> | grep -A 5 "Capacity"

# Verify local disk mounts
kubectl debug node/<node-name> -it --image=busybox -- df -h
```
