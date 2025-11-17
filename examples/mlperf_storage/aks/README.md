# MLPerf Storage Checkpoint Benchmark – AKS

Run the **checkpoint** MLPerf Storage benchmark on Azure Kubernetes Service (AKS) with the Kubeflow MPI Operator. Training/data generation are removed; only checkpoint write and read I/O is measured.

## Prerequisites

- AKS cluster with appropriate node pools
- `kubectl` configured to access your cluster
- Storage solution deployed (e.g. Azure Managed Lustre)
- Storage CSI driver installed and configured
- MPI Operator installed

## Quick Start

### Helm (Recommended)

```bash
# Install with custom values
helm install mlperf-storage-checkpoint examples/mlperf_storage/aks/helm/mlperf-storage-checkpoint \
  --set mpi.workers=4 \
  --set mpi.slotsPerWorker=8 \
  --set benchmark.numCheckpointsWrite=10 \
  --set benchmark.numCheckpointsRead=0 \
  --set benchmark.model=llama3-70b \
  --set storage.pvcName=shared-amlfs-storage

# Monitor MPIJob
kubectl get mpijobs
kubectl logs -f -l role=launcher
```

## Deployment Steps (Checkpoint Mode)

### Using Helm Chart

#### 1. Prepare Storage

Create a PVC for your storage backend. See [Storage Options](../../../storage_references/aks/shared_storage/README.md).

#### 2. Install the Chart

```bash
# Basic installation
helm install mlperf-storage-checkpoint examples/mlperf_storage/aks/helm/mlperf-storage-checkpoint \
  --set storage.pvcName=shared-amlfs-storage

# With customization of the benchmark
helm install mlperf-storage-checkpoint examples/mlperf_storage/aks/helm/mlperf-storage-checkpoint \
  --set mpi.workers=16 \
  --set mpi.slotsPerWorker=8 \
  --set benchmark.numCheckpointsWrite=40 \
  --set benchmark.numCheckpointsRead=0
```

#### 3. Monitor the Job

```bash
# Check MPIJob status
kubectl get mpijobs

# View launcher logs
kubectl logs -f -l role=launcher

# View worker logs
kubectl logs -l role=worker
```

#### 4. Retrieve Results

```bash
LAUNCHER_POD=$(kubectl get pods -l role=launcher -o jsonpath='{.items[0].metadata.name}')
kubectl cp ${LAUNCHER_POD}:/mnt/storage/results ./results
```

## Configuration Options

### Using Helm

The Helm chart provides extensive configuration options.

Common configurations:

```bash
# Increasing number of nodes
helm install mlperf-storage-checkpoint examples/mlperf_storage/aks/helm/mlperf-storage-checkpoint \
  --set mpi.workers=8

# Larger write workload
helm install mlperf-storage-checkpoint examples/mlperf_storage/aks/helm/mlperf-storage-checkpoint \
  --set mpi.workers=8 \
  --set mpi.slotsPerWorker=8 \
  --set benchmark.numCheckpointsWrite=20 \
  --set benchmark.clientHostMemoryGiB=64

# Node targeting
helm install mlperf-storage-checkpoint examples/mlperf_storage/aks/helm/mlperf-storage-checkpoint \
  --set nodeSelector.agentpool=compute
```

### Process / Slots / CPU

Total processes = `mpi.workers * mpi.slotsPerWorker`. Worker CPU requests/limits derive automatically from `slotsPerWorker`.

### Scaling Workers

Adjust the number of worker replicas in `job.yaml`:

```yaml
spec:
  mpiReplicaSpecs:
    Worker:
      replicas: 8 # Change this value
```

### Resource Allocation

Modify resource requests/limits through Helm values (`launcher.resources`, `worker.resources`) while CPUs map to `slotsPerWorker`.

### Node Affinity

Target specific node pools by uncommenting and configuring the affinity section in `job.yaml`:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: agentpool
              operator: In
              values:
                - compute # Your node pool name
```

## MPIJob Architecture (Checkpoint Mode)

The deployment consists of:

- **Launcher Pod (1)** builds host list, performs SSH readiness loop (300s timeout) then runs `mlpstorage checkpointing run` with explicit flags.
- **Worker Pods (N)** expose SSH (sshd) for MPI; slots map to CPU.
- **Shared Storage** provides checkpoint folder and results.
- **No ConfigMap** usage; all settings are values → CLI flags.

MPI Operator automatically:

- Generates hostfile with worker endpoints
- Injects SSH keys
- Manages lifecycle & status CR

## Cleanup

```bash
helm uninstall mlperf-storage-checkpoint
```
