# Node Labeler for AKS

This chart deploys a DaemonSet that labels and annotates each node with:
- **Labels**: KVP-derived host information from `/var/lib/hyperv/.kvp_pool_3` (e.g., `hyperv/PhysicalHostName`)
- **Labels**: InfiniBand PKey (`ib/pkey`) when RDMA devices are present
- **Annotations**: HCA (Host Channel Adapter) GUIDs (`ib/hca-guids`) as a comma-separated list when InfiniBand devices are detected

The HCA GUID annotations are used by the [Torset Labeler](../../torset_labeler/helm/README.md) to discover and label nodes with their InfiniBand switching domain (torset) information.

## Prerequisites

- Cluster-admin permissions to install cluster-scoped RBAC.
- Nodes with InfiniBand hardware will have HCA GUID annotations automatically collected.


## Installation

Install or upgrade the chart from this repository (namespace is `kube-system`):

```bash
helm upgrade --install node-labeler ./utilities/aks/node_labeler/helm -n kube-system
```

## Verification

Verify the DaemonSet rollout:

```bash
kubectl get pods -n kube-system -l app=node-labeler
```

Check labels applied to a node (replace `<node-name>` with actual node name):

```bash
kubectl get node <node-name> --show-labels | tr ',' '\n' | egrep '(^|,)hyperv/|ib/pkey'
```

Check HCA GUID annotations on nodes with InfiniBand:

```bash
kubectl get nodes -o json | jq -r '.items[] | select(.metadata.annotations["ib/hca-guids"]) | {name: .metadata.name, guids: .metadata.annotations["ib/hca-guids"]}'
```

Once HCA GUIDs are collected, use the [Torset Labeler](../../torset_labeler/helm/README.md) to discover and apply torset labels.

## Uninstallation

Remove the node labeler from your cluster:

```bash
helm uninstall node-labeler -n kube-system
```