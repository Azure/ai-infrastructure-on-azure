# FIO Performance Testing on AKS

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Storage Types](#3-storage-types)
4. [Quick Start](#4-quick-start)
5. [Configuration Examples](#5-configuration-examples)
6. [Test Examples](#6-test-examples)

## 1. Overview

This Helm chart provides FIO (Flexible I/O Tester) for testing storage performance on Azure Kubernetes Service (AKS). It supports multiple storage types:

- **Azure Container Storage**: High-performance ephemeral disk storage
- **LocalPV**: Local persistent volumes on nodes
- **Existing PVC**: Use an existing PersistentVolumeClaim (for blobfuse, Lustre, or other shared storage)

FIO is useful for:

- Validating storage performance for AI/ML workloads
- Testing different I/O patterns (sequential, random, mixed)
- Benchmarking storage performance with various configurations
- Comparing performance across different storage types

## 2. Prerequisites

- AKS cluster
- kubectl access to the cluster
- Helm 3.x
- Depending on storage type:
  - **Azure Container Storage**: Cluster created with `--enable-azure-container-storage`
  - **LocalPV**: Nodes with local disk storage
  - **Existing PVC**: Pre-created PVC (e.g., blobfuse or Lustre storage)

## 3. Storage Types

### Azure Container Storage

Uses Azure Container Storage with ephemeral disk for high-performance local NVMe storage. Ideal for scratch space and temporary data.

**Configuration:**

```yaml
storage:
  type: "azure-container-storage"
  size: "100Gi"
  azureContainerStorage:
    storageClassName: "acstor-ephemeraldisk-nvme"
```

### LocalPV

Uses local persistent volumes on the node. Provides direct access to local disks for maximum performance.

**Configuration:**

```yaml
storage:
  type: "localpv"
  size: "100Gi"
  localpv:
    path: "/mnt/disks/ssd0"
    nodeAffinity:
      required:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                  - your-node-name
```

### Existing PVC (Blobfuse, Lustre, or Shared Storage)

Use an existing PVC for testing with pre-provisioned storage like blobfuse or Lustre. This is the recommended approach for testing blobfuse performance.

**Configuration:**

```yaml
storage:
  type: "existing-pvc"
  existingPvcName: "my-shared-pvc"
```

**Note**: For blobfuse testing, create a blobfuse PVC using the [blob-shared-storage Helm chart](../../../storage_references/aks/shared_storage/helm/blob-shared-storage) first, then reference it here.

## 4. Quick Start

### Default Test (Azure Container Storage)

```bash
helm install fio-test infrastructure_validations/aks/fio/helm/fio
```

### Test with Existing PVC (e.g., Blobfuse)

```bash
helm install fio-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=existing-pvc \
  --set storage.existingPvcName=my-blobfuse-pvc
```

### Monitor the Test

```bash
kubectl logs -f fio-test-fio
```

### Clean Up

```bash
helm uninstall fio-test
```

## 5. Configuration Examples

### Custom Random Write Test

```bash
helm install iops-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set fio.readWrite=randwrite \
  --set fio.blockSize=4k \
  --set fio.numJobs=4 \
  --set fio.runtime=300
```

### Sequential Write Test

```bash
helm install seq-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set fio.readWrite=write \
  --set fio.blockSize=4M \
  --set fio.size=5G \
  --set fio.timeBased=false \
  --set storage.size=10Gi
```

## 6. Test Examples

### Blobfuse Examples

To test blobfuse, first create a blobfuse PVC using the blob-shared-storage Helm chart, then use it with FIO.

#### Create Blobfuse Storage

See the [blob shared storage documentation](../../../storage_references/aks/shared_storage/README.md) for examples of creating blobfuse storage with different mount options.

#### Block Cache Sequential Write

Test large block sequential writes using blobfuse block cache. First create the storage, then run FIO:

```bash
# Create blobfuse PVC with block cache mount options
helm install blob-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set pvc.name="fio-blobfuse-pvc" \
  --set storage.size=10Gi \
  --set-json 'storage.mountOptions=["-o allow_other","--use-attr-cache=true","--cancel-list-on-mount-seconds=10","-o attr_timeout=120","-o entry_timeout=120","-o negative_timeout=120","--log-level=LOG_WARNING","--block-cache","--block-cache-block-size=32"]'

# Run FIO test against the blobfuse PVC
helm install fio-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=existing-pvc \
  --set storage.existingPvcName=fio-blobfuse-pvc \
  --set fio.testName=sequential-write-test \
  --set fio.blockSize=4M \
  --set fio.readWrite=write \
  --set fio.size=10G \
  --set fio.timeBased=false \
  --set fio.additionalOptions="--group_reporting"
```

#### File Cache Sequential Write

Test large block sequential writes using blobfuse file cache:

```bash
# Create blobfuse PVC with file cache mount options
helm install blob-storage storage_references/aks/shared_storage/helm/blob-shared-storage \
  --set pvc.name="fio-blobfuse-pvc" \
  --set storage.size=10Gi \
  --set-json 'storage.mountOptions=["-o allow_other","--use-attr-cache=true","--cancel-list-on-mount-seconds=10","-o attr_timeout=120","-o entry_timeout=120","-o negative_timeout=120","--log-level=LOG_WARNING","--file-cache-timeout=600","--tmp-path=/tmp/blobfuse","--lazy-write"]'

# Run FIO test against the blobfuse PVC
helm install fio-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=existing-pvc \
  --set storage.existingPvcName=fio-blobfuse-pvc \
  --set fio.testName=sequential-write-test \
  --set fio.blockSize=4M \
  --set fio.readWrite=write \
  --set fio.size=10G \
  --set fio.timeBased=false \
  --set fio.additionalOptions="--group_reporting"
```

### Azure Container Storage Examples

#### High IOPS Random Write Test

Test maximum IOPS with Azure Container Storage ephemeral disk.

```bash
helm install iops-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set storage.size=100Gi \
  --set fio.testName=high-iops-test \
  --set fio.blockSize=4k \
  --set fio.readWrite=randwrite \
  --set fio.numJobs=8 \
  --set fio.runtime=300 \
  --set resources.limits.cpu=8 \
  --set resources.limits.memory=16Gi
```

#### Large File Sequential Write

Test throughput with large sequential writes on ephemeral disk.

```bash
helm install throughput-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set storage.size=200Gi \
  --set fio.testName=throughput-test \
  --set fio.blockSize=1M \
  --set fio.readWrite=write \
  --set fio.size=50G \
  --set fio.timeBased=false \
  --set fio.numJobs=4
```

### Shared Storage (Lustre/Blobfuse) Examples

#### Test Existing Lustre PVC

Test performance against an existing Lustre filesystem.

```bash
helm install lustre-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=existing-pvc \
  --set storage.existingPvcName=my-lustre-pvc \
  --set fio.blockSize=1M \
  --set fio.readWrite=write \
  --set fio.size=10G \
  --set fio.numJobs=4
```

#### Test Existing Shared Blobfuse PVC

Test performance against a shared blobfuse PVC with ReadWriteMany access.

```bash
helm install shared-blob-test infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=existing-pvc \
  --set storage.existingPvcName=shared-blob-storage-pvc \
  --set fio.readWrite=randwrite \
  --set fio.blockSize=4k \
  --set fio.runtime=300
```

## Monitoring and Debugging

### View Test Logs

```bash
# Follow logs in real-time
kubectl logs -f fio-test-fio

# View completed test logs
kubectl logs fio-test-fio
```

### Check Pod Status

```bash
kubectl get pods
kubectl describe pod fio-test-fio
```

### Debug Mode

Set `sleepDuration` to keep the pod running after test completion for debugging:

```bash
helm install debug-test infrastructure_validations/aks/fio/helm/fio \
  --set sleepDuration=3600 \
  --set storage.type=azure-container-storage
```

Then exec into the pod:

```bash
kubectl exec -it fio-test-fio -- /bin/sh
```

## Performance Tips

### Blobfuse Optimization

- Use `--block-cache` for large sequential writes
- Use `--file-cache-timeout` for file-based caching
- Adjust timeout values based on workload patterns
- Use `Standard_LRS` for cost-effective testing
- Use `Premium_LRS` for production workloads

### Azure Container Storage

- Best for ephemeral data and scratch space
- Provides lowest latency on NDv5 series VMs
- Data is lost when pod is deleted
- No additional cost beyond the VM

### LocalPV

- Maximum performance for node-local data
- Requires node affinity configuration
- Not portable across nodes
- Good for node-specific caching

### Shared Storage (Lustre)

- Best for multi-node training with shared datasets
- Use existing PVC mode to test pre-provisioned storage
- Consider block size and job count for optimal throughput
