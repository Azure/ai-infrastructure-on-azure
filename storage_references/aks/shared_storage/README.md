# Shared Storage Helm Charts for AKS

## Table of Contents

1. [Overview](#1-overview)
2. [Available Storage Options](#2-available-storage-options)
3. [Blob Shared Storage](#3-blob-shared-storage)
4. [AMLFS Shared Storage](#4-amlfs-shared-storage)
5. [Azure Files Premium NFS](#5-azure-files-premium-nfs)

## 1. Overview

This directory contains Helm charts for deploying ReadWriteMany storage options on Azure Kubernetes Service (AKS). Each chart supports two provisioning modes:

- **Dynamic** (default) — Kubernetes creates and manages the storage resource automatically.
- **Static** — Mount an existing Azure storage resource that you manage outside of Kubernetes.

Set `storage.provisioning` to `"dynamic"` or `"static"` to choose the mode.

## 2. Available Storage Options

- **Blob Shared Storage** (`blob-shared-storage`) — Cost-effective storage using Azure Blob with BlobFuse. Supports dynamic provisioning (new account) and static provisioning (existing account).
- **AMLFS Shared Storage** (`amlfs-shared-storage`) — High-performance storage using Azure Managed Lustre File System. Supports dynamic provisioning (new AMLFS instance) and static provisioning (existing AMLFS instance).
- **Azure Files Premium NFS** (`azurefiles-shared-storage`) — Shared NFSv4.1 storage using Azure Files Premium. Supports dynamic provisioning (new file share) and static provisioning (existing file share).

## 3. Blob Shared Storage

Provides shared storage using Azure Blob Storage mounted with BlobFuse. This option offers cost-effective storage with good performance for most workloads.

For detailed configuration options, see the [Azure Storage Fuse documentation](https://github.com/Azure/azure-storage-fuse). For optimal performance tuning, refer to the [configuration guide](https://github.com/Azure/azure-storage-fuse?tab=readme-ov-file#config-guide).

### 3.1 Dynamic Provisioning (default)

Kubernetes dynamically creates a new Azure Blob Storage account and container.

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set storage.pvcName="shared-storage-pvc"
```

With optimized mount options for multiple clients writing large, independent files:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set storage.pvcName="shared-storage-pvc" \
  --set-json 'storage.mountOptions=["-o allow_other","--use-attr-cache=true","--cancel-list-on-mount-seconds=10","-o attr_timeout=120","-o entry_timeout=120","-o negative_timeout=120","--log-level=LOG_WARNING","--file-cache-timeout-in-seconds=120","--block-cache","--block-cache-block-size=32","--block-cache-parallelism=80"]'
```

### 3.2 Static Provisioning (existing storage account)

Mount an existing Azure Blob Storage account. Use this when you already have a storage account with data that you want to make available to your AKS workloads.

#### Authentication

The AKS kubelet managed identity is used to authenticate to the storage account. The identity must have the **Storage Blob Data Contributor** role on the storage account.

#### Prerequisites

```bash
# Get the kubelet identity object ID
KUBELET_IDENTITY=$(az aks show \
  --name "${CLUSTER_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query identityProfile.kubeletidentity.objectId -o tsv)

# Assign Storage Blob Data Contributor role
az role assignment create \
  --assignee-object-id "${KUBELET_IDENTITY}" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<STORAGE_RG>/providers/Microsoft.Storage/storageAccounts/<STORAGE_ACCOUNT>"
```

#### Deployment with Managed Identity

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set storage.provisioning=static \
  --set storage.storageAccount.name="mystorageaccount" \
  --set storage.storageAccount.resourceGroup="my-storage-rg" \
  --set storage.storageAccount.containerName="mycontainer" \
  --set storage.pvcName="shared-storage-pvc"
```

### 3.3 Configuration Reference

| Parameter | Default | Description |
|---|---|---|
| `storage.provisioning` | `dynamic` | `"dynamic"` or `"static"` |
| `storage.pvcName` | `shared-blob-storage` | Name of the PVC to create |
| `storage.size` | `100Ti` | Storage size |
| `storage.skuName` | `Standard_LRS` | Azure storage SKU (dynamic only) |
| `storage.accessModes` | `[ReadWriteMany]` | PVC access modes |
| `storage.reclaimPolicy` | `Delete` | PV reclaim policy (`Retain` recommended for static) |
| `storage.volumeBindingMode` | `Immediate` | Volume binding mode (dynamic only) |
| `storage.storageAccount.name` | `""` | Existing storage account name (static only, **required**) |
| `storage.storageAccount.resourceGroup` | `""` | Storage account resource group (static only, **required**) |
| `storage.storageAccount.containerName` | `""` | Blob container name (static only, **required**) |
| `storage.mountOptions` | See values.yaml | BlobFuse mount options |

### 3.4 Performance Testing

You can test blobfuse performance using the FIO testing tool. See the [FIO testing documentation](../../../infrastructure_validations/aks/fio/README.md) for detailed examples.

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

### 4.1 Dynamic Provisioning (default)

Kubernetes dynamically provisions a new AMLFS instance.

#### Available SKUs

| SKU                         | Throughput per TiB | Storage Minimum | Storage Maximum | Increment |
| --------------------------- | ------------------ | --------------- | --------------- | --------- |
| `AMLFS-Durable-Premium-40`  | 40 MB/s            | 48 TiB          | 12.5 PiB        | 48 TiB    |
| `AMLFS-Durable-Premium-125` | 125 MB/s           | 16 TiB          | 4 PiB           | 16 TiB    |
| `AMLFS-Durable-Premium-250` | 250 MB/s           | 8 TiB           | 2 PiB           | 8 TiB     |
| `AMLFS-Durable-Premium-500` | 500 MB/s           | 4 TiB           | 1 PiB           | 4 TiB     |

For detailed information about throughput configurations, see the [Azure Managed Lustre documentation](https://learn.microsoft.com/en-us/azure/azure-managed-lustre/create-file-system-portal#throughput-configurations).

#### Deployment Example

16 TiB filesystem with 2 GB/s total throughput:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/amlfs-shared-storage \
  --set storage.amlfs.skuName="AMLFS-Durable-Premium-125" \
  --set storage.size=16Ti \
  --set storage.pvcName="shared-storage-pvc"
```

### 4.2 Static Provisioning (existing AMLFS instance)

Mount an existing Azure Managed Lustre File System instance. Use this when you have already provisioned AMLFS outside of Kubernetes (e.g., via the Azure portal, Bicep, or Terraform).

#### Prerequisites

- The Azure Lustre CSI driver must be installed in the AKS cluster (see [infrastructure_references/aks](../../infrastructure_references/aks/README.md))
- The AKS nodes must have network connectivity to the AMLFS MGS IP address
- You need the **MGS IP address** of the existing AMLFS instance (found in the Azure portal under the AMLFS resource → Client connection)

#### Deployment Example

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/amlfs-shared-storage \
  --set storage.provisioning=static \
  --set storage.existingFilesystem.mgsIPAddress="10.0.0.4" \
  --set storage.existingFilesystem.filesystemName="lustrefs" \
  --set storage.size=16Ti \
  --set storage.pvcName="shared-storage-pvc"
```

### 4.3 Configuration Reference

| Parameter | Default | Description |
|---|---|---|
| `storage.provisioning` | `dynamic` | `"dynamic"` or `"static"` |
| `storage.pvcName` | `shared-amlfs-storage` | Name of the PVC to create |
| `storage.size` | `16Ti` | Storage size |
| `storage.accessModes` | `[ReadWriteMany]` | PVC access modes |
| `storage.reclaimPolicy` | `Delete` | PV reclaim policy (`Retain` recommended for static) |
| `storage.volumeBindingMode` | `Immediate` | Volume binding mode (dynamic only) |
| `storage.amlfs.skuName` | `AMLFS-Durable-Premium-125` | AMLFS SKU (dynamic only) |
| `storage.amlfs.zones` | `1` | Availability zone (dynamic only) |
| `storage.amlfs.maintenanceDayOfWeek` | `Sunday` | Maintenance day (dynamic only) |
| `storage.amlfs.maintenanceTimeOfDayUtc` | `02:00` | Maintenance time UTC (dynamic only) |
| `storage.existingFilesystem.mgsIPAddress` | `""` | MGS IP address (static only, **required**) |
| `storage.existingFilesystem.filesystemName` | `lustrefs` | Lustre filesystem name (static only) |
| `storage.mountOptions` | `["noatime", "flock"]` | Lustre mount options |

## 5. Azure Files Premium NFS

Provides high-performance shared storage using Azure Files Premium with NFSv4.1 protocol. Azure Files Premium NFS offers low-latency, high-throughput file storage optimized for enterprise workloads.

For detailed information, see the [Azure Files NFS documentation](https://learn.microsoft.com/en-us/azure/storage/files/files-nfs-protocol).

### 5.1 Dynamic Provisioning (default)

Kubernetes dynamically provisions a new Azure Files Premium NFS share.

#### Deployment Example

100 GiB file share with optimized NFS mount options:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/azurefiles-shared-storage \
  --set storage.size=100Gi \
  --set storage.pvcName="shared-storage-pvc"
```

With custom mount options for maximum throughput:

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/azurefiles-shared-storage \
  --set storage.size=1Ti \
  --set storage.pvcName="shared-storage-pvc" \
  --set-json 'storage.mountOptions=["nconnect=8","rsize=1048576","wsize=1048576","actimeo=30","noresvport"]'
```

### 5.2 Static Provisioning (existing file share)

Mount an existing Azure Files Premium NFS share. Use this when you already have a file share with data that you want to make available to your AKS workloads.

#### Prerequisites

- The existing storage account must have **Premium** performance tier
- The file share must use **NFS** protocol (cannot be changed after creation)
- The AKS cluster must have network connectivity to the storage account (via VNet integration or private endpoint)
- The storage account must allow access from the AKS subnet (network rules or private endpoint)

#### Deployment Example

```bash
helm install shared-storage storage_references/aks/shared_storage/helm/azurefiles-shared-storage \
  --set storage.provisioning=static \
  --set storage.existingFileShare.storageAccountName="mystorageaccount" \
  --set storage.existingFileShare.resourceGroup="my-storage-rg" \
  --set storage.existingFileShare.shareName="myshare" \
  --set storage.size=100Gi \
  --set storage.pvcName="shared-storage-pvc"
```

### 5.3 Mount Options Reference

The chart uses optimized mount options for high-performance NFS access:

| Option | Default Value | Description |
|--------|---------------|-------------|
| `nconnect` | `8` | Number of TCP connections. Maximum 8 for NFS 4.1. Improves throughput for parallel I/O. |
| `rsize` | `1048576` | Read buffer size (1 MiB). Optimized for large sequential reads. |
| `wsize` | `1048576` | Write buffer size (1 MiB). Optimized for large sequential writes. |
| `actimeo` | `30` | Attribute cache timeout in seconds. Balances consistency and performance. |
| `noresvport` | - | Do not use privileged source port. Required for some network configurations. |

### 5.4 Configuration Reference

| Parameter | Default | Description |
|---|---|---|
| `storage.provisioning` | `dynamic` | `"dynamic"` or `"static"` |
| `storage.pvcName` | `shared-azurefiles-storage` | Name of the PVC to create |
| `storage.size` | `100Gi` | Storage size (minimum 100Gi for Premium NFS) |
| `storage.accessModes` | `[ReadWriteMany]` | PVC access modes |
| `storage.reclaimPolicy` | `Delete` | PV reclaim policy (`Retain` recommended for static) |
| `storage.volumeBindingMode` | `Immediate` | Volume binding mode (dynamic only) |
| `storage.azureFiles.skuName` | `Premium_LRS` | Azure Files SKU (dynamic only) |
| `storage.azureFiles.protocol` | `nfs` | Protocol type (dynamic only) |
| `storage.existingFileShare.storageAccountName` | `""` | Storage account name (static only, **required**) |
| `storage.existingFileShare.resourceGroup` | `""` | Resource group (static only, **required**) |
| `storage.existingFileShare.shareName` | `""` | File share name (static only, **required**) |
| `storage.mountOptions` | See values.yaml | NFS mount options |

### 5.5 Network Requirements

Azure Files NFS requires network connectivity between AKS nodes and the storage account:

1. **VNet Integration** (recommended): Deploy the storage account with a private endpoint in the same VNet as AKS, or in a peered VNet.

2. **Service Endpoint**: Enable the `Microsoft.Storage` service endpoint on the AKS subnet and configure storage account network rules.

3. **Private Endpoint**: Use Azure Private Link to expose the Azure Files NFS endpoint through a private IP in your VNet.

Example creating a private endpoint:

```bash
# Create private endpoint for the storage account
az network private-endpoint create \
  --name "${STORAGE_ACCOUNT}-pe" \
  --resource-group "${RESOURCE_GROUP}" \
  --vnet-name "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --private-connection-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${STORAGE_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
  --group-id file \
  --connection-name "${STORAGE_ACCOUNT}-connection"
```


