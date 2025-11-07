# Azure Container Storage for AKS - Ephemeral Disk

## Overview

Azure Container Storage is a cloud-based volume management service built natively for containers. This directory contains a Helm chart for deploying Azure Container Storage with ephemeral disk storage, which uses local NVMe or temp disks on nodes for high-performance, low-latency storage.

## Prerequisites

- AKS cluster with Azure Container Storage enabled with ephemeral disk
- Azure CLI version that supports `--enable-azure-container-storage` flag
- kubectl configured to access your AKS cluster

## Enabling Azure Container Storage

Azure Container Storage with ephemeral disk is enabled by default during AKS cluster creation using the deployment script:

```bash
export AZURE_REGION="eastus"
export NODE_POOL_VM_SIZE="Standard_ND96isr_H100_v5"

./infrastructure_references/aks/scripts/deploy-aks.sh deploy-aks
```

To disable Azure Container Storage during cluster creation:

```bash
export ENABLE_AZURE_CONTAINER_STORAGE="false"
./infrastructure_references/aks/scripts/deploy-aks.sh deploy-aks
```

## Ephemeral Disk Storage

Uses local NVMe or temp disk on the node for high-performance, ephemeral storage.

**Best for:**
- AI/ML training scratch space on NDv5 series VMs
- High-performance workloads requiring low latency
- Temporary data and caching

**Characteristics:**
- Highest performance (lowest latency, highest IOPS)
- Data is ephemeral (lost when pod is deleted or node is recycled)
- No additional cost beyond the VM
- Ideal for NDv5 series VMs with local NVMe SSDs

**Example VM Series:**
- NDv5 series (e.g., Standard_ND96isr_H100_v5) - includes local NVMe SSDs

## Deploying the Helm Chart

### Basic Deployment

```bash
helm install ephemeral-storage storage_references/aks/azure_container_storage/helm/ephemeral-disk-storage
```

### Custom Configuration

Create a custom values file or use `--set` flags:

```bash
helm install ephemeral-storage storage_references/aks/azure_container_storage/helm/ephemeral-disk-storage \
  --set storage.pvcName="my-ephemeral-pvc" \
  --set storage.size="200Gi"
```

### Verify Deployment

```bash
# Check the storage class
kubectl get storageclass acstor-ephemeraldisk-nvme

# Check the PVC
kubectl get pvc ephemeraldisk-pvc

# Describe the PVC to see details
kubectl describe pvc ephemeraldisk-pvc
```

## Using in Your Workloads

Reference the PVC in your pod specifications:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-workload
spec:
  containers:
    - name: app
      image: myapp:latest
      volumeMounts:
        - name: ephemeral-volume
          mountPath: /mnt/ephemeral
  volumes:
    - name: ephemeral-volume
      persistentVolumeClaim:
        claimName: ephemeraldisk-pvc
```

## Configuration Options

See `helm/ephemeral-disk-storage/values.yaml` for all configuration options:

- **storage.className**: StorageClass name (default: `acstor-ephemeraldisk-nvme`)
- **storage.pvcName**: PVC name (default: `ephemeraldisk-pvc`)
- **storage.size**: Storage size request (default: `100Gi`)
- **storage.accessModes**: Access modes (default: `ReadWriteOnce`)
- **storage.volumeBindingMode**: Volume binding mode (default: `WaitForFirstConsumer`)

## Performance Considerations

When using ephemeral disk storage with NDv5 VMs:

1. **Local NVMe Performance**: NDv5 VMs include multiple local NVMe SSDs providing exceptional IOPS and low latency
2. **Data Locality**: Storage is local to the node, providing best performance but no data persistence across node changes
3. **Capacity Planning**: Plan storage requests based on available local disk capacity on your VM SKU
4. **Workload Suitability**: Ideal for AI/ML training scratch space, caching layers, and temporary data processing

## Additional Resources

- [Azure Container Storage Documentation](https://learn.microsoft.com/en-us/azure/storage/container-storage/)
- [Install Azure Container Storage on AKS](https://learn.microsoft.com/en-us/azure/storage/container-storage/install-container-storage-aks)
- [Use Container Storage with Local Disk](https://learn.microsoft.com/en-us/azure/storage/container-storage/use-container-storage-with-local-disk)
- [NDv5 Series VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/ndv5-series)

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

