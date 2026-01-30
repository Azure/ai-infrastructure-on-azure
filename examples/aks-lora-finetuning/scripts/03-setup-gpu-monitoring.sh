#!/bin/bash
# Setup GPU monitoring - Azure Managed Prometheus + Grafana + DCGM exporter

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Initialize config and resource names
init

# Check prerequisites
check_prereqs az kubectl
check_azure_login

: "${AKS_CLUSTER_NAME:?}" "${RESOURCE_GROUP_NAME:?}" "${LOCATION:?}"

MONITOR_NAME="${AKS_CLUSTER_NAME:0:15}-mon"
GRAFANA_NAME="${AKS_CLUSTER_NAME:0:15}-graf"

echo "🔧 Setting up GPU monitoring for AKS cluster..."

# Step 1: Azure Monitor Workspace
echo ""
echo "📊 Step 1: Creating Azure Monitor Workspace..."
az monitor account show -n "$MONITOR_NAME" -g "$RESOURCE_GROUP_NAME" &>/dev/null || \
    az monitor account create -n "$MONITOR_NAME" -g "$RESOURCE_GROUP_NAME" -l "$LOCATION" -o none
MONITOR_ID=$(az monitor account show -n "$MONITOR_NAME" -g "$RESOURCE_GROUP_NAME" --query id -o tsv | tr -d '\r')
echo "  ✓ Workspace: $MONITOR_NAME"

# Step 2: Azure Managed Grafana
echo ""
echo "📈 Step 2: Creating Azure Managed Grafana..."
az grafana show -n "$GRAFANA_NAME" -g "$RESOURCE_GROUP_NAME" &>/dev/null || \
    az grafana create -n "$GRAFANA_NAME" -g "$RESOURCE_GROUP_NAME" -l "$LOCATION" --skip-role-assignments false -o none
GRAFANA_ID=$(az grafana show -n "$GRAFANA_NAME" -g "$RESOURCE_GROUP_NAME" --query id -o tsv | tr -d '\r')
GRAFANA_URL=$(az grafana show -n "$GRAFANA_NAME" -g "$RESOURCE_GROUP_NAME" --query "properties.endpoint" -o tsv | tr -d '\r')
echo "  ✓ Grafana: $GRAFANA_URL"

# Step 3: Enable metrics addon
echo ""
echo "🔗 Step 3: Enabling Azure Monitor metrics addon..."
METRICS_ENABLED=$(az aks show -n "$AKS_CLUSTER_NAME" -g "$RESOURCE_GROUP_NAME" \
    --query "azureMonitorProfile.metrics.enabled" -o tsv 2>/dev/null | tr -d '\r' || echo "false")

if [[ "$METRICS_ENABLED" != "true" ]]; then
    az aks update -n "$AKS_CLUSTER_NAME" -g "$RESOURCE_GROUP_NAME" \
        --enable-azure-monitor-metrics \
        --azure-monitor-workspace-resource-id "$MONITOR_ID" \
        --grafana-resource-id "$GRAFANA_ID" -o none
fi
echo "  ✓ Metrics addon enabled"

kubectl wait --for=condition=Ready pods -l rsName=ama-metrics -n kube-system --timeout=300s &>/dev/null || true

# Step 4: Configure DCGM exporter
echo ""
echo "🏷️ Step 4: Configuring DCGM exporter..."
for i in {1..6}; do
    kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter --no-headers 2>/dev/null | grep -q . && break
    echo "  Waiting for DCGM exporter... ($i/6)" && sleep 10
done

kubectl patch ds nvidia-dcgm-exporter -n gpu-operator --type=merge \
    -p='{"spec":{"template":{"metadata":{"annotations":{"prometheus.io/scrape":"true","prometheus.io/port":"9400","prometheus.io/path":"/metrics"}}}}}' 2>/dev/null \
    && echo "  ✓ Annotations added" || echo "  ⚠ DCGM DaemonSet not found"

# Step 5: Create Prometheus scrape config
echo ""
echo "⚙️ Step 5: Creating Prometheus scrape config..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ama-metrics-prometheus-config
  namespace: kube-system
data:
  prometheus-config: |
    scrape_configs:
    - job_name: dcgm-exporter
      scrape_interval: 30s
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [gpu-operator]
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: nvidia-dcgm-exporter
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        target_label: __address__
        replacement: ${1}:9400
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
EOF
echo "  ✓ Scrape config created"

# Step 6: Restart Azure Monitor components
echo ""
echo "🔄 Step 6: Restarting Azure Monitor components..."
kubectl rollout restart ds/ama-metrics-node deploy/ama-metrics -n kube-system &>/dev/null || true
kubectl rollout status ds/ama-metrics-node -n kube-system --timeout=120s &>/dev/null || true
echo "  ✓ Components restarted"

# Step 7: Import dashboard
echo ""
echo "📊 Step 7: Importing DCGM Dashboard..."
DASHBOARD_FILE=$(find . -name "dcgm-exporter-dashboard.json" -type f 2>/dev/null | head -1)
if [[ -n "$DASHBOARD_FILE" ]]; then
    az grafana dashboard create -n "$GRAFANA_NAME" -g "$RESOURCE_GROUP_NAME" \
        --definition "$(cat "$DASHBOARD_FILE")" -o none 2>/dev/null \
        && echo "  ✓ Dashboard imported" || echo "  ⚠ Import failed - import manually"
else
    echo "  ⚠ Dashboard file not found. Import manually in Grafana."
fi

# Summary
cat <<EOF

============================================================================
✅ GPU MONITORING SETUP COMPLETE!
============================================================================

📊 Resources: $MONITOR_NAME (Prometheus) + $GRAFANA_NAME (Grafana)
🌐 Grafana: $GRAFANA_URL
🔍 Test: DCGM_FI_DEV_GPU_UTIL, DCGM_FI_DEV_GPU_TEMP, DCGM_FI_DEV_FB_USED

⏱️  Metrics take 3-5 minutes to appear

🔧 Troubleshooting:
   kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400
   curl localhost:9400/metrics | grep DCGM

Next: ./scripts/04-build-and-push-image.sh
EOF