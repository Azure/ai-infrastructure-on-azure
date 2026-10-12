#!/bin/bash
# Create AKS cluster with GPU support and workload identity

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize config and resource names
init

# Check prerequisites
check_prereqs az helm kubectl
check_azure_login

echo "🚀 Creating AKS cluster..."
echo "  Cluster: $AKS_CLUSTER_NAME"
echo "  ACR: $ACR_NAME"
echo "  Storage: $STORAGE_ACCOUNT_NAME"
echo ""

# Ensure SSH key exists (required for AKS node access)
if [[ ! -f "$HOME/.ssh/id_rsa" ]]; then
	echo "Generating SSH key..."
	ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" -q
	echo "  ✓ SSH key created"
fi

# Check if cluster exists and its state
cluster_state=$(az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "powerState.code" -o tsv 2>/dev/null | tr -d '\r') || cluster_state=""

if [[ -z "$cluster_state" ]]; then
	echo "Creating AKS cluster..."
	az aks create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$AKS_CLUSTER_NAME" \
		--location "$LOCATION" \
		--node-count "$AKS_SYSTEM_NODE_COUNT" \
		--node-vm-size "$AKS_SYSTEM_NODE_SIZE" \
		--kubernetes-version "$AKS_VERSION" \
		--enable-managed-identity \
		--attach-acr "$ACR_NAME" \
		--enable-cluster-autoscaler \
		--min-count 1 \
		--max-count 3 \
		--enable-oidc-issuer \
		--enable-workload-identity \
		--generate-ssh-keys
elif [[ "$cluster_state" == "Stopped" ]]; then
	echo "AKS cluster is stopped. Starting..."
	az aks start --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME"
	echo "  ✓ Cluster started"
else
	echo "AKS cluster already exists (state: $cluster_state)"
fi

# Get credentials
echo "Getting cluster credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$AKS_CLUSTER_NAME" --overwrite-existing
echo "  💡 New kubectl context added: $(kubectl config current-context)"
echo "     To switch clusters: kubectl config use-context <name>"
echo "     List all contexts:  kubectl config get-contexts"

# Copy kubeconfig to WSL if running in WSL environment
if grep -qi microsoft /proc/version 2>/dev/null; then
	WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "")
	if [[ -n "$WIN_USER" ]] && [[ -f "/mnt/c/Users/$WIN_USER/.kube/config" ]]; then
		mkdir -p ~/.kube
		cp "/mnt/c/Users/$WIN_USER/.kube/config" ~/.kube/config
		chmod 600 ~/.kube/config
	fi
fi

# Add GPU node pool (with 0 nodes initially to avoid idle costs)
# Nodes will be scaled up when deploying workloads (script 05/06)
if ! az aks nodepool show --cluster-name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "$AKS_GPU_NODE_POOL_NAME" &>/dev/null; then
	echo "Adding GPU node pool (0 nodes - will scale up when needed)..."
	az aks nodepool add \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--cluster-name "$AKS_CLUSTER_NAME" \
		--name "$AKS_GPU_NODE_POOL_NAME" \
		--node-count 0 \
		--node-vm-size "$AKS_GPU_NODE_SIZE" \
		--enable-cluster-autoscaler \
		--min-count 0 \
		--max-count 1 \
		--node-osdisk-type Managed \
		--node-taints nvidia.com/gpu=true:NoSchedule \
		--labels workload=gpu-intensive
	echo "  ✓ GPU nodepool created (0 nodes - saves ~\$20/hr until needed)"
else
	echo "GPU node pool already exists"
fi

# ============================================================================
# WORKLOAD IDENTITY SETUP
# Uses a user-assigned managed identity with federated credentials
# This allows pods to authenticate to Azure services (like blob storage)
# ============================================================================
echo "Configuring workload identity..."

# Create namespace
kubectl create namespace workloads 2>/dev/null || echo "  (namespace already exists)"

# Get storage account ID for role assignments
storage_id=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id -o tsv | tr -d '\r')

# Get OIDC issuer URL (required for federated credentials)
oidc_issuer=$(az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query "oidcIssuerProfile.issuerUrl" -o tsv | tr -d '\r')
echo "  OIDC Issuer: $oidc_issuer"

# Create user-assigned managed identity for workload identity
WORKLOAD_IDENTITY_NAME="${PROJECT_NAME}-workload-id"
echo "  Creating managed identity: $WORKLOAD_IDENTITY_NAME"
az identity create --name "$WORKLOAD_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --location "$LOCATION" 2>/dev/null || echo "  (Identity already exists)"

# Wait for identity to propagate
sleep 5

# Get identity details
workload_client_id=$(az identity show --name "$WORKLOAD_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query "clientId" -o tsv | tr -d '\r')
workload_principal_id=$(az identity show --name "$WORKLOAD_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query "principalId" -o tsv | tr -d '\r')
echo "  Client ID: $workload_client_id"

# Grant storage access to workload identity
echo "  Granting Storage Blob Data Contributor role..."
az role assignment create \
	--assignee "$workload_principal_id" \
	--role "Storage Blob Data Contributor" \
	--scope "$storage_id" 2>/dev/null || echo "  (Role assignment may already exist)"

# Create federated credential linking K8s service account to Azure identity
fed_cred_name="workload-identity-sa-federated"
echo "  Creating federated credential..."
az identity federated-credential create \
	--name "$fed_cred_name" \
	--identity-name "$WORKLOAD_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--issuer "$oidc_issuer" \
	--subject "system:serviceaccount:workloads:workload-identity-sa" \
	--audiences "api://AzureADTokenExchange" 2>/dev/null || echo "  (Federated credential may already exist)"

# Create Kubernetes service account with workload identity annotation
kubectl create serviceaccount workload-identity-sa -n workloads 2>/dev/null || true
kubectl annotate serviceaccount workload-identity-sa \
	-n workloads \
	azure.workload.identity/client-id="$workload_client_id" \
	--overwrite

echo "  ✓ Workload identity configured"
echo "    Identity: $WORKLOAD_IDENTITY_NAME"
echo "    Service Account: workloads/workload-identity-sa"

# Install NVIDIA GPU Operator
if ! helm status gpu-operator -n gpu-operator &>/dev/null; then
	echo "Installing NVIDIA GPU Operator..."
	helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
	helm repo update
	helm install gpu-operator nvidia/gpu-operator \
		-n gpu-operator --create-namespace \
		--version v25.3.4 \
		--set operator.runtimeClass=nvidia-container-runtime
else
	echo "GPU Operator already installed"
fi

echo ""
echo "✅ AKS cluster ready!"
echo "  Cluster: $AKS_CLUSTER_NAME"
echo "  GPU Node Pool: $AKS_GPU_NODE_POOL_NAME"
echo "  GPU Operator: Installed"
echo "  Verify: kubectl get nodes"
echo ""
echo "Next: ./scripts/03-setup-gpu-monitoring.sh"
