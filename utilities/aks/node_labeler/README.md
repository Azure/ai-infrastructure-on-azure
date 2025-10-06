# Node Labeler for AKS

This chart deploys a DaemonSet that labels each node with:
- KVP-derived labels from `/var/lib/hyperv/.kvp_pool_3`
- The IB PKey found on the node (`ib/pkey`)
- The fabric torset derived via SHARP tooling (`ib/torset`) when RDMA is available

## Prerequisites

- Cluster-admin permissions to install cluster-scoped RBAC.
- Optional: RDMA device plugin on IB-enabled nodes (torset discovery will gracefully skip if absent).


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
kubectl get node <node-name> --show-labels | tr ',' '\n' | egrep '(^|,)hyperv/|ib/pkey|ib/torset'
```

## Uninstallation

Remove the node labeler from your cluster:

```bash
helm uninstall node-labeler -n kube-system
```