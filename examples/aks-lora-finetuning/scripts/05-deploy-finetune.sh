#!/bin/bash
# Deploy Fine-tuning Job
# Simple script to deploy the GPT-OSS fine-tuning job

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize config and resource names
init

# Check prerequisites
check_prereqs kubectl az

echo "🎯 Deploying fine-tuning job..."
echo "  ACR: $ACR_NAME"
echo "  Storage: $STORAGE_ACCOUNT_NAME"

# Ensure we're in the right subscription
az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null || true

# Check if GPU nodes are available, scale up if needed
echo "  Checking GPU nodepool '$AKS_GPU_NODE_POOL_NAME'..."
gpu_node_count=$(az aks nodepool show \
    --cluster-name "$AKS_CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$AKS_GPU_NODE_POOL_NAME" \
    --query "count" -o tsv 2>/dev/null | tr -d '\r')

echo "  Current GPU node count: ${gpu_node_count:-'unknown'}"

if [[ "$gpu_node_count" == "0" ]] || [[ -z "$gpu_node_count" ]]; then
    echo "🚀 Scaling up GPU nodepool (this may take 5-10 minutes)..."
    az aks nodepool update \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --cluster-name "$AKS_CLUSTER_NAME" \
        --name "$AKS_GPU_NODE_POOL_NAME" \
        --update-cluster-autoscaler \
        --min-count 1 \
        --max-count 1
    
    echo "  Waiting for GPU node to be ready..."
    kubectl wait --for=condition=Ready nodes -l workload=gpu-intensive --timeout=600s 2>/dev/null || \
        echo "  (Waiting for node to appear...)"
    
    # Wait for GPU operator pods to be ready
    sleep 30
    
    # Wait for DCGM exporter to start scraping metrics
    echo "  Waiting for GPU metrics to be ready..."
    kubectl wait --for=condition=Ready pod -l app=nvidia-dcgm-exporter -n gpu-operator --timeout=120s 2>/dev/null || true
    sleep 60  # Allow first scrapes to be ingested by Azure Monitor
    echo "  ✓ GPU metrics ready"
else
    echo "  GPU nodepool already has $gpu_node_count node(s)"
fi

# Substitute placeholders and apply
sed -e "s/__ACR_NAME__/${ACR_NAME}/g" \
    -e "s/__STORAGE_ACCOUNT_NAME__/${STORAGE_ACCOUNT_NAME}/g" \
    ./k8s/finetune-job.yaml | kubectl apply -f -

echo "✅ Fine-tuning job deployed!"
echo ""
echo "Monitor with:"
echo "  kubectl get pods -n workloads -w"
echo "  kubectl logs -f job/gpt-oss-finetune -n workloads"
echo ""
echo "💡 Tip: Scale down GPU when done to save costs:"
echo "  az aks nodepool update --resource-group $RESOURCE_GROUP_NAME --cluster-name $AKS_CLUSTER_NAME --name $AKS_GPU_NODE_POOL_NAME --update-cluster-autoscaler --min-count 0 --max-count 0"
