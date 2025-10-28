# FIO Testing with Blobfuse on AKS

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Test Examples](#test-examples)

## Overview

## Overview

This directory contains tools and examples for testing Azure Blob Storage performance using FIO (Flexible I/O Tester) with blobfuse mounts on Azure Kubernetes Service (AKS).

FIO is a versatile tool for testing I/O performance. This setup allows you to test different I/O patterns against Azure Blob Storage mounted via blobfuse, which is useful for:

- Validating storage performance for AI/ML workloads
- Testing different I/O patterns (sequential, random, mixed)
- Benchmarking blob storage performance with various configurations
- Validating blobfuse mount options and caching settings

## Prerequisites

- AKS cluster with blob CSI driver enabled
- Azure Storage Account with blob container
- kubectl access to the cluster

## Quick Start

1. **Deploy the Helm chart (runs default random write test):**
   ```bash
   helm install fio-test ./helm/fio
   ```

2. **Monitor the test:**
   ```bash
   kubectl logs -f fio-test-pod
   ```

3. **Clean up:**
   ```bash
   helm uninstall fio-test
   ```

## Configuration

The Helm chart creates:
- A StorageClass for blob storage with optimized mount options
- A PersistentVolumeClaim for the test volume
- A Pod running FIO tests against the mounted blob storage

### Default Mount Options

The default blobfuse mount options are optimized for performance:
- `allow_other`: Allow other users to access the mount
- `use-attr-cache=true`: Enable attribute caching
- `cancel-list-on-mount-seconds=10`: Cancel long-running lists on mount
- `attr_timeout=120`: Cache attributes for 2 minutes
- `entry_timeout=120`: Cache directory entries for 2 minutes
- `negative_timeout=120`: Cache negative lookups for 2 minutes
- `log-level=LOG_WARNING`: Reduce log verbosity

### Customization

You can customize the test by modifying the values in the Helm chart:
- Storage class parameters (SKU, mount options)
- FIO test parameters (block size, I/O pattern, duration)
- Container resources and limits

## Test Examples

The `examples/` directory contains pre-configured FIO test scenarios:

1. **Block Cache Sequential Write Test** (`block-cache-sequential-write.yaml`): Large block sequential writes using blobfuse block cache
2. **File Cache Sequential Write Test** (`file-cache-sequential-write.yaml`): Large block sequential writes using blobfuse file cache

### Running Examples

The `examples/` directory contains pre-configured test scenarios. To run a specific example:

**Option 1: Run with default values (random write test)**
```bash
helm install fio-test ./helm/fio
```

**Option 2: Use a specific example configuration**
```bash
# Run the block cache sequential write test (4M block writes with block caching)
helm install block-cache-test ./helm/fio -f helm/fio/examples/block-cache-sequential-write.yaml

# Run the file cache sequential write test (4M block writes with file caching)
helm install file-cache-test ./helm/fio -f helm/fio/examples/file-cache-sequential-write.yaml
```

**Option 3: Override specific values for custom tests**
```bash
# Run a custom sequential write test
helm install custom-test ./helm/fio \
  --set fio.readWrite=write \
  --set fio.blockSize=4M \
  --set fio.size=5G \
  --set fio.timeBased=false \
  --set storage.size=10Gi

# Run a custom random test with higher IOPS
helm install iops-test ./helm/fio \
  --set fio.readWrite=randwrite \
  --set fio.blockSize=4k \
  --set fio.numJobs=4 \
  --set fio.runtime=300
```

### Monitoring the Test

After deploying, monitor the test progress:

```bash
# Watch the pod status
kubectl get pods -w

# Follow the test logs in real-time (replace 'fio-test' with your release name)
kubectl logs -f fio-test-pod

# Get detailed pod information if there are issues
kubectl describe pod fio-test-pod
```

### Cleaning Up

Remove the test resources when done:

```bash
helm uninstall fio-test
# This will remove the pod, PVC, and storage class
```
