# MLPerf Storage Benchmarks on AKS

This directory provides Helm charts to run MLPerf Storage workloads on Azure Kubernetes Service (AKS) using the Kubeflow MPI Operator. Benchmarks are decomposed into focused charts so you can size storage independently for checkpointing, training emulation, dataset generation, and dataset sizing.

## Available Helm Charts

| Chart | Path | Purpose |
|-------|------|---------|
| Checkpointing | `helm/mlperf-checkpointing` | Write & read model checkpoints (I/O focus) |
| Training Run | `helm/mlperf-training-run` | Emulate training I/O (requires data generation) |
| Training Dataset Generation | `helm/mlperf-training-dataset-generation` | Parallel generation of synthetic training dataset |
| Training Dataset Size | `helm/mlperf-training-dataset-size` | Calculate recommended dataset size for a target host and GPU configuration |

Each chart is independent; it is possible to install any subset depending on workflow stage.

## Prerequisites

- AKS cluster with GPU or high‑memory node pools sized for your test
- `kubectl` configured for the target cluster
- Shared storage (e.g. Azure Managed Lustre, Azure NetApp Files, Azure Blob Storage) provisioned & mounted via PVC
- Storage CSI driver installed (e.g. Azure Lustre CSI or Azure Blob CSI)
- Kubeflow MPI Operator deployed 

## Storage Setup

Create or reuse a PersistentVolumeClaim pointing at your shared filesystem. See [Shared Storage References](../../../storage_references/aks/shared_storage/README.md).

## Quick Start Examples

### 1. Checkpointing
```bash
helm install ckpt examples/mlperf_storage/aks/helm/mlperf-checkpointing \
  --set storage.pvcName=shared-amlfs-storage \
  --set mpi.workers=8 --set mpi.slotsPerWorker=8 \
  --set benchmark.model=llama3-70b \
  --set benchmark.numCheckpointsWrite=20 --set benchmark.numCheckpointsRead=5
```
Monitor:
```bash
kubectl get mpijob ckpt -o wide
kubectl logs -f -l app.kubernetes.io/instance=ckpt,role=launcher
```
Retrieve results:
```bash
LAUNCHER=$(kubectl get pods -l app.kubernetes.io/instance=ckpt,role=launcher -o jsonpath='{.items[0].metadata.name}')
kubectl cp ${LAUNCHER}:/mnt/storage/results ./results
```

### 2. Dataset Size Calculator
```bash
helm install datasize examples/mlperf_storage/aks/helm/mlperf-training-dataset-size \
  --set storage.pvcName=shared-amlfs-storage \
  --set benchmark.model=unet3d \
  --set benchmark.clientHostMemoryGiB=128 \
  --set benchmark.maxAccelerators=32 \
  --set benchmark.numClientHosts=4 \
  --set benchmark.acceleratorType=h100
```
### 3. Dataset Generation
```bash
helm install datagen examples/mlperf_storage/aks/helm/mlperf-training-dataset-generation \
  --set storage.pvcName=shared-amlfs-storage \
  --set mpi.workers=8 --set mpi.slotsPerWorker=8 \
  --set benchmark.model=unet3d --set benchmark.numFilesTrain=56000
```
### 4. Training I/O Emulation
```bash
helm install train-io examples/mlperf_storage/aks/helm/mlperf-training-run \
  --set storage.pvcName=shared-amlfs-storage \
  --set mpi.workers=4 --set mpi.slotsPerWorker=8 \
  --set benchmark.model=unet3d --set benchmark.numFilesTrain=400
```

## Common Configuration Keys

| Key | Charts | Description |
|-----|--------|-------------|
| `mpi.workers` | checkpointing, training-run, datagen | Number of worker pods (also equals client host count for training-run) |
| `mpi.slotsPerWorker` | checkpointing, training-run, datagen | CPU slots per worker, also drives total MPI processes |
| `benchmark.model` | all | Model name for sizing/emulation (e.g. `llama3-70b`, `unet3d`) |
| `benchmark.numFilesTrain` | training-run, datagen | Number of synthetic training files / dataset size parameter |
| `benchmark.numCheckpointsWrite` / `benchmark.numCheckpointsRead` | checkpointing | Number of checkpoints to write / read |
| `benchmark.clientHostMemoryGiB` | checkpointing, training-run, datasize | Memory per host in GiB |
| `storage.pvcName` | all | Existing PVC name providing shared storage |
| `storage.mountPath` | all | Path inside containers where storage is mounted |
| `benchmark.debug` / `benchmark.verbose` | all | Extra logging flags appended to command when true |

## Derived Values

- Total MPI processes = `mpi.workers * mpi.slotsPerWorker`
- Training-run accelerators (emulated) = same as total MPI processes
- Client hosts for training-run = `mpi.workers`

## Host Readiness Behavior

Launcher performs an SSH readiness loop (up to 300s). All workers must accept ssh before workload starts.

## Adjusting Resources

Use:
```bash
--set launcher.resources.requests.memory=64Gi \
--set worker.resources.requests.memory=256Gi
```
CPU for workers is auto‑derived from `mpi.slotsPerWorker` in the templates.

## Enabling Debug or Verbose Output

Add `--set benchmark.debug=true` and/or `--set benchmark.verbose=true` to the `helm install` or `helm upgrade` command; corresponding CLI flags are inserted automatically.

## Upgrades
```bash
helm upgrade ckpt examples/mlperf_storage/aks/helm/mlperf-checkpointing \
  --set mpi.workers=16 --set benchmark.numCheckpointsWrite=40
```

## Cleanup
```bash
helm uninstall ckpt
helm uninstall train-io
helm uninstall datagen
helm uninstall datasize
```
