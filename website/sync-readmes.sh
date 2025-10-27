#!/bin/bash

# Script to copy README files from the repository into Docusaurus docs with proper frontmatter

# Set base path - we're in website subdirectory, parent has the actual content
BASE_PATH=".."

# Infrastructure
echo "Copying Infrastructure READMEs..."
cat > docs/infrastructure/cyclecloud-slurm.md << 'HEREDOC'
---
title: Azure CycleCloud Slurm Workspace AI Cluster
sidebar_label: CycleCloud Slurm (Slurm)
tags: [slurm, infrastructure]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_references/azure_cyclecloud_workspace_for_slurm/README.md >> docs/infrastructure/cyclecloud-slurm.md

cat > docs/infrastructure/aks-cluster.md << 'HEREDOC'
---
title: Azure Kubernetes Service Cluster
sidebar_label: AKS Cluster (AKS)
tags: [aks, infrastructure]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_references/aks/README.md >> docs/infrastructure/aks-cluster.md

# Validations - AKS
echo "Copying AKS Validation READMEs..."
cat > docs/validations/aks/storage-performance.md << 'HEREDOC'
---
title: Blobfuse Storage Performance Testing
sidebar_label: Storage Performance
tags: [aks, validation, storage]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_validations/aks/blobfuse/README.md >> docs/validations/aks/storage-performance.md

cat > docs/validations/aks/nccl-testing.md << 'HEREDOC'
---
title: NCCL All-reduce Testing (AKS)
sidebar_label: NCCL Testing
tags: [aks, validation, nccl]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_validations/aks/NCCL/README.md >> docs/validations/aks/nccl-testing.md

cat > docs/validations/aks/node-health-checks.md << 'HEREDOC'
---
title: Node Health Checks (AKS)
sidebar_label: Node Health Checks
tags: [aks, validation, health]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_validations/aks/NHC/README.md >> docs/validations/aks/node-health-checks.md

# Validations - Slurm
echo "Copying Slurm Validation READMEs..."
cat > docs/validations/slurm/nccl-testing.md << 'HEREDOC'
---
title: NCCL All-reduce Testing (Slurm)
sidebar_label: NCCL Testing
tags: [slurm, validation, nccl]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_validations/slurm/NCCL/README.md >> docs/validations/slurm/nccl-testing.md

cat > docs/validations/slurm/node-health-checks.md << 'HEREDOC'
---
title: Node Health Checks (Slurm)
sidebar_label: Node Health Checks
tags: [slurm, validation, health]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_validations/slurm/NHC/README.md >> docs/validations/slurm/node-health-checks.md

cat > docs/validations/slurm/thermal-testing.md << 'HEREDOC'
---
title: Thermal Testing
sidebar_label: Thermal Testing
tags: [slurm, validation, thermal]
---

HEREDOC
cat ${BASE_PATH}/infrastructure_validations/slurm/thermal_test/README.md >> docs/validations/slurm/thermal-testing.md

# Examples - AI Training
echo "Copying AI Training Example READMEs..."
cat > docs/examples/ai-training/megatron-gpt3-slurm.md << 'HEREDOC'
---
title: MegatronLM GPT3-175B Training (Slurm)
sidebar_label: MegatronLM GPT3-175B (Slurm)
tags: [slurm, training, megatron, gpt3]
---

HEREDOC
cat ${BASE_PATH}/examples/megatron-lm/GPT3-175B/slurm/README.md >> docs/examples/ai-training/megatron-gpt3-slurm.md

cat > docs/examples/ai-training/megatron-gpt3-aks.md << 'HEREDOC'
---
title: MegatronLM GPT3-175B Training (AKS)
sidebar_label: MegatronLM GPT3-175B (AKS)
tags: [aks, training, megatron, gpt3]
---

HEREDOC
cat ${BASE_PATH}/examples/megatron-lm/GPT3-175B/aks/README.md >> docs/examples/ai-training/megatron-gpt3-aks.md

cat > docs/examples/ai-training/llm-foundry-slurm.md << 'HEREDOC'
---
title: LLM Foundry Training (Slurm)
sidebar_label: LLM Foundry (Slurm)
tags: [slurm, training, llm-foundry]
---

HEREDOC
cat ${BASE_PATH}/examples/llm-foundry/slurm/README.md >> docs/examples/ai-training/llm-foundry-slurm.md

cat > docs/examples/ai-training/llm-foundry-aks.md << 'HEREDOC'
---
title: LLM Foundry Training (AKS)
sidebar_label: LLM Foundry (AKS)
tags: [aks, training, llm-foundry]
---

HEREDOC
cat ${BASE_PATH}/examples/llm-foundry/aks/README.md >> docs/examples/ai-training/llm-foundry-aks.md

cat > docs/examples/ai-training/llm-foundry-docker.md << 'HEREDOC'
---
title: LLM Foundry Docker Build
sidebar_label: LLM Foundry Docker
tags: [docker, llm-foundry]
---

HEREDOC
cat ${BASE_PATH}/examples/llm-foundry/docker/README.md >> docs/examples/ai-training/llm-foundry-docker.md

# Examples - Shared Storage
echo "Copying Shared Storage Example READMEs..."
cat > docs/examples/shared-storage/shared-storage-aks.md << 'HEREDOC'
---
title: Shared Storage Solutions (AKS)
sidebar_label: Shared Storage (AKS)
tags: [aks, storage]
---

HEREDOC
cat ${BASE_PATH}/storage_references/aks/shared_storage/README.md >> docs/examples/shared-storage/shared-storage-aks.md

# Guidance
echo "Copying Guidance READMEs..."
cat > docs/guidance/node-labeler.md << 'HEREDOC'
---
title: Node Labeler
sidebar_label: Node Labeler (AKS)
tags: [aks, utilities]
---

HEREDOC
cat ${BASE_PATH}/utilities/aks/node_labeler/README.md >> docs/guidance/node-labeler.md

cat > docs/guidance/torset-labeler.md << 'HEREDOC'
---
title: Torset Labeler
sidebar_label: Torset Labeler (AKS)
tags: [aks, utilities]
---

HEREDOC
cat ${BASE_PATH}/utilities/aks/torset_labeler/helm/README.md >> docs/guidance/torset-labeler.md

cat > docs/guidance/squashed-images.md << 'HEREDOC'
---
title: Squashed Images
sidebar_label: Squashed Images (Slurm)
tags: [slurm, storage]
---

HEREDOC
cat ${BASE_PATH}/storage_references/slurm/squashed_images/README.md >> docs/guidance/squashed-images.md

echo "✅ All README files copied successfully!"
