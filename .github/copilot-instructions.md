# GitHub Copilot Instructions for AI Infrastructure on Azure

## Project Overview

This repository collects architectural guidance and AI training examples designed to run on Azure AI Infrastructure. It provides practical implementations and reference architectures for large-scale AI workloads using Azure services.

**Primary Focus Areas:**
- **Infrastructure deployment**: Automated setup of Azure AI compute environments
- **AI/ML training workflows**: End-to-end examples for distributed training at scale
- **Infrastructure validation**: Performance testing and health monitoring tools
- **Storage optimization**: High-performance storage configurations for AI workloads

**Target Orchestration Platforms:**
- Azure Kubernetes Service (AKS) with GPU support
- Azure CycleCloud Workspace for Slurm
- Azure Machine Learning compute

## Repository Structure

```
├── .github/                          # GitHub workflows and configurations
├── examples/                         # AI training examples and use cases
│   ├── llm-foundry/                 # LLM Foundry MPT training examples
│   ├── megatron-lm/                 # MegatronLM GPT3-175B training
│   ├── nemo-run/                    # NVIDIA NeMo training examples
│   ├── dgx_benchmarking/            # DGX benchmark utilities
│   └── shared_storage/              # Shared storage configuration examples
├── infrastructure_references/        # Infrastructure deployment guides
│   ├── aks/                        # Azure Kubernetes Service setup
│   └── azure_cyclecloud_workspace_for_slurm/  # Slurm workspace setup
├── infrastructure_validations/       # Testing and validation tools
│   ├── aks/                        # AKS-specific validations
│   └── slurm/                      # Slurm-specific validations
└── storage_references/              # Storage configuration examples
```

### Key Directory Purposes

- **`examples/`**: Complete end-to-end AI training workflows with infrastructure setup
- **`infrastructure_references/`**: Reusable infrastructure deployment scripts and configurations
- **`infrastructure_validations/`**: Tools to verify infrastructure performance and health
- **`storage_references/`**: High-performance storage configurations and optimizations

## Technology Stack and File Types

### Languages and Frameworks
- **Bash scripts**: Infrastructure deployment and automation (`.sh` files)
- **Python**: Data preprocessing, training scripts, and utilities (`.py` files)
- **YAML**: Kubernetes manifests, Helm values, and CI/CD workflows (`.yaml`, `.yml` files)
- **Helm charts**: Kubernetes application packaging and deployment
- **Dockerfile**: Container definitions for training environments

### Infrastructure as Code
- **Kubernetes manifests**: Pod specs, deployments, services, and custom resources
- **Helm templates**: Parameterized Kubernetes deployments using Go templating
- **Slurm job scripts**: HPC workload scheduling and resource management

## Coding Standards and Conventions

### Shell Scripts
- Use `#!/usr/bin/env bash` shebang
- Enable strict error handling: `set -euo pipefail`
- Use environment variables with defaults: `${VAR_NAME:=default_value}`
- Document required and optional environment variables in script headers
- Use meaningful variable names in UPPER_CASE for environment variables

### Python Code
- Follow PEP 8 style guidelines
- Use descriptive function and variable names
- Include docstrings for functions and modules
- Handle exceptions appropriately for infrastructure operations

### YAML and Helm
- Use 2-space indentation consistently
- Place comments above the line they describe
- Use meaningful resource names following Kubernetes conventions
- Helm templates should include helper functions in `_helpers.tpl`
- Use `{{ include "chart.labels" . }}` for consistent labeling

### Documentation
- All directories should contain a `README.md` file
- Use clear section headers and table of contents for long documents
- Include prerequisites, setup instructions, and usage examples
- Provide environment variable documentation with descriptions

## Infrastructure Deployment Patterns

### Common Environment Variables
When working with deployment scripts, these variables are commonly used:

**Azure-specific:**
- `AZURE_REGION`: Target Azure region (e.g., "eastus", "westus2")
- `AZURE_RESOURCE_GROUP`: Resource group name (default: "ai-infra-aks")
- `CLUSTER_NAME`: AKS cluster name (default: "ai-infra")

**Compute configuration:**
- `NODE_POOL_VM_SIZE`: GPU VM SKUs (e.g., "Standard_NC24ads_A100_v4")
- `NODE_POOL_NODE_COUNT`: Number of compute nodes (default: 2)

**Training parameters:**
- `GLOBAL_BATCH_SIZE`: Global batch size for distributed training
- `TENSOR_MODEL_PARALLEL_SIZE`: Tensor parallelism degree
- `PIPELINE_MODEL_PARALLEL_SIZE`: Pipeline parallelism degree

### Deployment Script Patterns
Most deployment scripts follow this pattern:
1. Environment variable validation and defaults
2. Prerequisites checking (CLI tools, permissions)
3. Infrastructure provisioning (AKS cluster, storage accounts)
4. Operator installation (GPU operators, PyTorch operators)
5. Application deployment (Helm chart installation)
6. Validation and monitoring setup

## AI Training Workflow Patterns

### Distributed Training Setup
- Multi-node, multi-GPU configurations using NCCL for communication
- InfiniBand networking optimization for high-throughput communication
- Checkpoint saving and resumption for fault tolerance
- TensorBoard integration for training monitoring

### Storage Patterns
- **High-performance datasets**: Azure Managed Lustre File System (AMLFS)
- **Large dataset storage**: Azure Blob Storage with blobfuse mounting
- **Checkpoint storage**: Azure NetApp Files for high IOPS requirements
- **Container images**: Squashfs formats for fast container startup

## Special Considerations

### GPU and Networking
- RDMA/InfiniBand configuration for optimal GPU-to-GPU communication
- SHARP (Scalable Hierarchical Aggregation and Reduction Protocol) support
- NCCL environment variable tuning for Azure networking topology

### Security and Compliance
- Follow Microsoft security guidelines and policies
- Use managed identities for Azure service authentication
- Implement least-privilege access principles
- Regular security scanning through GitHub Actions workflows

### Performance Optimization
- Node affinity and topology-aware scheduling
- Container image optimization with multi-stage builds
- Storage performance tuning for training workloads
- Network optimization for distributed training communication

When suggesting code changes or new features, consider:
1. Scalability for large AI workloads
2. Azure service integration best practices  
3. Cost optimization opportunities
4. Monitoring and observability requirements
5. Fault tolerance and error recovery mechanisms