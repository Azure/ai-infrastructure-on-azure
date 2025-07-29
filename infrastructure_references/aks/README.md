# Azure Kubernetes Service (AKS) Infrastructure Setup

This document provides a guide to set up an Azure Kubernetes Service (AKS) cluster with GPU support, including the installation of necessary operators and monitoring tools.

## Prerequisites

- Access to an Azure subscription with permissions to create resources.
- Azure CLI [installed](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and configured.
- Kubectl [installed](https://kubernetes.io/docs/tasks/tools/#kubectl) in your environment.
- Helm [installed](https://helm.sh/docs/intro/install/) for managing Kubernetes applications.
- jq [installed](https://jqlang.github.io/jq/download) for processing JSON.
- Git [installed](https://git-scm.com/downloads) for cloning repositories (required for AMLFS installation).
- Kustomize [installed](https://github.com/kubernetes-sigs/kustomize/releases) for managing Kubernetes configurations (required for PyTorch Operator installation). 

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
# export SYSTEM_POOL_VM_SIZE=""
# export GPU_OPERATOR_VERSION=""
# export NETWORK_OPERATOR_VERSION=""
# export MPI_OPERATOR_VERSION=""
# export CERT_MANAGER_VERSION=""
# export PYTORCH_OPERATOR_VERSION=""
# export RDMA_DEVICE_PLUGIN=""
```

Run the following command to deploy the AKS cluster and additional necessary components:

```bash
./scripts/deploy-aks.sh all
```

## Available Commands

The `deploy-aks.sh` script supports the following commands:

### Infrastructure Commands

- **`deploy-aks`** - Create a new AKS cluster with basic configuration
- **`add-nodepool`** - Add a GPU node pool to an existing AKS cluster
- **`all`** - Deploy AKS cluster and install all operators (complete setup)

### Operator Installation Commands

- **`install-network-operator`** - Install NVIDIA Network Operator for InfiniBand/RDMA support
- **`install-gpu-operator`** - Install NVIDIA GPU Operator for GPU workload management
- **`install-kube-prometheus`** - Install Prometheus monitoring stack with Grafana dashboards
- **`install-mpi-operator`** - Install MPI Operator for distributed computing workloads
- **`install-pytorch-operator`** - Install PyTorch Operator (includes cert-manager) for PyTorch distributed training
- **`install-amlfs`** - Install Azure Managed Lustre File System (AMLFS) CSI driver and configure required roles

### Operator Removal Commands

- **`uninstall-mpi-operator`** - Remove MPI Operator from the cluster
- **`uninstall-pytorch-operator`** - Remove PyTorch Operator and cert-manager from the cluster

### Usage Examples

```bash
# Complete setup (recommended for new deployments)
./scripts/deploy-aks.sh all

# Individual component installation
./scripts/deploy-aks.sh deploy-aks
./scripts/deploy-aks.sh add-nodepool
./scripts/deploy-aks.sh install-pytorch-operator
./scripts/deploy-aks.sh install-amlfs

# Install with custom parameters
./scripts/deploy-aks.sh deploy-aks --node-vm-size standard_ds4_v2
./scripts/deploy-aks.sh add-nodepool --gpu-driver=none --node-osdisk-size 1000

# Skip AMLFS installation in complete setup
INSTALL_AMLFS=false ./scripts/deploy-aks.sh all
```

## Environment Variables

### Mandatory Variables

- **`AZURE_REGION`** - Azure region for deployment (e.g., "eastus", "westus2")
- **`NODE_POOL_VM_SIZE`** - VM size for GPU nodes (e.g., "Standard_NC24ads_A100_v4")

### Optional Configuration Variables

- **`AZURE_RESOURCE_GROUP`** - Resource group name (default: "ai-infra-aks")
- **`CLUSTER_NAME`** - AKS cluster name (default: "ai-infra")
- **`USER_NAME`** - Admin username for AKS nodes (default: "azureuser")
- **`SYSTEM_POOL_VM_SIZE`** - VM size for system node pool (default: empty, AKS selects appropriate size)
- **`NODE_POOL_NAME`** - Node pool name (default: "gpu")
- **`NODE_POOL_NODE_COUNT`** - Number of nodes in pool (default: 2)

### Operator Version Variables

- **`GPU_OPERATOR_VERSION`** - Version of GPU Operator to install (default: "v25.3.1")
- **`NETWORK_OPERATOR_VERSION`** - Version of Network Operator to install (default: "v25.4.0")
- **`MPI_OPERATOR_VERSION`** - Version of MPI Operator to install (default: "v0.6.0")
- **`CERT_MANAGER_VERSION`** - Version of cert-manager to install (default: "v1.18.2")
- **`PYTORCH_OPERATOR_VERSION`** - Version of PyTorch Operator to install (default: "v1.8.1")

### Namespace Configuration

- **`NETWORK_OPERATOR_NS`** - Namespace for Network Operator (default: "network-operator")
- **`GPU_OPERATOR_NS`** - Namespace for GPU Operator (default: "gpu-operator")

### RDMA Configuration

- **`RDMA_DEVICE_PLUGIN`** - RDMA device plugin type (default: "sriov-device-plugin")
  - Options: "sriov-device-plugin", "rdma-shared-device-plugin"

### AMLFS Configuration

- **`INSTALL_AMLFS`** - Install Azure Managed Lustre File System CSI driver (default: "true")
  - Set to "false" to skip AMLFS installation in the 'all' command

## RDMA Device Plugin Configuration

The script supports two types of RDMA device plugins for InfiniBand networking:

### SR-IOV Device Plugin (Default)

- **Environment Variable**: `RDMA_DEVICE_PLUGIN=sriov-device-plugin`
- **Resource Name**: `rdma/ib`
- **Use Case**: Standard SR-IOV networking with dedicated virtual functions per pod
- **Benefits**: Better isolation and performance per pod

### RDMA Shared Device Plugin

- **Environment Variable**: `RDMA_DEVICE_PLUGIN=rdma-shared-device-plugin`
- **Resource Name**: `rdma/shared_ib`
- **Use Case**: Shared RDMA resources across multiple pods
- **Benefits**: Higher resource utilization when multiple pods need RDMA access

### Usage Examples

Deploy with SR-IOV device plugin (default):

```bash
./scripts/deploy-aks.sh all
```

Deploy with RDMA shared device plugin:

```bash
export RDMA_DEVICE_PLUGIN=rdma-shared-device-plugin
./scripts/deploy-aks.sh all
```

Install only the network operator with specific plugin:

```bash
export RDMA_DEVICE_PLUGIN=rdma-shared-device-plugin
./scripts/deploy-aks.sh install-network-operator
```

## Azure Managed Lustre File System (AMLFS) Support

The deployment script includes support for Azure Managed Lustre File System (AMLFS), which provides high-performance storage for AI/ML workloads.

### AMLFS Installation

AMLFS is installed by default when running the `all` command. The installation process:

1. **Clones the Azure Lustre CSI driver repository** from the dynamic provisioning preview branch
2. **Installs the CSI driver** using the official installation script
3. **Configures Azure roles** for the AKS kubelet identity to manage AMLFS resources

### Required Azure Roles

The script automatically assigns the following roles to the kubelet identity:

- **Contributor** (Resource Group scope) - For managing resources within the AKS node resource group
- **Reader** (Subscription scope) - For reading subscription resources

### AMLFS Usage Examples

```bash
# Install AMLFS separately
./scripts/deploy-aks.sh install-amlfs

# Deploy everything including AMLFS (default behavior)
./scripts/deploy-aks.sh all

# Deploy everything but skip AMLFS installation
INSTALL_AMLFS=false ./scripts/deploy-aks.sh all
```

### AMLFS Configuration

- **Environment Variable**: `INSTALL_AMLFS` (default: `true`)
- **CSI Driver**: Azure Lustre CSI Driver (dynamic provisioning preview)
- **Branch**: `dynamic-provisioning-preview`
- **Repository**: `https://github.com/kubernetes-sigs/azurelustre-csi-driver.git`


## Monitoring

### Installation

To install the Kube Prometheus stack for monitoring, run the following command:

```bash
./scripts/deploy-aks.sh install-kube-prometheus
```

> [!NOTE]
> You can also set the Grafana admin password by exporting the environment variable `GRAFANA_PASSWORD` before running the deployment script. If not set, a random password will be generated.

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

Go to <http://127.0.0.1:3000/dashboards> and enter username as `admin`. You can find the Grafana admin password by running the following command:

```bash
kubectl -n monitoring get secret kube-prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 --decode
```
