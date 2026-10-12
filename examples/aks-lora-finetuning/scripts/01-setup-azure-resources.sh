#!/bin/bash
# Setup Azure resources for AKS GPU fine-tuning project

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize config and resource names
init

# Check prerequisites
check_prereqs az
check_azure_login

echo "Subscription: $(az account show --query name -o tsv)"

echo ""
echo "Configuration:"
echo "  Suffix: ${UNIQUE_SUFFIX}"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container Registry: $ACR_NAME"
echo ""

# Register required resource providers (needed for new subscriptions)
echo "📋 Checking resource providers..."
providers=("Microsoft.ContainerService" "Microsoft.ContainerRegistry" "Microsoft.Storage" "Microsoft.Monitor" "Microsoft.AlertsManagement" "Microsoft.Dashboard" "Microsoft.OperationalInsights")
for provider in "${providers[@]}"; do
	state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
	if [[ "$state" != "Registered" ]]; then
		echo "  Registering $provider..."
		az provider register --namespace "$provider" --wait 2>/dev/null || echo "  ⚠ Could not register $provider (may need owner permissions)"
	fi
done
echo "  ✓ Resource providers ready"

# Create resource group
echo ""
echo "Creating resource group..."
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"

# Create storage account with security settings
echo "Creating storage account..."
az storage account create \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--sku Standard_LRS \
	--allow-blob-public-access false \
	--allow-shared-key-access false \
	--public-network-access Enabled

# Create blob containers for models and datasets
echo "Creating blob containers..."
az storage container create --name "$STORAGE_CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT_NAME" --auth-mode login
az storage container create --name "$STORAGE_DATASET_CONTAINER" --account-name "$STORAGE_ACCOUNT_NAME" --auth-mode login

# Create container registry
echo "Creating container registry..."
az acr create --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP_NAME" --sku "$ACR_SKU" --location "$LOCATION" || true

# Summary
echo ""
echo "✓ Setup complete!"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Storage: $STORAGE_ACCOUNT_NAME (containers: $STORAGE_CONTAINER_NAME, $STORAGE_DATASET_CONTAINER)"
echo "  Registry: $ACR_NAME"

echo ""
echo "Next: ./scripts/02-create-aks-cluster.sh"
