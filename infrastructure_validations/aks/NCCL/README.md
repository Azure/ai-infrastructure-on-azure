# NCCL Allreduce

NCCL Allreduce is a quick test for the IB network and this example has a container image and a helm chart to deploy.

## Launching the Helm Chart

```bash
# Install with default values (2 nodes, 8 GPUs per node)
helm install nccl-test ./helm/nccl-test

# Install with custom number of nodes
helm install nccl-test ./helm/nccl-test --set nodes=4

# Install with custom configuration
helm install nccl-test ./helm/nccl-test \
  --set nodes=2 \
  --set gpusPerNode=8 \
  --set ncclTest.testArgs="-b 16G -e 16G -f 2 -g 1 -c 0 -n 10"

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

#### NCCL Test Parameters

The `ncclTest.testArgs` parameter controls the test execution:

- `-b`: Starting data size (e.g., 1K, 1M, 1G, 16G)
- `-e`: Ending data size (e.g., 16G, 32G)
- `-f`: Factor for data size progression (e.g., 2 for doubling)
- `-g`: Number of GPUs per process (typically 1)
- `-c`: Enable data validation (0=disabled, 1=enabled)
- `-N`: Number of iterations per test


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
kubectl describe mpijob <release-name>
```

View test results:
```bash
# Check launcher logs for results
kubectl logs job/<release-name>-launcher

# Check worker logs
kubectl logs -l task=nccl-test
```

### Cleanup

```bash
helm uninstall nccl-test
```

## Building the Container Image

The container image is automatically built and published to GitHub Container Registry via GitHub Actions whenever changes are made to the Dockerfile or workflow.

Published image: `ghcr.io/azure/ai-infrastructure-on-azure/nccl-test:latest`

### Manual Build (Optional)

The instructions below show how to build and push to an Azure Container Registry, `$ACR_NAME`:

```bash
cd docker/
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/nccl-test:v1.0 .
```

Set the `image` values to use a custom image with the Helm chart:

```bash
helm install nccl-test ./helm/nccl-test \
  --set image.repository=$ACR_NAME.azurecr.io/nccl-test \
  --set image.tag=v1.0 \
  --set image.pullPolicy=Never
```
