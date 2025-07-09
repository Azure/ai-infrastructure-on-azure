# Azure Node Health Check (AZNHC)

Azure Node Health Check is a comprehensive validation tool for GPU clusters that tests hardware components, GPUs, and InfiniBand connectivity on each node.

## Launching the Helm Chart

```bash
# Install with default values (2 nodes)
helm install aznhc-test ./helm/aznhc

# Install with custom number of nodes
helm install aznhc-test ./helm/aznhc --set nodes=4
```

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodes` | Number of nodes to test | `2` |
| `gpuResource` | GPU resource name | `nvidia.com/gpu` |
| `rdmaResource` | RDMA resource name | `rdma/ib` |
| `image.repository` | Container image repository | `ghcr.io/azure/ai-infrastructure-on-azure/aznhc` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `nhcConfig` | Node Health Check configuration | See values.yaml |

#### Node Health Check Configuration

The `nhcConfig` parameter contains the complete test configuration that gets written to the container. You can customize which tests to run by modifying this configuration in your values file.

The default configuration includes:
- **Hardware checks**: CPU, memory, swap, InfiniBand ports, Ethernet interfaces
- **GPU checks**: GPU count, health monitoring, bandwidth, ECC errors, clock throttling, NCCL tests
- **InfiniBand checks**: Bandwidth with GPU Direct RDMA, link flapping detection

#### Automatic Node Distribution

Test pods are automatically distributed across different nodes because each pod requests the full GPU and RDMA resources available on a node (8 GPUs + 8 RDMA ports). This ensures that each node runs its own health check independently.

#### Using Custom Values Files

For complex configurations, create a custom values file:

```yaml
# custom-values.yaml
nodes: 4

nhcConfig: |
  # Custom NHC configuration
  * || check_gpu_count 8
  * || check_nvsmi_healthmon
  * || check_gpu_bw 50 300
  * || check_ib_bw_gdr 350
```

Then install with:
```bash
helm install aznhc-test ./helm/aznhc -f custom-values.yaml
```

### Monitoring the Health Checks

Check job status:
```bash
kubectl get job
kubectl describe job aznhc-test
```

View all health check results:
```bash
kubectl logs -l task=aznhc-test
```

**Check for failures across all nodes:**
```bash
kubectl logs -l task=aznhc-test | grep -i fail
```

Monitor job completion:
```bash
kubectl wait --for=condition=complete --timeout=600s job/aznhc-test
```

### Understanding Results

- **Successful completion**: All tests passed on all nodes
- **Failed pods**: Individual nodes that failed health checks
- **Partial completion**: Some nodes passed, others failed

Each node runs independently, so you can identify which specific nodes have issues.

### Cleanup

```bash
helm uninstall aznhc-test
```

## Building the Container Image

The container image is automatically built and published to GitHub Container Registry via GitHub Actions whenever changes are made to the Dockerfile or workflow.

Published image: `ghcr.io/azure/ai-infrastructure-on-azure/aznhc:latest`

### Manual Build (Optional)

The instructions below show how to build and push to an Azure Container Registry, `$ACR_NAME`:

```bash
cd docker/
az acr login -n $ACR_NAME
docker build -t $ACR_NAME.azurecr.io/aznhc-test:dev .
docker push $ACR_NAME.azurecr.io/aznhc-test:dev
```

Set the `image` values to use a custom image with the Helm chart:

```bash
helm install aznhc-test ./helm/aznhc-test \
  --set image.repository=$ACR_NAME.azurecr.io/aznhc-test \
  --set image.tag=dev \
  --set image.pullPolicy=Never
```
