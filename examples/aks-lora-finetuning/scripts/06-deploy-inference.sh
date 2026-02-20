#!/bin/bash
# Deploy side-by-side comparison inference with Web UI (2 GPUs)

# Parse arguments first (before sourcing common.sh which sets -e)
REPLICAS=1

while [[ $# -gt 0 ]]; do
	case $1 in
	--replicas | -r)
		REPLICAS="$2"
		shift 2
		;;
	--help | -h)
		echo "Usage: $0 [--replicas N]"
		echo "  Deploys GPT-OSS-20B side-by-side comparison with Web UI"
		echo "  Requires: 2 GPUs (fine-tuned vs baseline)"
		echo "  --replicas: Number of replicas (default: 1)"
		exit 0
		;;
	*)
		echo "Unknown: $1 (use --help)"
		exit 1
		;;
	esac
done

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize config and resource names
init

# Check prerequisites
check_prereqs az kubectl
check_azure_login

echo "🚀 Deploying GPT-OSS-20B Side-by-Side Comparison"
echo "   Mode: 2 GPU with Web UI"
echo "   Replicas: $REPLICAS"
echo ""

# Check if GPU nodes are available, scale up if needed
gpu_node_count=$(az aks nodepool show \
	--cluster-name "$AKS_CLUSTER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$AKS_GPU_NODE_POOL_NAME" \
	--query "count" -o tsv 2>/dev/null | tr -d '\r')

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
	kubectl wait --for=condition=Ready nodes -l workload=gpu-intensive --timeout=600s 2>/dev/null ||
		echo "  (Waiting for node to appear...)"

	# Wait for DCGM exporter to start scraping metrics
	echo "  Waiting for GPU metrics to be ready..."
	kubectl wait --for=condition=Ready pod -l app=nvidia-dcgm-exporter -n gpu-operator --timeout=120s 2>/dev/null || true
	echo "  ✓ GPU metrics ready"
else
	echo "  GPU nodepool already has $gpu_node_count node(s)"
fi

# Build and push image
echo "📦 Building inference image..."
az acr build \
	--registry "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--image "gpt-oss-inference:latest" \
	--file "docker/Dockerfile.inference" \
	.

echo "✓ Image built and pushed"

# Get AKS credentials
echo ""
echo "🔗 Connecting to AKS..."
az aks get-credentials \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$AKS_CLUSTER_NAME" \
	--overwrite-existing

# Deploy
echo ""
echo "📋 Deploying comparison inference..."
kubectl create namespace workloads --dry-run=client -o yaml | kubectl apply -f -

# Substitute placeholders and apply
sed -e "s/__ACR_NAME__/${ACR_NAME}/g" \
	-e "s/__STORAGE_ACCOUNT_NAME__/${STORAGE_ACCOUNT_NAME}/g" \
	./k8s/inference-deployment.yaml | kubectl apply -f -

# Scale
if [ "$REPLICAS" -gt 0 ]; then
	echo ""
	echo "⚖️  Scaling to $REPLICAS replica(s)..."
	kubectl scale deployment gpt-oss-inference -n workloads --replicas=$REPLICAS

	echo "   ⏳ Waiting for pods (model load ~3-4 min)..."
	kubectl wait --for=condition=available --timeout=600s \
		deployment/gpt-oss-inference -n workloads 2>/dev/null ||
		echo "   ⚠️  Not ready yet. Check: kubectl logs -n workloads -l app=gpt-oss-inference -f"
fi

# Get LoadBalancer IP
echo ""
echo "🌐 Getting LoadBalancer IP..."
for i in {1..30}; do
	ip=$(kubectl get svc gpt-oss-inference -n workloads -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
	[ -n "$ip" ] && break
	echo -n "."
	sleep 2
done
echo ""

# Summary
echo ""
echo "✅ Deployment Complete!"
echo ""
if [ -n "$ip" ]; then
	echo "🌍 Web UI: http://${ip}"
else
	echo "⏳ IP pending: kubectl get svc gpt-oss-inference -n workloads"
fi
echo ""
echo "📊 Useful Commands:"
echo "   kubectl get pods -n workloads -l app=gpt-oss-inference"
echo "   kubectl logs -n workloads -l app=gpt-oss-inference -f"
echo "   kubectl scale deployment gpt-oss-inference -n workloads --replicas=0  # Stop"
