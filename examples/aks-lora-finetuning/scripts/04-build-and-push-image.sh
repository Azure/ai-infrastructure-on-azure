#!/bin/bash
# Build and push Docker image to ACR

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize config and resource names
init

# Check prerequisites
check_prereqs az
check_azure_login

echo "🐳 Building and pushing images to $ACR_NAME..."

# Note: az acr build doesn't require local Docker or az acr login
# It builds images in the cloud using ACR's build service

# Build and push fine-tuning image
echo "Building fine-tuning image..."
az acr build --registry "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--image gpt-oss-finetune:latest \
	--file ./docker/Dockerfile \
	./

# Build and push inference image
echo "Building inference image..."
az acr build --registry "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--image gpt-oss-inference:latest \
	--file ./docker/Dockerfile.inference \
	./

echo "✅ Images pushed to $ACR_NAME.azurecr.io"
echo ""
echo "Next: ./scripts/05-deploy-finetune.sh"
