#!/bin/bash

# Fix relative links between README files to point to Docusaurus pages

echo "Fixing relative links in markdown files..."

# Define mappings from original README paths to Docusaurus page paths
declare -A link_map=(
  # Infrastructure
  ["infrastructure_references/azure_cyclecloud_workspace_for_slurm/README.md"]="/docs/infrastructure/cyclecloud-slurm"
  ["infrastructure_references/aks/README.md"]="/docs/infrastructure/aks-cluster"
  ["../../infrastructure_references/aks/README.md"]="/docs/infrastructure/aks-cluster"
  ["../../../infrastructure_references/aks/README.md"]="/docs/infrastructure/aks-cluster"
  ["../../../../infrastructure_references/aks/README.md"]="/docs/infrastructure/aks-cluster"
  ["../../../infrastructure_references/azure_cyclecloud_workspace_for_slurm/README.md"]="/docs/infrastructure/cyclecloud-slurm"
  ["../../../../infrastructure_references/azure_cyclecloud_workspace_for_slurm/README.md"]="/docs/infrastructure/cyclecloud-slurm"
  ["../../../infrastructure_references/azure_cyclecloud_workspaces_for_slurm/README.md"]="/docs/infrastructure/cyclecloud-slurm"
  
  # Validations - AKS
  ["infrastructure_validations/aks/blobfuse/README.md"]="/docs/validations/aks/storage-performance"
  ["infrastructure_validations/aks/NCCL/README.md"]="/docs/validations/aks/nccl-testing"
  ["infrastructure_validations/aks/NHC/README.md"]="/docs/validations/aks/node-health-checks"
  ["../../infrastructure-validations/nhc-aks.md"]="/docs/validations/aks/node-health-checks"
  ["../infrastructure-validations/nhc-aks.md"]="/docs/validations/aks/node-health-checks"
  
  # Validations - Slurm
  ["infrastructure_validations/slurm/NCCL/README.md"]="/docs/validations/slurm/nccl-testing"
  ["infrastructure_validations/slurm/NHC/README.md"]="/docs/validations/slurm/node-health-checks"
  ["infrastructure_validations/slurm/thermal_test/README.md"]="/docs/validations/slurm/thermal-testing"
  ["../../infrastructure-validations/nccl-slurm.md"]="/docs/validations/slurm/nccl-testing"
  
  # Examples
  ["examples/megatron-lm/GPT3-175B/slurm/README.md"]="/docs/examples/ai-training/megatron-gpt3-slurm"
  ["examples/megatron-lm/GPT3-175B/aks/README.md"]="/docs/examples/ai-training/megatron-gpt3-aks"
  ["examples/llm-foundry/slurm/README.md"]="/docs/examples/ai-training/llm-foundry-slurm"
  ["examples/llm-foundry/aks/README.md"]="/docs/examples/ai-training/llm-foundry-aks"
  ["../../examples/megatron-lm/gpt3-175b-aks.md"]="/docs/examples/ai-training/megatron-gpt3-aks"
  ["../docker/README.md"]="/docs/examples/ai-training/llm-foundry-docker"
  
  # Storage
  ["storage_references/aks/shared_storage/README.md"]="/docs/examples/shared-storage/shared-storage-aks"
  ["../../../storage_references/aks/shared_storage/README.md"]="/docs/examples/shared-storage/shared-storage-aks"
  ["../../../shared_storage/aks/README.md"]="/docs/examples/shared-storage/shared-storage-aks"
  ["storage_references/slurm/squashed_images/README.md"]="/docs/guidance/squashed-images"
  ["../../../../storage_references/squashed_images/README.md"]="/docs/guidance/squashed-images"
  
  # Utilities
  ["utilities/aks/node_labeler/README.md"]="/docs/guidance/node-labeler"
  ["utilities/aks/torset_labeler/README.md"]="/docs/guidance/torset-labeler"
  ["../../torset_labeler/helm/README.md"]="/docs/guidance/torset-labeler"
  ["../utilities/node-labeler.md"]="/docs/guidance/node-labeler"
  ["../utilities/torset-labeler.md"]="/docs/guidance/torset-labeler"
)

# Process all markdown files
find docs -name "*.md" -type f | while read file; do
  echo "Processing: $file"
  
  # Create a temporary file
  tmp_file=$(mktemp)
  cp "$file" "$tmp_file"
  
  # Replace each link pattern
  for old_path in "${!link_map[@]}"; do
    new_path="${link_map[$old_path]}"
    
    # Handle markdown links: [text](path)
    sed -i "s|\](${old_path})|](${new_path})|g" "$tmp_file"
    
    # Handle markdown links with fragments: [text](path#fragment)
    sed -i "s|\](${old_path}#\([^)]*\))|](${new_path}#\1)|g" "$tmp_file"
  done
  
  # Copy back if changes were made
  if ! cmp -s "$file" "$tmp_file"; then
    cp "$tmp_file" "$file"
    echo "  ✓ Updated links in $file"
  fi
  
  rm "$tmp_file"
done

echo "✅ Relative link fixing complete!"
