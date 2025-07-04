#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"

# Check if the DEBUG env var is set to true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# RG specific variables
: "${AZURE_RESOURCE_GROUP:=ai-infra-aks}"

# AKS specific variables
: "${CLUSTER_NAME:=ai-infra}"
: "${USER_NAME:=azureuser}"

# Versions
: "${GPU_OPERATOR_VERSION:=v25.3.1}"
: "${NETWORK_OPERATOR_VERSION:=v25.4.0}"
: "${MPI_OPERATOR_VERSION:=v0.6.0}" # Latest version: https://github.com/kubeflow/mpi-operator/releases

: "${NETWORK_OPERATOR_NS:=network-operator}"
: "${GPU_OPERATOR_NS:=gpu-operator}"

function check_prereqs() {
    local prereqs=("kubectl" "helm" "az" "jq")
    for cmd in "${prereqs[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ $cmd is not installed. Please install it and try again."
            exit 1
        fi
    done
}

# deploy_aks creates a resource group and a new AKS cluster with the provided
# arguments.
function deploy_aks() {
    # RG specific variables
    : "${AZURE_REGION:?❌ Environment variable AZURE_REGION must be set}"

    az group create \
        --name "${AZURE_RESOURCE_GROUP}" \
        --location "${AZURE_REGION}"

    # Let's first check if the cluster already exists.
    existing_cluster=$(az aks show \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --query "name" -o tsv 2>/dev/null || true)
    if [[ -n "${existing_cluster}" ]]; then
        echo "⚠️ AKS cluster '${CLUSTER_NAME}' already exists in resource group '${AZURE_RESOURCE_GROUP}', skipping creation!"
        return 0
    fi

    echo "⏳ Creating AKS cluster '${CLUSTER_NAME}' in resource group '${AZURE_RESOURCE_GROUP}'..."
    az aks create \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --enable-oidc-issuer \
        --enable-workload-identity \
        --enable-managed-identity \
        --node-count 1 \
        --location "${AZURE_REGION}" \
        --generate-ssh-keys \
        --admin-username "${USER_NAME}" \
        --os-sku Ubuntu

    echo "✅ AKS cluster '${CLUSTER_NAME}' created successfully in resource group '${AZURE_RESOURCE_GROUP}'!"
}

# add_nodepool adds a new node pool to the AKS cluster. You can provide additional
# arguments to the function. For example a call would look like this:
# `add_nodepool --gpu-driver none --node-osdisk-size 48`
function add_nodepool() {
    # Node pool specific variables
    : "${NODE_POOL_VM_SIZE:?❌ Environment variable NODE_POOL_VM_SIZE must be set}"
    : "${NODE_POOL_NAME:=gpu}"
    : "${NODE_POOL_NODE_COUNT:=2}"

    aks_infiniband_support="az feature show \
        --namespace Microsoft.ContainerService \
        --name AKSInfinibandSupport -o tsv --query 'properties.state'"

    # Until the output of the above command is not "Registered", keep running the command.
    while [[ "$(eval "$aks_infiniband_support")" != "Registered" ]]; do
        az feature register --name AKSInfinibandSupport --namespace Microsoft.ContainerService
        echo "⏳ Waiting for the feature 'AKSInfinibandSupport' to be registered..."
        sleep 10
    done

    echo "⏳ Adding node pool '${NODE_POOL_NAME}', SKU: '${NODE_POOL_VM_SIZE}', Count: '${NODE_POOL_NODE_COUNT}' to AKS cluster '${CLUSTER_NAME}' in resource group '${AZURE_RESOURCE_GROUP}'!..."
    az aks nodepool add \
        --name "${NODE_POOL_NAME}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --cluster-name "${CLUSTER_NAME}" \
        --node-count "${NODE_POOL_NODE_COUNT}" \
        --node-vm-size "${NODE_POOL_VM_SIZE}" "$@"

    echo "✅ Node pool '${NODE_POOL_NAME}', SKU: '${NODE_POOL_VM_SIZE}', Count: '${NODE_POOL_NODE_COUNT}' added to AKS cluster '${CLUSTER_NAME}' in resource group '${AZURE_RESOURCE_GROUP}'!"
}

# download_aks_credentials downloads the AKS credentials to the local machine. You
# can provide additional arguments to the function. For example a call would look
# like this: `download_aks_credentials --overwrite-existing`
function download_aks_credentials() {
    az aks get-credentials \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" "$@"
}

# install_network_operator installs the NVIDIA network operator on the AKS
# cluster.
function install_network_operator() {
    echo "⏳ Installing Nvidia Network Operator..."

    kubectl create ns "${NETWORK_OPERATOR_NS}" || true
    kubectl label --overwrite ns "${NETWORK_OPERATOR_NS}" pod-security.kubernetes.io/enforce=privileged

    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null
    helm repo update >/dev/null

    helm upgrade -i \
        --wait \
        --create-namespace \
        -n "${NETWORK_OPERATOR_NS}" \
        --values "${CONFIGS_DIR}"/network-operator/values.yaml \
        network-operator \
        nvidia/network-operator \
        --version "${NETWORK_OPERATOR_VERSION}"

    kubectl apply -f "${CONFIGS_DIR}"/network-operator/node-feature-rule.yaml
    kubectl apply -k "${CONFIGS_DIR}"/network-operator/nicclusterpolicy/rdma-shared-device-plugin/

    echo -e "⏳ Waiting for Nvidia Network Operator to be ready, to see behind the scenes run:\n"
    echo "kubectl get NicClusterPolicy nic-cluster-policy"
    echo -e "kubectl get pods -n ${NETWORK_OPERATOR_NS} -o wide\n"

    while true; do
        nic_cluster_policy_state=$(kubectl get NicClusterPolicy nic-cluster-policy -o jsonpath='{.status.state}')
        if [[ "${nic_cluster_policy_state}" == "ready" ]]; then
            echo "✅ Nvidia Network Operator is successfully installed."
            break
        fi

        echo "⏳ Waiting for Nvidia Network Operator to be ready..."
        sleep 5
    done

    echo -e '\nRDMA Shared IB devices on nodes:\n'
    rdma_ib_on_nodes_cmd="kubectl get nodes -l accelerator=nvidia -o json | jq -r '.items[] | {name: .metadata.name, \"rdma/shared_ib\": .status.allocatable[\"rdma/shared_ib\"]}'"
    echo "$ ${rdma_ib_on_nodes_cmd}"
    eval "${rdma_ib_on_nodes_cmd}"
}

function install_gpu_operator() {
    echo "⏳ Installing Nvidia GPU Operator..."

    kubectl create ns "${GPU_OPERATOR_NS}" || true
    kubectl label --overwrite ns "${GPU_OPERATOR_NS}" pod-security.kubernetes.io/enforce=privileged

    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null
    helm repo update >/dev/null

    helm upgrade -i \
        --wait \
        -n "${GPU_OPERATOR_NS}" \
        --create-namespace \
        --values "${CONFIGS_DIR}"/gpu-operator/values.yaml \
        gpu-operator \
        nvidia/gpu-operator \
        --version "${GPU_OPERATOR_VERSION}"

    # Wait for the GPU Operator to be ready
    echo -e "⏳ Waiting for GPU Operator to be ready, to see behind the scenes run:\n"
    echo "kubectl get clusterpolicies cluster-policy"
    echo -e "kubectl get pods -n ${GPU_OPERATOR_NS} -o wide\n"

    while true; do
        gpu_cluster_policy_state=$(kubectl get clusterpolicies cluster-policy -o jsonpath='{.status.state}')
        if [[ "${gpu_cluster_policy_state}" == "ready" ]]; then
            echo "✅ GPU Operator is successfully installed."
            break
        fi

        echo "⏳ Waiting for GPU Operator to be ready..."
        sleep 5
    done

    echo -e '\n🤖 GPUs on nodes:\n'
    gpu_on_nodes_cmd="kubectl get nodes -l accelerator=nvidia -o json | jq -r '.items[] | {name: .metadata.name, \"nvidia.com/gpu\": .status.allocatable[\"nvidia.com/gpu\"]}'"
    echo "$ ${gpu_on_nodes_cmd}"
    eval "${gpu_on_nodes_cmd}"
}

function install_grafana_dashboards() {
    echo "⏳ Installing Grafana dashboards..."

    DASHBOARD_DIR="${CONFIGS_DIR}/monitoring/dashboards"
    mkdir -p "${DASHBOARD_DIR}"
    pushd "${DASHBOARD_DIR}"

    # Let's download the Grafana dashboards here.
    # Nvidia dashboards
    # https://github.com/NVIDIA/dcgm-exporter/tree/main/grafana
    [ -f dcgm-exporter-dashboard.json ] || curl -o dcgm-exporter-dashboard.json -L https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/refs/heads/main/grafana/dcgm-exporter-dashboard.json

    # Iterate over the files in the directory and print them
    for file in *; do
        # Removes the suffix of .json from the file name, converts the _ to - and makes it lowercase
        CM_NAME="$(echo "${file}" | sed 's/\.json//g' | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        kubectl -n monitoring create cm --dry-run=client -o yaml "${CM_NAME}" --from-file "${file}" | kubectl apply -f -
        kubectl -n monitoring label cm "${CM_NAME}" grafana_dashboard=1
    done

    popd
    echo "✅ Grafana dashboards installed successfully."
}

function install_kube_prometheus() {
    echo "⏳ Installing Kube Prometheus..."

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    kube_prometheus_install="helm upgrade -i \
        --wait \
        -n monitoring \
        --create-namespace \
        kube-prometheus \
        prometheus-community/kube-prometheus-stack"

    # If you don't retry then it could fail with errors like:
    # Error: create: failed to create: Post "https://foobar.eastus.azmk8s.io:443/api/v1/namespaces/monitoring/secrets": remote error: tls: bad record MAC
    until ${kube_prometheus_install}; do
        echo "⏳ Waiting for kube-prometheus to be installed..."
        sleep 5
    done

    install_grafana_dashboards
    echo "✅ Kube Prometheus installed successfully."
}

function install_mpi_operator() {
    echo "⏳ Installing MPI Operator..."
    kubectl apply --server-side -f "https://raw.githubusercontent.com/kubeflow/mpi-operator/${MPI_OPERATOR_VERSION}/deploy/v2beta1/mpi-operator.yaml"
    echo "✅ MPI Operator installed successfully."
}

function print_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy-aks               Create a new AKS cluster. Supports additional 'az aks create' arguments"
    echo "  add-nodepool             Add a GPU node pool to the existing AKS cluster. Supports additional 'az aks nodepool add' arguments"
    echo "  install-network-operator Install NVIDIA Network Operator for InfiniBand/RDMA support"
    echo "  install-gpu-operator     Install NVIDIA GPU Operator for GPU workload management"
    echo "  install-kube-prometheus  Install Prometheus monitoring stack with Grafana dashboards"
    echo "  install-mpi-operator     Install MPI Operator for distributed computing workloads"
    echo "  uninstall-mpi-operator   Remove MPI Operator from the cluster"
    echo "  all                      Deploy AKS cluster and install all operators (full setup)"
    echo ""
    echo "Examples:"
    echo "  $0 all"
    echo "  $0 deploy-aks --node-vm-size standard_ds4_v2"
    echo "  $0 add-nodepool --gpu-driver=none --node-osdisk-size 1000"
    echo ""
    echo "Environment Variables (mandatory):"
    echo "  AZURE_REGION             Azure region for deployment"
    echo "  NODE_POOL_VM_SIZE        VM size for GPU nodes"
    echo ""
    echo "Environment Variables (optional):"
    echo "  AZURE_RESOURCE_GROUP     Resource group name (default: ai-infra-aks)"
    echo "  CLUSTER_NAME             AKS cluster name (default: ai-infra)"
    echo "  USER_NAME                Admin username for AKS nodes (default: azureuser)"
    echo "  NODE_POOL_NAME           Node pool name (default: gpu)"
    echo "  NODE_POOL_NODE_COUNT     Number of nodes in pool (default: 2)"
    echo "  GPU_OPERATOR_VERSION     Version of GPU Operator to install (default: v25.3.1)"
    echo "  NETWORK_OPERATOR_VERSION Version of Network Operator to install (default: v25.4.0)"
    echo "  MPI_OPERATOR_VERSION     Version of MPI Operator to install (default: v0.6.0)"
    echo "  NETWORK_OPERATOR_NS      Namespace for Network Operator (default: network-operator)"
    echo "  GPU_OPERATOR_NS          Namespace for GPU Operator (default: gpu-operator)"
    echo ""
}

check_prereqs
PARAM="${1:-}"
case $PARAM in
deploy-aks | deploy_aks)
    deploy_aks "${@:2}"
    download_aks_credentials --overwrite-existing
    ;;
add-nodepool | add_nodepool)
    add_nodepool "${@:2}"
    ;;
install-network-operator | install_network_operator)
    install_network_operator
    ;;
install-gpu-operator | install_gpu_operator)
    install_gpu_operator
    ;;
install-kube-prometheus | install_kube_prometheus)
    install_kube_prometheus
    ;;
install-mpi-operator | install_mpi_operator)
    install_mpi_operator
    ;;
uninstall-mpi-operator | uninstall_mpi_operator)
    kubectl delete --server-side -f "https://raw.githubusercontent.com/kubeflow/mpi-operator/${MPI_OPERATOR_VERSION}/deploy/v2beta1/mpi-operator.yaml"
    ;;
all)
    deploy_aks
    download_aks_credentials --overwrite-existing
    install_kube_prometheus
    install_mpi_operator
    add_nodepool --gpu-driver=none
    install_network_operator
    install_gpu_operator
    ;;
*)
    print_usage
    exit 1
    ;;
esac
