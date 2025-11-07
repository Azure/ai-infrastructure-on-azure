# Torset Labeler Helm Chart

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [What This Chart Does](#3-what-this-chart-does)
4. [Installation](#4-installation)
5. [Configuration](#5-configuration)
6. [How It Works](#6-how-it-works)
7. [Checking Results](#7-checking-results)
8. [Troubleshooting](#8-troubleshooting)
9. [Cleanup](#9-cleanup)
10. [Re-running Discovery](#10-re-running-discovery)
11. [Integration with Workloads](#11-integration-with-workloads)

## 1. Overview

This Helm chart labels AKS nodes with torset information based on their HCA (Host Channel Adapter) GUIDs collected by the `node-labeler` chart.

## 2. Prerequisites

1. The `node-labeler` chart must be installed and running first to collect HCA GUID annotations
2. Nodes must have the `ib/hca-guids` annotation populated
3. At least one GPU node with InfiniBand hardware and SHARP support
4. The target nodepool must have InfiniBand connectivity

## 3. What This Chart Does

This chart runs a Kubernetes Job that:

1. **Fetches HCA GUIDs**: Queries all nodes matching the nodepool selector for their `ib/hca-guids` annotations
2. **Discovers Torsets**: Uses SHARP topology discovery to identify which nodes belong to the same torset (InfiniBand switching domain)
3. **Labels Nodes**: Applies `ib/torset=torset-XX` labels to each node based on the discovered topology

## 4. Installation

### Basic Installation

```bash
helm install torset-labeler utilities/aks/torset_labeler/helm -n kube-system
```

### Custom Nodepool Selector

To target a specific nodepool:

```bash
helm install torset-labeler utilities/aks/torset_labeler/helm -n kube-system \
  --set nodepool.selector="agentpool=mygpupool"
```

## 5. Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodepool.selector` | Label selector for nodes to process | `agentpool=gpu` |
| `image.repository` | Container image with SHARP tools | `mcr.microsoft.com/aznhc/aznhc-nv` |
| `image.tag` | Image tag | `1.2.0` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `kubectl.repository` | kubectl image | `mcr.microsoft.com/oss/kubernetes/kubectl` |
| `kubectl.tag` | kubectl version | `v1.26.3` |

## Example: values.yaml

```yaml
nodepool:
  selector: "agentpool=gpu"

image:
  repository: mcr.microsoft.com/aznhc/aznhc-nv
  tag: "1.2.0"
  pullPolicy: IfNotPresent
```

## 6. How It Works

### Architecture

The Job runs four init containers and one main container in sequence:

1. **cleanup-old-labels** (init): Removes all existing `ib/torset` labels from nodes matching the selector to ensure a clean state
2. **fetch-guids** (init): Queries Kubernetes API for all nodes with `ib/hca-guids` annotations
3. **torset-discovery** (init): Runs on a GPU node with IB hardware, uses SHARP to generate topology and identify torsets
4. **apply-labels** (main): Applies the discovered torset labels to each node

### Torset Discovery Algorithm

The Python script (`torset_tool.py`) implements the following logic:

1. Parse HCA GUIDs from node annotations (comma-separated list)
2. Write all GUIDs to a file
3. Run `sharp_cmd topology` to generate InfiniBand topology
4. Parse topology output to identify leaf switches
5. Group nodes connected to the same leaf switch into torsets
6. Generate torset labels (e.g., `torset-00`, `torset-01`, etc.)

### Output

After successful completion, each node will have a label like:

```
ib/torset=torset-00
```

Nodes in the same torset share the same InfiniBand switching domain and have optimal network connectivity for collective operations.

## 7. Checking Results

View torset labels on all nodes:

```bash
kubectl get nodes -L ib/torset
```

View detailed torset assignments:

```bash
kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["ib/torset"]) | "\(.metadata.name): \(.metadata.labels["ib/torset"])"'
```

## 8. Troubleshooting

### Check Job Status

```bash
kubectl get jobs -n kube-system torset-labeler
kubectl describe job -n kube-system torset-labeler
```

### View Logs

Check each container's logs:

```bash
# Fetch GUIDs
kubectl logs -n kube-system job/torset-labeler -c fetch-guids

# Torset discovery
kubectl logs -n kube-system job/torset-labeler -c torset-discovery

# Apply labels
kubectl logs -n kube-system job/torset-labeler
```

### Common Issues

**No nodes found with HCA GUID annotations**
- Ensure `node-labeler` chart is installed and running
- Check that nodes have `ib/hca-guids` annotations:
  ```bash
  kubectl get nodes -o json | jq -r '.items[] | select(.metadata.annotations["ib/hca-guids"]) | .metadata.name'
  ```

**SHARP command not found**
- Verify the container image has SHARP tools installed
- Check that the Job is scheduled on a node with InfiniBand hardware

**Job fails to schedule**
- Verify the nodepool selector matches available nodes
- Check node resources and scheduling constraints

## 9. Cleanup

To remove the Job and related resources:

```bash
helm uninstall torset-labeler -n kube-system
```

To remove torset labels from nodes:

```bash
kubectl label nodes --all ib/torset-
```

## 10. Re-running Discovery

The Job will complete after labeling nodes. To re-run torset discovery (e.g., after adding new nodes with autoscaling):

1. Delete the existing Job: `helm uninstall torset-labeler -n kube-system`
2. Reinstall: `helm install torset-labeler utilities/aks/torset_labeler/helm -n kube-system`

**Important:** The job automatically removes all existing torset labels from the target nodepool before performing discovery. This ensures:
- Stale labels from removed nodes are cleaned up
- Labels are always consistent with the current topology
- Autoscaling events don't result in mixed label states

## 11. Integration with Workloads

Once nodes are labeled with torsets, you can use these labels in Pod scheduling:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-distributed-workload
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - my-app
        topologyKey: ib/torset
```

This ensures all pods in the workload are scheduled within the same torset for optimal InfiniBand performance.
