# Azure Kubernetes Service (AKS) Infrastructure Setup

This document provides a guide to set up an Azure Kubernetes Service (AKS) cluster with GPU support, including the installation of necessary operators and monitoring tools.

## Prerequisites

- Access to an Azure subscription with permissions to create resources.
- Azure CLI [installed](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and configured.
- Kubectl [installed](https://kubernetes.io/docs/tasks/tools/#kubectl) in your environment.
- Helm [installed](https://helm.sh/docs/intro/install/) for managing Kubernetes applications.
- jq [installed](https://jqlang.github.io/jq/download) for processing JSON.

## Setup

Export the following environment variables to configure your AKS cluster:

```bash
export AZURE_REGION=""
export NODE_POOL_VM_SIZE=""

# # Optional
# export NODE_POOL_NODE_COUNT="2"
# export AZURE_RESOURCE_GROUP="ai-infra-aks"
# export NODE_POOL_NAME=""
# export CLUSTER_NAME=""
# export USER_NAME=""
# export GPU_OPERATOR_VERSION=""
# export NETWORK_OPERATOR_VERSION=""
# export MPI_OPERATOR_VERSION=""
```

Run the following command to deploy the AKS cluster and additional necessary components:

```bash
./scripts/deploy-aks.sh all
```

## Monitoring

### Prometheus

To access the Prometheus dashboard, run the following command:

```bash
kubectl -n monitoring port-forward svc/prometheus-operated 9090
```

Go to <http://127.0.0.1:9090> to access the Prometheus dashboard.

### Grafana

To access the Grafana dashboard, run the following command:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-grafana 3000:80
```

Go to <http://127.0.0.1:3000/dashboards> and enter username as `admin` and password as `prom-operator`.
