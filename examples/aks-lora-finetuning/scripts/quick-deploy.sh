#!/bin/bash

# Quick deployment script for AKS GPU Fine-tuning
set -e

echo "🚀 Starting quick deployment..."

# 1. Setup Azure resources
echo "📋 Step 1: Setting up Azure resources..."
bash ./scripts/01-setup-azure-resources.sh

# 2. Create AKS cluster  
echo "🏗️  Step 2: Creating AKS cluster..."
bash ./scripts/02-create-aks-cluster.sh

# 3. Setup GPU monitoring
echo "📊 Step 3: Setting up GPU monitoring..."
bash ./scripts/03-setup-gpu-monitoring.sh

# 4. Build and push Docker image
echo "🐳 Step 4: Building and pushing Docker image..."
bash ./scripts/04-build-and-push-image.sh

# 5. Deploy fine-tuning job
echo "🎯 Step 5: Deploying fine-tuning job..."
bash ./scripts/05-deploy-finetune.sh

echo ""
echo "⏳ Waiting for fine-tuning to complete..."
echo "   Monitor: kubectl logs job/gpt-oss-finetune -n workloads -f"
echo ""

# Wait for fine-tuning job to complete
while true; do
    status=$(kubectl get job gpt-oss-finetune -n workloads -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    failed=$(kubectl get job gpt-oss-finetune -n workloads -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    
    if [ "$status" = "True" ]; then
        echo "✅ Fine-tuning completed successfully!"
        break
    elif [ "$failed" = "True" ]; then
        echo "❌ Fine-tuning failed. Check logs: kubectl logs job/gpt-oss-finetune -n workloads"
        exit 1
    fi
    
    echo -n "."
    sleep 30
done

echo ""
# 6. Deploy inference service
echo "🌐 Step 6: Deploying inference service..."
bash ./scripts/06-deploy-inference.sh --replicas 1

echo "✅ Deployment complete!"
echo ""
echo "Check status with:"
echo "  kubectl get pods -A"
echo "  kubectl get jobs -n workloads" 
echo "  kubectl get svc -n workloads"