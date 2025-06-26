# Deploy AKS

This repository contains scripting and resources for running AI workloads on Azure Kubernetes Service (AKS).

## Pre-requisites

* Azure Subscription
* A client with the Azure CLI installed
* Docker for building images
* Quota for GPU nodes on Azure (examples use NDv5)
* Linux shell (use WSL for Windows)

## Define Variables

The following are variables will be used in the deployment steps:

```
export RESOURCE_GROUP=
export LOCATION=
export CLUSTER_NAME=
export ACR_NAME=
```

## Deploy Azure Resources

### Enable AKS Infiniband support

The feature need to be registered to ensure the AKS cluster is deployed with Infiniband support.  The following command will register the feature:

```
az feature register --name AKSInfinibandSupport --namespace Microsoft.ContainerService
```

Note: check the feature status with the following command to ensure it is reporting `Registered`:

```
az feature show --name AKSInfinibandSupport --namespace Microsoft.ContainerService --query properties.state --output tsv
```

### Create a resource group

```
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Create an Azure Container Registry

```
az acr create \
    --resource-group $RESOURCE_GROUP \
    --name $ACR_NAME \
    --sku Basic \
    --admin-enabled
```

### Create an AKS cluster

```
az aks create \
  --resource-group $RESOURCE_GROUP \
  --node-resource-group ${RESOURCE_GROUP}-nrg \
  --name $CLUSTER_NAME \
  --enable-managed-identity \
  --node-count 2 \
  --generate-ssh-keys \
  --location $LOCATION \
  --node-vm-size standard_d4ads_v5 \
  --nodepool-name system \
  --os-sku Ubuntu \
  --attach-acr $ACR_NAME
```

### Add an NDv5 node pool

This will create a node pool using for NDv5 VMs.  The `--gpu-driver none` flag is used to ensure AKS is not managing the GPU drivers.  Instead we will manage this with the NVIDIA GPU operator.

```
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name ndv5 \
  --node-count 1 \
  --node-vm-size Standard_ND96isr_H100_v5 \
  --node-osdisk-size 128 \
  --os-sku Ubuntu \
  --gpu-driver none
```

## Installing tools

### Install kubectl

Once the AKS cluster is created you will need to install kubectl to interact with the cluster.  The following commands will install kubectl and configure it to use the AKS cluster:

```
az aks install-cli
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
```

### Helm

Helm is a package manager for Kubernetes that allows you to easily deploy and manage applications on your AKS cluster.  The following commands will get the latest version of Helm and install it locally:

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### K9s (optional)

[K9s](https://k9scli.io/) is a terminal-based UI for Kubernetes that allows you to easily navigate and manage your Kubernetes resources.  The following command will download and install the linux K9s for amd64:

```
curl -L https://github.com/derailed/k9s/releases/download/v0.50.6/k9s_Linux_amd64.tar.gz | tar xz -C ~/bin k9s
```

> Note: This will put k9s in $HOME/path. Ensure the directory is present and in your PATH.

## NVIDIA Drivers

The NVIDIA CPU and Network operators are used to manage the GPU drivers and Infiniband drivers on the NDv5 nodes. The installations will all use Helm.

### Add the nvidia repository to Helm

```
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Install Network Operator

```
helm upgrade --install \
  --create-namespace -n network-operator \
  network-operator nvidia/network-operator \
  --set nfd.deployNodeFeatureRules=false \
  --version v25.4.0
```

Create the node feature rules:

```network-operator-nfd.yaml
apiVersion: nfd.k8s-sigs.io/v1alpha1
kind: NodeFeatureRule
metadata:
  name: nfd-network-rule
spec:
   rules:
   - name: "nfd-network-rule"
     labels:
        "feature.node.kubernetes.io/pci-15b3.present": "true"
     matchFeatures:
        - feature: pci.device
          matchExpressions:
            device: {op: In, value: ["101c", "101e"]}
```

Apply the rules:

```
kubectl apply -f network-operator-nfd.yaml
```

Create the nic cluster policy:

```sriov.yaml
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy
spec:
  docaTelemetryService:
    image: doca_telemetry
    repository: nvcr.io/nvidia/doca
    version: 1.16.5-doca2.6.0-host
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: feature.node.kubernetes.io/pci-15b3.present
          operator: In
          values:
          - "true"
  ofedDriver:
    env:
    - name: OFED_BLACKLIST_MODULES_FILE
      value: /host/etc/modprobe.d/blacklist-ofed-modules.conf
    forcePrecompiled: false
    image: doca-driver
    livenessProbe:
      initialDelaySeconds: 30
      periodSeconds: 30
    readinessProbe:
      initialDelaySeconds: 10
      periodSeconds: 30
    repository: nvcr.io/nvidia/mellanox
    startupProbe:
      initialDelaySeconds: 10
      periodSeconds: 20
    upgradePolicy:
      autoUpgrade: true
      drain:
        deleteEmptyDir: true
        enable: true
        force: true
        timeoutSeconds: 300
      maxParallelUpgrades: 1
    version: 25.04-0.6.1.0-2
  sriovDevicePlugin:
    config: |
      {
        "resourceList": [
          {
            "resourcePrefix": "rdma",
            "resourceName": "ib",
            "selectors": {
              "vendors": ["15b3"],
              "linkTypes": ["infiniband"],
              "isRdma": true
            }
          }
        ]
      }
    image: sriov-network-device-plugin
    repository: ghcr.io/k8snetworkplumbingwg
    version: v3.9.0
```

### Install GPU Operator

```
helm upgrade --install \
  --create-namespace -n gpu-operator \
  gpu-operator nvidia/gpu-operator \
  --set nfd.enabled=false \
  --set driver.rdma.enabled=true \
  --version v25.3.1
```

## K8s packages

### MPI Operator

Install mpi-operator:

```
MPI_OPERATOR_VERSION=v0.6.0
kubectl apply --server-side -f "https://raw.githubusercontent.com/kubeflow/mpi-operator/${MPI_OPERATOR_VERSION}/deploy/v2beta1/mpi-operator.yaml"
```