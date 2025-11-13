# Kueue Workload Management

This Helm chart provides a simple example for setting up [Kueue](https://kueue.sigs.k8s.io/) workload management with a GPU node pool queue configuration.

## Overview

Kueue is a Kubernetes-native job queueing system that manages quota and admission control for batch workloads. This example creates a basic GPU queue that:

- Targets nodes with the label `agentpool: gpu`
- Manages GPU resources (`nvidia.com/gpu`), RDMA/InfiniBand (`rdma/ib`), CPU, and memory
- Calculates total cluster quota as: `node count × per-node resources`

This is a **simple, single-queue example** designed to get you started quickly. For production deployments with multiple teams, resource classes, or complex quota hierarchies, refer to the [Kueue documentation](https://kueue.sigs.k8s.io/).

## Prerequisites

- Kubernetes cluster with Kueue installed
  - Install using: `./infrastructure_references/aks/scripts/deploy-aks.sh install-kueue`
  - Or follow [Kueue installation guide](https://kueue.sigs.k8s.io/docs/installation/)

## Installation

### Quick Start

```bash
helm install gpu-queue ./scheduling/aks/kueue/helm
```

### Custom Installation

```bash
# For 2 NDv5 nodes with 8 H100 GPUs each:
helm install gpu-queue ./scheduling/aks/kueue/helm \
  --set nodes.count=2 \
  --set "nodes.perNodeResources.nvidia\.com/gpu=8" \
  --set "nodes.perNodeResources.rdma/ib=8" \
  --set "nodes.perNodeResources.cpu=90" \
  --set "nodes.perNodeResources.memory=1800Gi"
```

## Configuration

Edit `helm/values.yaml` to match your cluster:

```yaml
# Node configuration
nodes:
  count: 2 # Number of GPU nodes
  perNodeResources:
    nvidia.com/gpu: "8" # GPUs per node
    rdma/ib: "8" # RDMA devices per node
    cpu: "90" # CPU cores per node
    memory: "1800Gi" # Memory per node

# Cluster Queue name
clusterQueue:
  name: "gpu-cluster-queue"

# Local Queue configuration
localQueue:
  name: "gpu-local-queue"
  namespace: "default"
```

**Example**: With 2 nodes × 8 GPUs per node = 16 total GPUs quota

## Using Kueue with Repository Examples

All Helm charts in this repository support optional Kueue integration. To enable Kueue for any workload, simply add the `kueue.queueName` parameter during Helm installation.

**Example with NCCL tests:**

```bash
helm install nccl-test ./infrastructure_validations/aks/NCCL/helm/nccl-test \
  --set kueue.queueName=gpu-local-queue
```

This works for all infrastructure validations (NCCL, NHC, FIO) and training examples (llm-foundry, megatron-lm).

## How It Works

When you add the `kueue.queueName` parameter, the Helm chart automatically adds the Kueue queue label to the workload:

```yaml
metadata:
  labels:
    kueue.x-k8s.io/queue-name: gpu-local-queue
```

This label tells Kueue to manage the workload's admission. Kueue will:

1. **Queue the workload** until resources are available
2. **Check quota** against the ClusterQueue limits
3. **Admit the workload** when resources can be allocated
4. **Monitor execution** and release resources when complete

Without the `kueue.queueName` parameter, workloads run directly without Kueue management (default Kubernetes behavior).

## Resources Created

This chart creates three Kueue resources:

### 1. ResourceFlavor

Defines the type of resources available (GPU nodes with `agentpool: gpu` label).

### 2. ClusterQueue

Manages cluster-wide resource quotas for GPU, RDMA, CPU, and memory.

### 3. LocalQueue

Provides a namespace-scoped queue that maps to the ClusterQueue.

## Monitoring Queue Status

Check queue status:

```bash
kubectl get clusterqueues
kubectl get localqueues
kubectl get workloads
```

View detailed queue information:

```bash
kubectl describe clusterqueue gpu-cluster-queue
kubectl describe localqueue gpu-local-queue
```

## Uninstallation

```bash
helm uninstall gpu-queue
```

## Learn More

- [Kueue Documentation](https://kueue.sigs.k8s.io/)
- [Kueue Concepts](https://kueue.sigs.k8s.io/docs/concepts/)
- [Advanced Queue Configuration](https://kueue.sigs.k8s.io/docs/tasks/)
- [Main AKS Infrastructure Guide](../../infrastructure_references/aks/README.md)
