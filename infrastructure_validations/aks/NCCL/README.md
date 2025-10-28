# NCCL Allreduce

## Table of Contents

1. [Overview](#1-overview)
2. [Launching the Helm Chart](#2-launching-the-helm-chart)
3. [Building the Container Image](#3-building-the-container-image)

## 1. Overview

NCCL Allreduce is a quick test for the IB network and this example has a container image and a helm chart to deploy.

## 2. Launching the Helm Chart

```bash
# Install with default values (2 nodes, 8 GPUs per node)
helm install nccl-test ./helm/nccl-test

# Install with custom number of nodes
helm install nccl-test ./helm/nccl-test --set nodes=4

# Install with custom configuration
helm install nccl-test ./helm/nccl-test \
  --set nodes=2 \
  --set gpusPerNode=8 \
  --set ncclTest.testArgs="-b 16G -e 16G -f 2 -g 1 -c 0 -N 10"

# Install with shared RDMA resources
helm install nccl-test ./helm/nccl-test \
  --set rdmaResource="rdma/shared_ib" \
  --set nodes=4
```

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodes` | Number of worker nodes | `2` |
| `gpusPerNode` | Number of GPUs per worker node | `8` |
| `gpuResource` | GPU resource name | `nvidia.com/gpu` |
| `rdmaResource` | RDMA resource name | `rdma/ib` |
| `image.repository` | Container image repository | `ghcr.io/azure/ai-infrastructure-on-azure/nccl-test` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `ncclTest.testArgs` | Arguments for NCCL test | `"-b 1K -e 16G -f 2 -g 1 -c 0"` |
| `ncclTest.env.*` | NCCL environment variables | See values.yaml |
| `affinity.required` | Required pod affinity topology keys | `[{topologyKey: agentpool}]` |
| `affinity.preferred` | Preferred pod affinity topology keys | `[]` |

#### NCCL Test Parameters

The `ncclTest.testArgs` parameter controls the test execution:

- `-b`: Starting data size (e.g., 1K, 1M, 1G, 16G)
- `-e`: Ending data size (e.g., 16G, 32G)
- `-f`: Factor for data size progression (e.g., 2 for doubling)
- `-g`: Number of GPUs per process (typically 1)
- `-c`: Enable data validation (0=disabled, 1=enabled)
- `-N`: Number of iterations per test

#### Pod Affinity Configuration

The `affinity` parameter controls where worker pods are scheduled to ensure optimal network topology:

- **`affinity.required`**: List of topology keys that **must** be satisfied (hard constraint). All worker pods will be co-located based on these topology keys. Default ensures all workers run in the same `agentpool`.
- **`affinity.preferred`**: List of topology keys that are **preferred** but not required (soft constraint). Each entry should include `topologyKey` and optionally `weight` (1-100, default 100).

**Examples:**

1. **Require same torset (InfiniBand domain)** - Use this when torset labels are present and you want guaranteed co-location within the same IB switching domain:

```bash
helm install nccl-test ./helm/nccl-test \
  --set nodes=16 \
  --set affinity.required[0].topologyKey=agentpool \
  --set affinity.required[1].topologyKey=ib/torset
```

2. **Prefer same torset (best effort)** - Use this when torset labels may not be present on all nodes:

```bash
helm install nccl-test ./helm/nccl-test \
  --set nodes=16 \
  --set affinity.preferred[0].topologyKey=ib/torset \
  --set affinity.preferred[0].weight=100
```

3. **Using a custom values file** for complex affinity rules:

```yaml
# custom-affinity.yaml
nodes: 16
affinity:
  required:
    - topologyKey: agentpool
  preferred:
    - topologyKey: ib/torset
      weight: 100
    - topologyKey: topology.kubernetes.io/zone
      weight: 50
```

Then install:
```bash
helm install nccl-test ./helm/nccl-test -f custom-affinity.yaml
```

**Note:** If torset labels (`ib/torset`) are not present on nodes, using them in `required` will prevent pods from scheduling. Use `preferred` instead for graceful degradation.


#### Using Custom Values Files

For complex configurations, create a custom values file:

```yaml
# custom-values.yaml
nodes: 4
gpusPerNode: 8
rdmaResource: "rdma/shared_ib"

ncclTest:
  testArgs: "-b 16G -e 16G -f 2 -g 1 -c 0 -N 10"
  env:
    NCCL_DEBUG: "INFO"
    NCCL_COLLNET_ENABLE: "0"  # Disable SHARP
```

Then install with:
```bash
helm install nccl-test ./helm/nccl-test -f custom-values.yaml
```

### Monitoring the Test

Check job status:
```bash
kubectl get mpijob
kubectl describe mpijob nccl-test
```

View test results:
```bash
# Check launcher logs for results
kubectl logs job/nccl-test-launcher

# Check worker logs
kubectl logs -l task=nccl-test
```

### Cleanup

```bash
helm uninstall nccl-test
```

## 3. Building the Container Image

The container image is automatically built and published to GitHub Container Registry via GitHub Actions whenever changes are made to the Dockerfile or workflow.

Published image: `ghcr.io/azure/ai-infrastructure-on-azure/nccl-test:latest`

### Manual Build (Optional)

The instructions below show how to build and push to an Azure Container Registry, `$ACR_NAME`:

```bash
cd docker/
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/nccl-test:dev .
docker push $ACR_NAME.azurecr.io/nccl-test:dev
```

Set the `image` values to use a custom image with the Helm chart:

```bash
helm install nccl-test ./helm/nccl-test \
  --set image.repository=$ACR_NAME.azurecr.io/nccl-test \
  --set image.tag=dev \
  --set image.pullPolicy=Never
```
