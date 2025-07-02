# NCCL Test Helm Chart

This Helm chart deploys an NCCL (NVIDIA Collective Communications Library) performance test job on Kubernetes using the MPI Operator.

## Prerequisites

- Kubernetes cluster with GPU nodes
- MPI Operator installed (kubeflow/mpi-operator)
- NVIDIA GPU Operator or equivalent GPU support
- InfiniBand/RDMA support (if testing high-speed interconnects)

## Installation

### Install the MPI Operator (if not already installed)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```

### Install the NCCL Test Chart

```bash
# Install with default values (2 nodes, 8 GPUs per node)
helm install nccl-test ./helm/nccl-test

# Install with custom number of nodes
helm install nccl-test ./helm/nccl-test --set replicaCount=4

# Install with custom configuration
helm install nccl-test ./helm/nccl-test \
  --set replicaCount=2 \
  --set slotsPerWorker=8 \
  --set ncclTest.testArgs="-b 16G -e 16G -f 2 -g 1 -c 0 -n 10"
```

## Configuration

The following table lists the configurable parameters and their default values:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of worker nodes | `2` |
| `slotsPerWorker` | Number of GPUs per worker node | `8` |
| `image.repository` | Container image repository | `ghcr.io/azure/ai-infrastructure-on-azure/nccl-test` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `ncclTest.testArgs` | Arguments for the NCCL test | `"-b 1K -e 16G -f 2 -g 1 -c 0"` |
| `ncclTest.env.NCCL_DEBUG` | NCCL debug level | `WARN` |
| `resources.worker.requests` | Resource requests for worker pods | See values.yaml |
| `resources.worker.limits` | Resource limits for worker pods | See values.yaml |

## NCCL Test Parameters

The `ncclTest.testArgs` parameter controls the test execution:

- `-b`: Starting data size (e.g., 1K, 1M, 1G)
- `-e`: Ending data size (e.g., 16G, 32G)
- `-f`: Factor for data size progression (e.g., 2 for doubling)
- `-g`: Number of GPUs per process (typically 1)
- `-c`: Enable data validation (0=disabled, 1=enabled)

## Monitoring

Check the job status:
```bash
kubectl get mpijob
kubectl describe mpijob nccl-tests
```

View logs:
```bash
# Launcher logs (contains test results)
kubectl logs -f job/nccl-tests-launcher

# Worker logs
kubectl logs -l training.kubeflow.org/job-name=nccl-tests,training.kubeflow.org/replica-type=worker
```

## Customizing NCCL Environment

You can customize NCCL behavior by modifying the environment variables in `values.yaml`:

```yaml
ncclTest:
  env:
    NCCL_DEBUG: "INFO"  # More verbose logging
    NCCL_MIN_NCHANNELS: "16"  # Reduce channels for smaller tests
    NCCL_SOCKET_IFNAME: "eth0"  # Network interface
```

## Troubleshooting

1. **Job stuck in pending**: Check if nodes have sufficient GPU resources
2. **Connection issues**: Verify network configuration and RDMA drivers
3. **Permission errors**: Ensure proper security contexts and capabilities

## Uninstallation

```bash
helm uninstall nccl-test
```

This will remove the NCCL test job and associated resources.
