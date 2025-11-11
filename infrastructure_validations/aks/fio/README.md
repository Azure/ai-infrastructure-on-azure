# FIO Performance Testing on AKS

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Storage Types](#3-storage-types)
4. [Quick Start](#4-quick-start)
5. [Configuration Examples](#5-configuration-examples)
6. [Test Examples](#6-test-examples)

## 1. Overview

This Helm chart provides FIO (Flexible I/O Tester) for testing storage
performance on Azure Kubernetes Service (AKS). It supports multiple storage
types:

- **Azure Container Storage**: High-performance ephemeral disk storage
- **Existing PVC**: Use an existing PersistentVolumeClaim (for blobfuse, Lustre,
  or other shared storage)

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
  - **Azure Container Storage**: Cluster created with
    `--enable-azure-container-storage`
  - **Existing PVC**: Pre-created PVC (e.g., blobfuse or Lustre storage)

## 3. Storage Types

### Azure Container Storage

Uses Azure Container Storage v2.x with ephemeral disk for high-performance local
NVMe storage. Ideal for scratch space and temporary data.

**Configuration:**

```yaml
storage:
  type: "azure-container-storage"
  size: "100Gi"
```

**Note**:

- The Helm chart automatically creates the required StorageClass for Azure
  Container Storage v2.x
- Uses Kubernetes ephemeral volumes - the PVC is automatically created when the
  pod starts and deleted when the pod is deleted
- Deployed as a Kubernetes Job with TTL - the Job, Pod, and PVC are
  automatically deleted 1 hour after completion
- Retrieve logs within 1 hour of completion, or adjust
  `job.ttlSecondsAfterFinished` for longer retention

### Existing PVC (Blobfuse, Lustre, or Shared Storage)

Use an existing PVC for testing with pre-provisioned storage like blobfuse or
Lustre. This is the recommended approach for testing blobfuse performance.

**Configuration:**

```yaml
storage:
  type: "existing-pvc"
  existingPvcName: "my-shared-pvc"
```

**Note**: For blobfuse testing, create a blobfuse PVC using the
[blob-shared-storage Helm chart](../../../storage_references/aks/shared_storage/helm/blob-shared-storage)
first, then reference it here.

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
# Get job status
kubectl get jobs

# Get pod from job
kubectl get pods -l job-name=fio-test

# Follow logs in real-time
kubectl logs -f job/fio-test
```

### Clean Up

```bash
helm uninstall fio-test
```

**Note**: The Job, Pod, and PVC are automatically deleted 1 hour after the job
completes. You can manually clean up earlier with `helm uninstall`, or adjust
the TTL with `--set job.ttlSecondsAfterFinished=<seconds>`.

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

To test blobfuse, first create a blobfuse PVC using the blob-shared-storage Helm
chart, then use it with FIO.

#### Create Blobfuse Storage

See the
[blob shared storage documentation](../../../storage_references/aks/shared_storage/README.md)
for examples of creating blobfuse storage with different mount options.

#### Block Cache Sequential Write

Test large block sequential writes using blobfuse block cache. First create the
storage, then run FIO:

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

#### ND H100 v5 Maximum Performance Tests

Optimized configurations for ND96isr_H100_v5 (96 vCPUs, 1.9 TiB RAM, 24 TiB
local NVMe).

**Maximum Random Write IOPS:**

```bash
helm install iops-test-w infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set storage.size=24Ti \
  --set fio.testName=randwrite-iops \
  --set fio.blockSize=4k \
  --set fio.size=10G \
  --set fio.readWrite=randwrite \
  --set fio.numJobs=4 \
  --set fio.ioDepth=128 \
  --set fio.runtime=300 \
  --set resources.limits.cpu=90 \
  --set resources.limits.memory=1636Gi
```

**Maximum Random Read IOPS:**

```bash
helm install iops-test-r infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set storage.size=24Ti \
  --set fio.testName=randread-iops \
  --set fio.blockSize=4k \
  --set fio.size=10G \
  --set fio.readWrite=randread \
  --set fio.numJobs=4 \
  --set fio.ioDepth=128 \
  --set fio.runtime=300 \
  --set resources.limits.cpu=90 \
  --set resources.limits.memory=1636Gi
```

**Maximum Sequential Read Bandwidth:**

```bash
helm install bw-test-r infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set storage.size=24Ti \
  --set fio.testName=seq-read-bandwidth \
  --set fio.blockSize=1M \
  --set fio.size=20G \
  --set fio.readWrite=read \
  --set fio.numJobs=1 \
  --set fio.ioDepth=64 \
  --set fio.runtime=300 \
  --set resources.limits.cpu=90 \
  --set resources.limits.memory=1636Gi
```

**Maximum Sequential Write Bandwidth:**

```bash
helm install bw-test-w infrastructure_validations/aks/fio/helm/fio \
  --set storage.type=azure-container-storage \
  --set storage.size=24Ti \
  --set fio.testName=seq-write-bandwidth \
  --set fio.blockSize=1M \
  --set fio.size=20G \
  --set fio.readWrite=write \
  --set fio.numJobs=1 \
  --set fio.ioDepth=64 \
  --set fio.runtime=300 \
  --set resources.limits.cpu=90 \
  --set resources.limits.memory=1636Gi
```

**Notes:**

- These tests use the full 24 TiB local NVMe capacity available on ND H100 v5
- CPU limit set to 90 cores (leaving 6 for system overhead)
- Memory limit set to 1636 GiB (leaving ~280 GiB for system)
- `ioDepth=128` for IOPS tests maximizes queue depth for 4k random I/O
- `ioDepth=64` for bandwidth tests optimizes large block sequential I/O
- All tests run for 5 minutes (`runtime=300`) to ensure stable results

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
kubectl logs -f job/fio-test

# View completed test logs
kubectl logs job/fio-test

# Get logs from specific pod
kubectl logs fio-test-<pod-hash>
```

### Check Job Status

```bash
# View jobs
kubectl get jobs

# View pods created by job
kubectl get pods -l job-name=fio-test

# Describe job for details
kubectl describe job fio-test
```

### Debug Mode

Set `sleepDuration` and `job.ttlSecondsAfterFinished` to keep the pod running
after test completion for debugging:

```bash
helm install debug-test infrastructure_validations/aks/fio/helm/fio \
  --set sleepDuration=3600 \
  --set job.ttlSecondsAfterFinished=7200 \
  --set storage.type=azure-container-storage
```

Then exec into the pod:

```bash
# Find the pod name
kubectl get pods -l job-name=debug-test

# Exec into the pod
kubectl exec -it debug-test-<pod-hash> -- /bin/sh
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
- Provides lowest latency with local NVMe storage
- Job, Pod, and PVC automatically deleted 1 hour after completion (using
  Kubernetes Job with TTL)
- No additional cost beyond the VM
- Automatically configured by the Helm chart (no manual StorageClass needed)
- Retrieve logs within the TTL window (default 1 hour), or adjust with
  `--set job.ttlSecondsAfterFinished=<seconds>`

### Shared Storage (Lustre)

- Best for multi-node training with shared datasets
- Use existing PVC mode to test pre-provisioned storage
- Consider block size and job count for optimal throughput
