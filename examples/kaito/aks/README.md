# KAITO Inference on AKS

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites and AKS Environment Setup](#2-prerequisites-and-aks-environment-setup)
3. [Deployment Steps](#3-deployment-steps)
   
   3.1. [Install KAITO Operator](#31-install-kaito-operator)
   
   3.2. [Deploy a Model for Inference](#32-deploy-a-model-for-inference)
   
   3.3. [Test the Inference Endpoint](#33-test-the-inference-endpoint)

## 1. Introduction

This example demonstrates how to deploy and run inference workloads using the Kubernetes AI Toolchain Operator (KAITO) on Azure Kubernetes Service (AKS). KAITO automates the deployment and serving of large AI/ML models by managing GPU node provisioning, model downloading, and inference server deployment.

The implementation leverages several key technologies:

- **[KAITO (Kubernetes AI Toolchain Operator)](https://github.com/kaito-project/kaito)** - An operator that automates AI/ML inference workload deployment in Kubernetes clusters
- **[Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks)** - Microsoft's managed Kubernetes service
- **[Hugging Face Models](https://huggingface.co/models)** - Pre-trained models for various AI tasks
- **OpenAI-Compatible API** - Standard REST API for model inference

### Key Benefits of KAITO

- **Automated GPU Node Provisioning**: KAITO automatically manages GPU nodes based on model requirements
- **Model Management**: Handles downloading and caching of model weights from Hugging Face
- **Simplified Deployment**: Deploy models with a single Kubernetes manifest
- **OpenAI-Compatible Endpoints**: Provides familiar REST API for inference
- **Multiple Runtime Support**: Supports various inference runtimes (vLLM, Hugging Face Transformers)

## 2. Prerequisites and AKS Environment Setup

Before proceeding with KAITO deployment, ensure your AKS cluster meets the following requirements:

- **AKS Cluster** with KAITO addon enabled (recommended) or KAITO operator installed manually
- **GPU Node Pool** with appropriate VM SKUs (e.g., Standard_NC24ads_A100_v4, Standard_NC96ads_A100_v4)
- **Sufficient GPU Quota** in your Azure subscription for the selected VM SKU
- **kubectl** configured to access your AKS cluster
- **Azure CLI** installed and authenticated

### Option 1: Enable KAITO Addon (Recommended)

Enable KAITO when creating a new AKS cluster:

```bash
az aks create \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --node-count 1 \
  --enable-aks-kaito \
  --generate-ssh-keys
```

Or enable KAITO on an existing cluster:

```bash
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-aks-kaito
```

### Option 2: Manual KAITO Installation

If you prefer to install KAITO manually:

```bash
# Install using Helm
helm repo add kaito https://kaito-project.github.io/kaito
helm repo update
helm install kaito-workspace kaito/kaito-workspace --namespace kaito-workspace --create-namespace
```

### Verify KAITO Installation

```bash
# Check KAITO controller is running
kubectl get pods -n kaito-workspace

# Verify KAITO CRDs are installed
kubectl get crd workspaces.kaito.k8s.microsoft.com
```

### GPU Node Pool Setup

Ensure you have a GPU-enabled node pool. The specific VM SKU depends on your model requirements:

- **A100 GPUs**: Standard_NC24ads_A100_v4 (1x A100), Standard_NC48ads_A100_v4 (2x A100), Standard_NC96ads_A100_v4 (4x A100)
- **V100 GPUs**: Standard_NC6s_v3 (1x V100), Standard_NC12s_v3 (2x V100), Standard_NC24s_v3 (4x V100)

Create a GPU node pool if not already present:

```bash
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name gpunp \
  --node-count 1 \
  --node-vm-size Standard_NC24ads_A100_v4 \
  --labels kaito-node=true
```

## 3. Deployment Steps

### 3.1. Install KAITO Operator

If you used the addon method in the prerequisites, KAITO is already installed. Otherwise, ensure the KAITO operator is running:

```bash
# Check operator status
kubectl get deployment -n kaito-workspace

# View operator logs
kubectl logs -n kaito-workspace deployment/kaito-workspace-controller-manager
```

### 3.2. Deploy a Model for Inference

KAITO uses a `Workspace` custom resource to define model deployment specifications. The workspace includes:

- Model selection (from preset models or custom)
- Instance type (GPU VM SKU)
- Inference configuration (replicas, runtime)
- Optional: Resource limits and custom parameters

#### Quick Test with Phi-2 (2.7B Model)

For initial testing and validation, deploy the lightweight Phi-2 model from Microsoft:

```bash
kubectl apply -f manifests/phi2-workspace.yaml
```

This manifest configures:
- **Model**: microsoft/phi-2 (2.7B parameters)
- **GPU**: 1x A100 (Standard_NC24ads_A100_v4)
- **Runtime**: Hugging Face Transformers
- **Precision**: bfloat16 for optimal A100 performance

#### Production Deployment with Llama 3 8B

Deploy Meta's Llama 3 8B model for production workloads:

```bash
kubectl apply -f manifests/llama3-8b-workspace.yaml
```

This configuration includes:
- **Model**: meta-llama/Meta-Llama-3-8B-Instruct
- **GPU**: 1x A100 or 2x A100 depending on requirements
- **Runtime**: vLLM for high-throughput inference
- **Replicas**: Configurable for load balancing

#### Large Model Deployment with Llama 3 70B

For larger models requiring multiple GPUs:

```bash
kubectl apply -f manifests/llama3-70b-workspace.yaml
```

Configuration:
- **Model**: meta-llama/Meta-Llama-3-70B-Instruct
- **GPU**: 4x A100 (Standard_NC96ads_A100_v4)
- **Runtime**: vLLM with tensor parallelism
- **Optimization**: Pipeline parallelism for distributed inference

#### Monitor Deployment

Watch the workspace status:

```bash
# Check workspace status
kubectl get workspace

# Describe workspace for detailed information
kubectl describe workspace <workspace-name>

# Watch pod creation and model loading
kubectl get pods -w

# View model download and initialization logs
kubectl logs -f <workspace-pod-name>
```

The deployment process includes:
1. GPU node provisioning (if needed)
2. Model weight download from Hugging Face
3. Inference server initialization
4. Service endpoint creation

Typical deployment time:
- **Phi-2**: 5-10 minutes
- **Llama 3 8B**: 10-15 minutes
- **Llama 3 70B**: 15-25 minutes

### 3.3. Test the Inference Endpoint

Once the workspace is ready, KAITO creates a Kubernetes service for the inference endpoint.

#### Get Service Information

```bash
# List services
kubectl get svc

# Get service details
kubectl describe svc <workspace-name>-service
```

#### Local Testing with Port-Forward

For quick testing, use port-forwarding:

```bash
# Forward local port to inference service
kubectl port-forward svc/<workspace-name> 8080:80
```

#### Test with Phi-2

```bash
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2",
    "prompt": "What is Azure Kubernetes Service?",
    "max_tokens": 256,
    "temperature": 0.7
  }'
```

#### Test with Llama 3 (Chat Format)

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Meta-Llama-3-8B-Instruct",
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful AI assistant."
      },
      {
        "role": "user",
        "content": "Explain KAITO in simple terms."
      }
    ],
    "max_tokens": 512,
    "temperature": 0.7
  }'
```

#### Production Access with LoadBalancer

For production use, expose the service via Azure Load Balancer:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kaito-inference-lb
spec:
  type: LoadBalancer
  selector:
    app: <workspace-name>
  ports:
  - port: 80
    targetPort: 8080
```

Apply the LoadBalancer service:

```bash
kubectl apply -f manifests/loadbalancer-service.yaml

# Get external IP
kubectl get svc kaito-inference-lb
```

Wait for the `EXTERNAL-IP` to be assigned, then test:

```bash
curl -X POST http://<EXTERNAL-IP>/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2",
    "prompt": "Hello, world!",
    "max_tokens": 100
  }'
```

#### Python Client Example

```python
import requests
import json

# Configure endpoint
ENDPOINT_URL = "http://localhost:8080/v1/completions"

def generate_text(prompt, max_tokens=256):
    payload = {
        "model": "microsoft/phi-2",
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": 0.7
    }
    
    response = requests.post(
        ENDPOINT_URL,
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload)
    )
    
    if response.status_code == 200:
        result = response.json()
        return result['choices'][0]['text']
    else:
        raise Exception(f"Error: {response.status_code} - {response.text}")

# Example usage
prompt = "Explain what KAITO does:"
result = generate_text(prompt)
print(result)
```

## Configuration Options

### Workspace Parameters

- **`instanceType`**: Azure VM SKU for GPU nodes (e.g., Standard_NC24ads_A100_v4)
- **`modelId`**: Hugging Face model identifier (e.g., microsoft/phi-2)
- **`runtime`**: Inference runtime (huggingface, vllm)
- **`torch_dtype`**: Precision (bfloat16, float16, float32)
- **`replicas`**: Number of inference replicas for load balancing

### Model Selection

KAITO supports various preset models:

**Small Models (1-3B parameters)**:
- microsoft/phi-2 (2.7B)
- microsoft/phi-3-mini-4k-instruct (3.8B)
- stabilityai/stablelm-2-1_6b

**Medium Models (7-13B parameters)**:
- meta-llama/Meta-Llama-3-8B-Instruct
- mistralai/Mistral-7B-Instruct-v0.2
- tiiuae/falcon-7b-instruct

**Large Models (30B+ parameters)**:
- meta-llama/Meta-Llama-3-70B-Instruct
- tiiuae/falcon-40b-instruct

### Runtime Options

**Hugging Face Transformers**:
- Standard PyTorch-based inference
- Good for testing and smaller models
- Lower throughput, easier to debug

**vLLM**:
- High-performance inference engine
- Continuous batching for higher throughput
- Recommended for production workloads
- Supports tensor and pipeline parallelism

## Troubleshooting

### Workspace Not Ready

```bash
# Check workspace events
kubectl describe workspace <workspace-name>

# Check operator logs
kubectl logs -n kaito-workspace deployment/kaito-workspace-controller-manager
```

Common issues:
- Insufficient GPU quota
- Node provisioning delays
- Model download errors (check Hugging Face token if using gated models)

### Pod Crashes or OOM

```bash
# Check pod status
kubectl get pods

# View pod logs
kubectl logs <pod-name>

# Check resource usage
kubectl top pod <pod-name>
```

Solutions:
- Use larger VM SKU
- Reduce precision (float16 instead of float32)
- Enable tensor parallelism for large models

### Slow Model Loading

Model download times depend on:
- Model size
- Network bandwidth
- Hugging Face API rate limits

For faster loading:
- Use a Hugging Face Pro account
- Pre-cache models in container images
- Use persistent volumes for model caching

## Cleanup

Remove the workspace and associated resources:

```bash
# Delete workspace
kubectl delete workspace <workspace-name>

# KAITO will automatically clean up:
# - Inference pods
# - Services
# - GPU nodes (if auto-provisioned)

# Verify cleanup
kubectl get workspace
kubectl get pods
```

To completely uninstall KAITO:

```bash
# If installed via addon
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --disable-aks-kaito

# If installed via Helm
helm uninstall kaito-workspace -n kaito-workspace
```

## Performance Considerations

- **Batch Size**: Larger batches improve GPU utilization but increase latency
- **Precision**: bfloat16 recommended for A100 GPUs (hardware support, good accuracy)
- **Replicas**: Scale horizontally for higher throughput
- **VM SKU**: Choose based on model size and performance requirements
- **Model Caching**: Use persistent volumes to avoid re-downloading models

## Security Best Practices

- **Network Policies**: Restrict access to inference endpoints
- **Authentication**: Implement API authentication for production
- **Model Access**: Use Kubernetes secrets for Hugging Face tokens (gated models)
- **Resource Quotas**: Set namespace resource limits to prevent resource exhaustion
- **Image Scanning**: Ensure container images are scanned for vulnerabilities

## Additional Resources

- [KAITO GitHub Repository](https://github.com/kaito-project/kaito)
- [KAITO Documentation](https://kaito-project.github.io/kaito/)
- [Azure KAITO Quickstart](https://learn.microsoft.com/en-us/azure/aks/aks-extension-kaito)
- [Supported Models](https://github.com/kaito-project/kaito/blob/main/docs/models.md)
- [AKS GPU Best Practices](https://learn.microsoft.com/en-us/azure/aks/gpu-cluster)
